import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app/app_state_scope.dart';
import '../services/expenses_service.dart';
import '../services/payment_modes_service.dart';
import '../services/receipt_scan_service.dart';
import '../services/vendors_service.dart';
import '../widgets/searchable_dropdown_form_field.dart';

class ExpenseFormScreen extends StatefulWidget {
  const ExpenseFormScreen({super.key, this.extracted});

  final Map<String, dynamic>? extracted;

  @override
  State<ExpenseFormScreen> createState() => _ExpenseFormScreenState();
}

class _ExpenseFormScreenState extends State<ExpenseFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _amountController = TextEditingController(text: '0.00');
  final _noteController = TextEditingController();

  DateTime _date = DateTime.now();
  String? _selectedVendorId;
  String? _selectedCategoryId;
  String? _selectedPaymentModeId;

  List<VendorSummary> _vendors = [];
  List<ExpenseCategory> _categories = [];
  List<PaymentMode> _paymentModes = [];
  bool _isLoadingData = true;
  bool _isSaving = false;
  String? _loadError;
  bool _initialLoadDone = false;

  bool get _isLowConfidence =>
      (widget.extracted?['confidence'] as String?) == 'low';

  @override
  void initState() {
    super.initState();
    _prefillFromExtracted();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialLoadDone) {
      _initialLoadDone = true;
      _loadData();
    }
  }

  void _prefillFromExtracted() {
    final e = widget.extracted;
    if (e == null) return;

    // Expense name ← comma-separated item descriptions
    final items = e['items'];
    if (items is List && items.isNotEmpty) {
      final descriptions = items
          .whereType<Map<String, dynamic>>()
          .map((item) => (item['description'] as String? ?? '').trim())
          .where((s) => s.isNotEmpty)
          .join(', ');
      if (descriptions.isNotEmpty) _nameController.text = descriptions;
    }

    // Date
    final dateStr = e['date'] as String?;
    if (dateStr != null) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) _date = parsed;
    }

    // Amount ← grand_total
    final amount = e['grand_total'] ?? e['subtotal'];
    if (amount != null) {
      _amountController.text = (amount as num).toStringAsFixed(2);
    }

    // Note: leave empty
  }

  Future<void> _loadData() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (token == null) {
      if (mounted) {
        setState(() {
          _isLoadingData = false;
          _loadError = 'Not logged in';
        });
      }
      return;
    }

    final headers = _buildHeaders(appState, token);
    try {
      final results = await Future.wait([
        VendorsService().fetchVendors(headers: headers),
        ExpensesService().fetchCategories(headers: headers),
        PaymentModesService().fetchPaymentModes(headers: headers),
      ]);
      if (!mounted) return;
      setState(() {
        _vendors = results[0] as List<VendorSummary>;
        _categories = results[1] as List<ExpenseCategory>;
        _paymentModes = results[2] as List<PaymentMode>;
        _isLoadingData = false;
        _tryMatchVendor();
        _tryMatchPaymentMode();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoadingData = false;
        _loadError = e.toString();
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
    matched ??= _bestWordOverlapVendor(normalized);

    if (matched != null) _selectedVendorId = matched.id;
  }

  VendorSummary? _bestWordOverlapVendor(String normalized) {
    final queryWords = normalized.split(RegExp(r'\s+')).toSet();
    int bestScore = 0;
    VendorSummary? best;
    for (final v in _vendors) {
      final score = queryWords
          .intersection(v.name.toLowerCase().split(RegExp(r'\s+')).toSet())
          .length;
      if (score > bestScore) {
        bestScore = score;
        best = v;
      }
    }
    return best;
  }

  void _tryMatchPaymentMode() {
    final paymentMethod = widget.extracted?['payment_method'] as String?;
    if (paymentMethod == null || paymentMethod.isEmpty || _paymentModes.isEmpty) return;

    final normalized = paymentMethod.toLowerCase().trim();
    PaymentMode? matched = _paymentModes
        .where((m) => m.name.toLowerCase().trim() == normalized)
        .firstOrNull;
    matched ??= _paymentModes
        .where((m) {
          final mn = m.name.toLowerCase();
          return mn.contains(normalized) || normalized.contains(mn);
        })
        .firstOrNull;
    if (matched == null) {
      final queryWords = normalized.split(RegExp(r'\s+')).toSet();
      int bestScore = 0;
      for (final m in _paymentModes) {
        final score = queryWords
            .intersection(m.name.toLowerCase().split(RegExp(r'\s+')).toSet())
            .length;
        if (score > bestScore) {
          bestScore = score;
          matched = m;
        }
      }
    }

    if (matched != null) _selectedPaymentModeId = matched.id;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);
    try {
      final appState = AppStateScope.of(context);
      final token = await appState.getValidAuthToken();
      if (token == null) throw Exception('Not logged in');

      final vendorId = _selectedVendorId != null
          ? (int.tryParse(_selectedVendorId!) ?? 0)
          : 0;
      final categoryId = _selectedCategoryId != null
          ? (int.tryParse(_selectedCategoryId!) ?? 0)
          : 0;
      final paymentModeId = _selectedPaymentModeId != null
          ? int.tryParse(_selectedPaymentModeId!)
          : null;

      final body = {
        'extracted': {
          'vendor': _nameController.text.trim(),
          'date': DateFormat('yyyy-MM-dd').format(_date),
          'grand_total': double.tryParse(_amountController.text) ?? 0.0,
          'items': <Map<String, dynamic>>[],
        },
        'record_type': 'expense',
        'vendor_id': vendorId,
        'category': categoryId,
        if (paymentModeId != null) 'paymentmode': paymentModeId,
      };

      final service = ReceiptScanService(
        baseUrl: 'https://crm.kokonuts.my',
        headers: _buildHeaders(appState, token),
      );
      await service.confirm(body);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense saved')),
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
    _nameController.dispose();
    _amountController.dispose();
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.extracted != null ? 'Review Expense' : 'New Expense',
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
          children: [
            if (_isLowConfidence)
              _WarningBanner(
                message: 'Low confidence — please review all fields carefully',
              ),

            if (_loadError != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  'Could not load form data: $_loadError',
                  style: TextStyle(color: theme.colorScheme.error),
                ),
              ),

            // Expense Name
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: 'Expense Name',
                border: OutlineInputBorder(),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 16),

            // Date
            _DatePickerField(
              label: 'Expense Date',
              value: _date,
              onChanged: (d) => setState(() => _date = d),
            ),
            const SizedBox(height: 16),

            // Amount
            TextFormField(
              controller: _amountController,
              decoration: const InputDecoration(
                labelText: 'Amount',
                border: OutlineInputBorder(),
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
              ],
              validator: (v) {
                final parsed = double.tryParse(v ?? '');
                if (parsed == null) return 'Enter a valid amount';
                return null;
              },
            ),
            const SizedBox(height: 16),

            // Vendor (optional)
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
                    Text('Loading form data…'),
                  ],
                ),
              )
            else ...[
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
                  labelText: 'Vendor (optional)',
                  border: OutlineInputBorder(),
                ),
                hintText: 'Select a vendor',
                dialogTitle: 'Select vendor',
              ),
              const SizedBox(height: 16),

              // Category (required)
              SearchableDropdownFormField<String>(
                key: ValueKey('category_$_selectedCategoryId'),
                items: _categories.map((c) => c.id).toList(),
                itemToString: (id) => _categories
                    .where((c) => c.id == id)
                    .map((c) => c.name)
                    .firstOrNull ??
                    id,
                initialValue: _selectedCategoryId,
                onChanged: (id) => setState(() => _selectedCategoryId = id),
                decoration: const InputDecoration(
                  labelText: 'Expense Category',
                  border: OutlineInputBorder(),
                ),
                hintText: 'Select a category',
                dialogTitle: 'Select expense category',
                validator: (v) => v == null ? 'Category is required' : null,
              ),
              const SizedBox(height: 16),

              // Payment Mode (optional)
              SearchableDropdownFormField<String>(
                key: ValueKey('payment_$_selectedPaymentModeId'),
                items: _paymentModes.map((m) => m.id).toList(),
                itemToString: (id) => _paymentModes
                    .where((m) => m.id == id)
                    .map((m) => m.name)
                    .firstOrNull ??
                    id,
                initialValue: _selectedPaymentModeId,
                onChanged: (id) =>
                    setState(() => _selectedPaymentModeId = id),
                decoration: const InputDecoration(
                  labelText: 'Payment Mode (optional)',
                  border: OutlineInputBorder(),
                ),
                hintText: 'Select payment mode',
                dialogTitle: 'Select payment mode',
              ),
              const SizedBox(height: 16),
            ],

            // Note
            TextFormField(
              controller: _noteController,
              decoration: const InputDecoration(
                labelText: 'Note (optional)',
                border: OutlineInputBorder(),
              ),
              maxLines: 4,
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
// Shared small widgets
// ---------------------------------------------------------------------------

class _DatePickerField extends StatelessWidget {
  const _DatePickerField({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
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
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(display),
      ),
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
