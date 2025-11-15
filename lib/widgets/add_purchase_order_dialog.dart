import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state_scope.dart';
import '../services/purchase_orders_service.dart';

class AddPurchaseOrderDialog extends StatefulWidget {
  const AddPurchaseOrderDialog({super.key});

  @override
  State<AddPurchaseOrderDialog> createState() => _AddPurchaseOrderDialogState();
}

class _AddPurchaseOrderDialogState extends State<AddPurchaseOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _orderNumberController = TextEditingController();
  final _orderNameController = TextEditingController();
  final _vendorController = TextEditingController();
  final _referenceController = TextEditingController();
  final _notesController = TextEditingController();
  final _termsController = TextEditingController();
  final _service = PurchaseOrdersService();

  late DateTime _orderDate;
  final List<_PurchaseOrderItemDraft> _items = [];

  bool _isSubmitting = false;
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _orderDate = DateTime.now();
    _addItem();
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _orderNumberController.dispose();
    _orderNameController.dispose();
    _vendorController.dispose();
    _referenceController.dispose();
    _notesController.dispose();
    _termsController.dispose();
    super.dispose();
  }

  void _addItem() {
    setState(() {
      final item = _PurchaseOrderItemDraft(onChanged: _handleItemsChanged);
      _items.add(item);
    });
  }

  void _removeItem(int index) {
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  void _handleItemsChanged() {
    setState(() {});
  }

  double get _subtotal =>
      _items.fold(0, (total, item) => total + item.amount.clamp(0, double.infinity));

  double get _total => _subtotal;

  Future<void> _pickOrderDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(now.year - 10),
      lastDate: DateTime(now.year + 10),
      initialDate: _orderDate,
    );

    if (selected != null) {
      setState(() {
        _orderDate = selected;
      });
    }
  }

  Future<void> _submit() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_items.every((item) => !item.hasContent)) {
      setState(() {
        _submitError = 'Add at least one item to create a purchase order.';
      });
      return;
    }

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _submitError = 'You are not logged in.';
      });
      return;
    }

    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken =
        token.replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '').trim();
    final normalizedAuth =
        sanitizedToken.isNotEmpty ? 'Bearer $sanitizedToken' : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final authtokenHeader =
        autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;

    final items = _items
        .where((item) => item.hasContent)
        .map(
          (item) => CreatePurchaseOrderItem(
            name: item.nameController.text.trim(),
            description: item.descriptionController.text.trim(),
            quantity: item.quantity,
            rate: item.rate,
          ),
        )
        .toList(growable: false);

    final request = CreatePurchaseOrderRequest(
      vendorName: _vendorController.text.trim(),
      orderName: _orderNameController.text.trim(),
      orderNumber: _orderNumberController.text.trim(),
      orderDate: _orderDate,
      reference: _referenceController.text.trim().isEmpty
          ? null
          : _referenceController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      terms: _termsController.text.trim().isEmpty
          ? null
          : _termsController.text.trim(),
      items: items,
    );

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final created = await _service.createPurchaseOrder(
        headers: {
          'authtoken': authtokenHeader,
          'Authorization': normalizedAuth,
        },
        request: request,
      );

      if (!mounted) {
        return;
      }

      Navigator.of(context).pop(created);
    } on PurchaseOrdersException catch (error) {
      setState(() {
        _submitError = error.message;
      });
    } catch (error) {
      setState(() {
        _submitError = 'Failed to create purchase order: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Add Purchase Order'),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: _vendorController,
                  decoration: const InputDecoration(
                    labelText: 'Vendor name',
                    hintText: 'Enter the vendor or supplier name',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Vendor name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _orderNameController,
                  decoration: const InputDecoration(
                    labelText: 'Order name',
                    hintText: 'Describe the purchase order',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Order name is required.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _orderNumberController,
                  decoration: const InputDecoration(
                    labelText: 'Order number',
                    hintText: 'Auto-generated if left blank',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                _OrderDateField(
                  date: _orderDate,
                  onTap: _pickOrderDate,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _referenceController,
                  decoration: const InputDecoration(
                    labelText: 'Reference (optional)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _termsController,
                  decoration: const InputDecoration(
                    labelText: 'Terms (optional)',
                  ),
                  maxLines: 3,
                ),
                const SizedBox(height: 24),
                Text(
                  'Items',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                if (_items.isEmpty)
                  Card(
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
                    child: const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('Add at least one item to continue.'),
                    ),
                  ),
                ..._buildItemFields(theme),
                Align(
                  alignment: Alignment.centerLeft,
                  child: OutlinedButton.icon(
                    onPressed: _addItem,
                    icon: const Icon(Icons.add),
                    label: const Text('Add item'),
                  ),
                ),
                const SizedBox(height: 16),
                _TotalsSummary(subtotal: _subtotal, total: _total),
                if (_submitError != null) ...[
                  const SizedBox(height: 16),
                  Text(
                    _submitError!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }

  List<Widget> _buildItemFields(ThemeData theme) {
    final fields = <Widget>[];
    for (var i = 0; i < _items.length; i++) {
      final item = _items[i];
      fields.add(
        Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Item ${i + 1}',
                        style: theme.textTheme.titleSmall,
                      ),
                    ),
                    if (_items.length > 1)
                      IconButton(
                        tooltip: 'Remove item',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: _isSubmitting
                            ? null
                            : () => _removeItem(i),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                TextFormField(
                  controller: item.nameController,
                  decoration: const InputDecoration(
                    labelText: 'Item name',
                    hintText: 'Enter a product or service name',
                  ),
                  textInputAction: TextInputAction.next,
                  validator: (value) {
                    if (!item.hasContent) {
                      return null;
                    }
                    if (value == null || value.trim().isEmpty) {
                      return 'Enter an item name or remove this row.';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: item.descriptionController,
                  decoration: const InputDecoration(
                    labelText: 'Description (optional)',
                  ),
                  textInputAction: TextInputAction.next,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextFormField(
                        controller: item.quantityController,
                        decoration: const InputDecoration(labelText: 'Quantity'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: false,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        validator: (value) {
                          if (!item.hasContent) {
                            return null;
                          }
                          final quantity = item.quantity;
                          if (quantity <= 0) {
                            return 'Enter a quantity greater than zero.';
                          }
                          return null;
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextFormField(
                        controller: item.rateController,
                        decoration: const InputDecoration(labelText: 'Unit price'),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: false,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                        ],
                        validator: (value) {
                          if (!item.hasContent) {
                            return null;
                          }
                          if (item.rate < 0) {
                            return 'Enter a non-negative price.';
                          }
                          return null;
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text('Amount: ${item.amount.toStringAsFixed(2)}'),
              ],
            ),
          ),
        ),
      );
    }
    return fields;
  }
}

class _OrderDateField extends StatelessWidget {
  const _OrderDateField({required this.date, required this.onTap});

  final DateTime date;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final formatted =
        '${date.year.toString().padLeft(4, '0')}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: const InputDecoration(
          labelText: 'Order date',
          border: OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Icon(Icons.event, color: theme.colorScheme.primary),
            const SizedBox(width: 12),
            Text(formatted),
          ],
        ),
      ),
    );
  }
}

class _TotalsSummary extends StatelessWidget {
  const _TotalsSummary({required this.subtotal, required this.total});

  final double subtotal;
  final double total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _TotalsRow(label: 'Subtotal', amount: subtotal),
        const SizedBox(height: 8),
        Divider(color: theme.colorScheme.outlineVariant),
        const SizedBox(height: 8),
        _TotalsRow(
          label: 'Total',
          amount: total,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.amount,
    this.style,
  });

  final String label;
  final double amount;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final effectiveStyle = style ?? theme.textTheme.bodyMedium;

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: effectiveStyle),
        Text(amount.toStringAsFixed(2), style: effectiveStyle),
      ],
    );
  }
}

class _PurchaseOrderItemDraft {
  _PurchaseOrderItemDraft({required VoidCallback onChanged})
      : nameController = TextEditingController(),
        descriptionController = TextEditingController(),
        quantityController = TextEditingController(text: '1'),
        rateController = TextEditingController(text: '0') {
    nameController.addListener(onChanged);
    descriptionController.addListener(onChanged);
    quantityController.addListener(onChanged);
    rateController.addListener(onChanged);
  }

  final TextEditingController nameController;
  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController rateController;

  double get quantity => double.tryParse(quantityController.text.replaceAll(',', '.')) ?? 0;

  double get rate => double.tryParse(rateController.text.replaceAll(',', '.')) ?? 0;

  double get amount => quantity * rate;

  bool get hasContent {
    return nameController.text.trim().isNotEmpty ||
        descriptionController.text.trim().isNotEmpty ||
        quantityController.text.trim().isNotEmpty ||
        rateController.text.trim().isNotEmpty;
  }

  void dispose() {
    nameController.dispose();
    descriptionController.dispose();
    quantityController.dispose();
    rateController.dispose();
  }
}
