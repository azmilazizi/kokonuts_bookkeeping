import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app/app_state_scope.dart';
import '../services/receipt_scan_service.dart';
import '../services/vendors_service.dart';
import '../widgets/searchable_dropdown_form_field.dart';

class PurchaseOrderFormScreen extends StatefulWidget {
  const PurchaseOrderFormScreen({super.key, this.extracted});

  final Map<String, dynamic>? extracted;

  @override
  State<PurchaseOrderFormScreen> createState() =>
      _PurchaseOrderFormScreenState();
}

class _PurchaseOrderFormScreenState extends State<PurchaseOrderFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _notesController = TextEditingController();
  final _taxController = TextEditingController(text: '0.00');

  DateTime _orderDate = DateTime.now();
  String? _selectedVendorId;
  List<_LineItem> _lineItems = [];

  List<VendorSummary> _vendors = [];
  bool _isLoadingData = true;
  bool _isSaving = false;
  String? _vendorLoadError;

  bool get _isLowConfidence =>
      (widget.extracted?['confidence'] as String?) == 'low';

  double get _subtotal =>
      _lineItems.fold(0.0, (sum, item) => sum + item.total);
  double get _tax => double.tryParse(_taxController.text) ?? 0.0;
  double get _grandTotal => _subtotal + _tax;

  @override
  void initState() {
    super.initState();
    _taxController.addListener(_recalculate);
    _prefillFromExtracted();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadData());
  }

  void _recalculate() => setState(() {});

  void _prefillFromExtracted() {
    final e = widget.extracted;
    if (e == null) return;

    final dateStr = e['date'] as String?;
    if (dateStr != null) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) _orderDate = parsed;
    }

    final receiptNum = e['receipt_number'] as String?;
    if (receiptNum != null && receiptNum.isNotEmpty) {
      _notesController.text = 'Receipt ref: $receiptNum';
    }

    final tax = e['tax'];
    if (tax != null) {
      _taxController.text = (tax as num).toStringAsFixed(2);
    }

    final items = e['items'];
    if (items is List && items.isNotEmpty) {
      _lineItems = items.whereType<Map<String, dynamic>>().map((item) {
        final qty = (item['qty'] as num?)?.toDouble() ?? 1.0;
        final unitPrice = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        return _LineItem(
          nameController: TextEditingController(
            text: item['description'] as String? ?? '',
          ),
          qtyController: TextEditingController(text: qty.toString()),
          unitPriceController:
              TextEditingController(text: unitPrice.toStringAsFixed(2)),
        )..attachListeners(_recalculate);
      }).toList();
    }

    if (_lineItems.isEmpty) {
      _lineItems = [_LineItem.blank()..attachListeners(_recalculate)];
    }
  }

  Future<void> _loadData() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (token == null) {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
          _vendorLoadError = 'Not logged in';
        });
      }
      return;
    }

    final headers = _buildHeaders(appState, token);
    try {
      final vendors = await VendorsService().fetchVendors(headers: headers);
      if (!mounted) return;
      setState(() {
        _vendors = vendors;
        _isLoadingData = false;
        _tryMatchVendor();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingData = false;
        _vendorLoadError = e.toString();
      });
    }
  }

  void _tryMatchVendor() {
    final vendorName = widget.extracted?['vendor'] as String?;
    if (vendorName == null || vendorName.isEmpty || _vendors.isEmpty) return;

    final normalized = vendorName.toLowerCase().trim();
    VendorSummary? matched = _vendors
        .where((v) => v.name.toLowerCase().trim() == normalized)
        .firstOrNull;
    matched ??= _vendors
        .where((v) {
          final vn = v.name.toLowerCase();
          return vn.contains(normalized) || normalized.contains(vn);
        })
        .firstOrNull;

    if (matched != null) _selectedVendorId = matched.id;
  }

  void _addLineItem() {
    setState(() {
      _lineItems.add(_LineItem.blank()..attachListeners(_recalculate));
    });
  }

  void _removeLineItem(int index) {
    setState(() {
      _lineItems[index].dispose();
      _lineItems.removeAt(index);
      if (_lineItems.isEmpty) {
        _lineItems.add(_LineItem.blank()..attachListeners(_recalculate));
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final appState = AppStateScope.of(context);
      final token = await appState.getValidAuthToken();
      if (token == null) throw Exception('Not logged in');

      final vendorId =
          _selectedVendorId != null ? (int.tryParse(_selectedVendorId!) ?? 0) : 0;
      final vendorName = _selectedVendorId != null
          ? _vendors
                .where((v) => v.id == _selectedVendorId)
                .map((v) => v.name)
                .firstOrNull ??
              ''
          : '';

      final items = _lineItems.map((item) {
        final qty = double.tryParse(item.qtyController.text) ?? 0;
        final unitPrice =
            double.tryParse(item.unitPriceController.text) ?? 0;
        return {
          'description': item.nameController.text.trim(),
          'item_id': 0,
          'qty': qty,
          'unit_price': unitPrice,
          'total': qty * unitPrice,
        };
      }).toList();

      final notes = _notesController.text.trim();
      final body = {
        'extracted': {
          'vendor': vendorName,
          'date': DateFormat('yyyy-MM-dd').format(_orderDate),
          'receipt_number': notes.isNotEmpty ? notes : null,
          'items': items,
          'subtotal': _subtotal,
          'tax': _tax,
          'grand_total': _grandTotal,
        },
        'record_type': 'purchase_order',
        'vendor_id': vendorId,
      };

      final service = ReceiptScanService(
        baseUrl: 'https://crm.kokonuts.my',
        headers: _buildHeaders(appState, token),
      );
      await service.confirm(body);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Purchase order saved')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(e.toString().replaceFirst('Exception: ', '')),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Map<String, String> _buildHeaders(dynamic appState, String token) {
    final rawToken = ((appState.rawAuthToken as String?) ?? token).trim();
    final sanitized = token
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    final authValue = rawToken
        .replaceFirst(RegExp(r'^Bearer\s+', caseSensitive: false), '')
        .trim();
    return {
      'authtoken': authValue.isNotEmpty ? authValue : sanitized,
      'Authorization': 'Bearer $sanitized',
      'Accept': 'application/json',
    };
  }

  @override
  void dispose() {
    _notesController.dispose();
    _taxController.dispose();
    for (final item in _lineItems) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fmt = NumberFormat('#,##0.00');

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.extracted != null
              ? 'Review Purchase Order'
              : 'New Purchase Order',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            if (_isLowConfidence)
              _WarningBanner(
                message:
                    'Low confidence — please review all fields carefully',
              ),

            // Vendor
            const _SectionLabel('Vendor'),
            if (_isLoadingData)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Row(
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    SizedBox(width: 12),
                    Text('Loading vendors…'),
                  ],
                ),
              )
            else if (_vendorLoadError != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text(
                  'Could not load vendors: $_vendorLoadError',
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              )
            else
              SearchableDropdownFormField<String>(
                key: ValueKey('vendor_$_selectedVendorId'),
                items: _vendors.map((v) => v.id).toList(),
                itemToString: (id) => _vendors
                    .where((v) => v.id == id)
                    .map((v) => v.name)
                    .firstOrNull ??
                    id,
                initialValue: _selectedVendorId,
                onChanged: (id) => setState(() => _selectedVendorId = id),
                decoration: const InputDecoration(
                  labelText: 'Vendor',
                  border: OutlineInputBorder(),
                ),
                hintText: 'Select a vendor',
                dialogTitle: 'Select vendor',
              ),
            const SizedBox(height: 16),

            // Order Date
            const _SectionLabel('Order Date'),
            _DatePickerField(
              value: _orderDate,
              onChanged: (d) => setState(() => _orderDate = d),
            ),
            const SizedBox(height: 16),

            // Notes
            TextFormField(
              controller: _notesController,
              decoration: const InputDecoration(
                labelText: 'Notes',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 24),

            // Line Items
            Row(
              children: [
                Text('Line Items', style: theme.textTheme.titleMedium),
                const Spacer(),
                TextButton.icon(
                  onPressed: _isSaving ? null : _addLineItem,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Item'),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Line item header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Text(
                      'Description',
                      style: theme.textTheme.labelSmall,
                    ),
                  ),
                  Expanded(
                    child: Text(
                      'Qty',
                      style: theme.textTheme.labelSmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Unit Price',
                      style: theme.textTheme.labelSmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      'Total',
                      style: theme.textTheme.labelSmall,
                      textAlign: TextAlign.right,
                    ),
                  ),
                  const SizedBox(width: 36),
                ],
              ),
            ),
            const Divider(),

            ..._lineItems.asMap().entries.map((entry) {
              final index = entry.key;
              final item = entry.value;
              return _LineItemRow(
                key: ObjectKey(item),
                item: item,
                onDelete: () => _removeLineItem(index),
                enabled: !_isSaving,
              );
            }),

            const Divider(height: 32),

            // Totals
            _TotalsRow(label: 'Subtotal', value: fmt.format(_subtotal)),
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(
                  child: Text('Tax', style: TextStyle(fontSize: 14)),
                ),
                SizedBox(
                  width: 120,
                  child: TextFormField(
                    controller: _taxController,
                    textAlign: TextAlign.right,
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                        RegExp(r'^\d*\.?\d{0,2}'),
                      ),
                    ],
                    decoration: const InputDecoration(
                      isDense: true,
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            _TotalsRow(
              label: 'Grand Total',
              value: fmt.format(_grandTotal),
              bold: true,
            ),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _isSaving ? null : _save,
                  child: const Text('Save Draft'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton(
                  onPressed: _isSaving ? null : _save,
                  child: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Line item data model
// ---------------------------------------------------------------------------

class _LineItem {
  _LineItem({
    required this.nameController,
    required this.qtyController,
    required this.unitPriceController,
  });

  factory _LineItem.blank() => _LineItem(
        nameController: TextEditingController(),
        qtyController: TextEditingController(text: '1'),
        unitPriceController: TextEditingController(text: '0.00'),
      );

  final TextEditingController nameController;
  final TextEditingController qtyController;
  final TextEditingController unitPriceController;

  double get qty => double.tryParse(qtyController.text) ?? 0;
  double get unitPrice => double.tryParse(unitPriceController.text) ?? 0;
  double get total => qty * unitPrice;

  void attachListeners(VoidCallback listener) {
    qtyController.addListener(listener);
    unitPriceController.addListener(listener);
  }

  void dispose() {
    nameController.dispose();
    qtyController.dispose();
    unitPriceController.dispose();
  }
}

// ---------------------------------------------------------------------------
// Line item row widget
// ---------------------------------------------------------------------------

class _LineItemRow extends StatelessWidget {
  const _LineItemRow({
    super.key,
    required this.item,
    required this.onDelete,
    required this.enabled,
  });

  final _LineItem item;
  final VoidCallback onDelete;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final total = NumberFormat('#,##0.00').format(item.total);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: TextFormField(
              controller: item.nameController,
              enabled: enabled,
              decoration: const InputDecoration(
                isDense: true,
                hintText: 'Item description',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: TextFormField(
              controller: item.qtyController,
              enabled: enabled,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d*'),
                ),
              ],
              decoration: const InputDecoration(
                isDense: true,
                hintText: '1',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: TextFormField(
              controller: item.unitPriceController,
              enabled: enabled,
              textAlign: TextAlign.right,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(
                  RegExp(r'^\d*\.?\d{0,2}'),
                ),
              ],
              decoration: const InputDecoration(
                isDense: true,
                hintText: '0.00',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            flex: 2,
            child: Text(
              total,
              textAlign: TextAlign.right,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline, size: 18),
            onPressed: enabled ? onDelete : null,
            visualDensity: VisualDensity.compact,
            color: Colors.red,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared small widgets
// ---------------------------------------------------------------------------

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Text(
          text,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      );
}

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({required this.value, required this.onChanged});

  final DateTime value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    final display = DateFormat('dd/MM/yyyy').format(value);
    return InkWell(
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: value,
          firstDate: DateTime(2000),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      borderRadius: BorderRadius.circular(4),
      child: InputDecorator(
        decoration: const InputDecoration(
          border: OutlineInputBorder(),
          suffixIcon: Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(display),
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.value,
    this.bold = false,
  });

  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = bold
        ? Theme.of(context)
              .textTheme
              .bodyMedium
              ?.copyWith(fontWeight: FontWeight.w600)
        : Theme.of(context).textTheme.bodyMedium;
    return Row(
      children: [
        Expanded(child: Text(label, style: style)),
        Text(value, style: style),
      ],
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.amber.shade100,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.amber.shade400),
        ),
        child: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: Colors.amber.shade800, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '⚠ $message',
                style: TextStyle(color: Colors.amber.shade900, fontSize: 13),
              ),
            ),
          ],
        ),
      );
}
