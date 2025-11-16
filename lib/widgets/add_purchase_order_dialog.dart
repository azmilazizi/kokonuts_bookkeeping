import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state_scope.dart';
import '../services/inventory_items_service.dart';
import '../services/purchase_orders_service.dart';
import '../services/vendors_service.dart';

class AddPurchaseOrderDialog extends StatefulWidget {
  const AddPurchaseOrderDialog({super.key});

  @override
  State<AddPurchaseOrderDialog> createState() => _AddPurchaseOrderDialogState();
}

class _AddPurchaseOrderDialogState extends State<AddPurchaseOrderDialog> {
  final _formKey = GlobalKey<FormState>();
  final _orderNumberController = TextEditingController();
  final _orderNameController = TextEditingController();
  final _service = PurchaseOrdersService();
  final _vendorsService = VendorsService();
  final _inventoryItemsService = InventoryItemsService();
  final TextEditingController _itemSearchController = TextEditingController();

  late DateTime _orderDate;
  late _PurchaseOrderItemDraft _pendingItem;
  final List<_PurchaseOrderItemDraft> _items = [];

  bool _isSubmitting = false;
  String? _submitError;
  bool _isLoadingReferenceData = false;
  String? _referenceDataError;
  String? _pendingItemError;
  String? _selectedVendorName;
  InventoryItem? _selectedInventoryItem;
  List<String> _vendorNames = const [];
  List<InventoryItem> _inventoryItems = const [];

  @override
  void initState() {
    super.initState();
    _orderDate = DateTime.now();
    _pendingItem = _PurchaseOrderItemDraft(onChanged: _handleItemsChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _loadReferenceData();
      }
    });
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.dispose();
    }
    _orderNumberController.dispose();
    _orderNameController.dispose();
    _pendingItem.dispose();
    _itemSearchController.dispose();
    super.dispose();
  }

  void _removeItem(int index) {
    setState(() {
      final removed = _items.removeAt(index);
      removed.dispose();
    });
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _isLoadingReferenceData = true;
      _referenceDataError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }
    if (token == null || token.trim().isEmpty) {
      setState(() {
        _referenceDataError = 'You are not logged in.';
        _isLoadingReferenceData = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final results = await Future.wait([
        _vendorsService.fetchVendorNames(headers: headers),
        _inventoryItemsService.fetchItems(headers: headers),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _vendorNames = results[0] as List<String>;
        _inventoryItems = results[1] as List<InventoryItem>;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _referenceDataError = 'Failed to load reference data: $error';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingReferenceData = false;
        });
      }
    }
  }

  void _updateSelectedItem(InventoryItem? item) {
    setState(() {
      _selectedInventoryItem = item;
      _pendingItem.setItem(itemName: item?.name, itemId: item?.id);
      _pendingItemError = null;
    });
  }

  void _resetPendingItem() {
    setState(() {
      _selectedInventoryItem = null;
      _itemSearchController.clear();
      _pendingItem.clear();
      _pendingItemError = null;
    });
  }

  void _commitPendingItem() {
    final error = _validatePendingItem();
    if (error != null) {
      setState(() {
        _pendingItemError = error;
      });
      return;
    }

    final newItem = _PurchaseOrderItemDraft(
      onChanged: _handleItemsChanged,
      initialItemId: _pendingItem.itemId,
      initialItemName: _pendingItem.itemName,
      initialDescription: _pendingItem.descriptionController.text,
      initialQuantity: _pendingItem.quantityController.text,
      initialSubtotal: _pendingItem.subtotalController.text,
      initialDiscount: _pendingItem.discountController.text,
    );

    setState(() {
      _items.add(newItem);
      _pendingItemError = null;
    });
    _resetPendingItem();
  }

  String? _validatePendingItem() {
    if ((_pendingItem.itemName ?? '').isEmpty) {
      return 'Select an item before adding it to the order.';
    }
    if (_pendingItem.quantity <= 0) {
      return 'Enter a quantity greater than zero.';
    }
    if (_pendingItem.subtotal < 0) {
      return 'Subtotal cannot be negative.';
    }
    if (_pendingItem.discount < 0) {
      return 'Discount cannot be negative.';
    }
    return null;
  }

  void _handleItemsChanged() {
    setState(() {});
  }

  double get _subtotal =>
      _items.fold(0, (total, item) => total + item.total.clamp(0, double.infinity));

  double get _total => _subtotal;

  Map<String, String> _buildAuthHeaders(AppStateScope appState, String token) {
    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken =
        token.replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '').trim();
    final normalizedAuth =
        sanitizedToken.isNotEmpty ? 'Bearer $sanitizedToken' : token.trim();
    final autoTokenValue =
        rawToken.replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '').trim();
    final authtokenHeader =
        autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;
    return {
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };
  }

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

    if (_items.isEmpty) {
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

    final headers = _buildAuthHeaders(appState, token);

    final items = _items
        .where((item) => (item.itemName ?? '').isNotEmpty)
        .map(
          (item) => CreatePurchaseOrderItem(
            name: item.itemName ?? 'Item',
            description: item.descriptionController.text.trim().isEmpty
                ? null
                : item.descriptionController.text.trim(),
            quantity: item.quantity,
            rate: item.unitPrice,
          ),
        )
        .toList(growable: false);

    final request = CreatePurchaseOrderRequest(
      vendorName: _selectedVendorName?.trim() ?? '',
      orderName: _orderNameController.text.trim(),
      orderNumber: _orderNumberController.text.trim(),
      orderDate: _orderDate,
      reference: null,
      notes: null,
      terms: null,
      items: items,
    );

    setState(() {
      _isSubmitting = true;
      _submitError = null;
    });

    try {
      final created = await _service.createPurchaseOrder(
        headers: headers,
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

    final dialogWidth =
        (MediaQuery.of(context).size.width * 0.92).clamp(420.0, 1200.0);

    return AlertDialog(
      title: const Text('Add Purchase Order'),
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildVendorField(theme),
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
                    hintText: 'System generated',
                  ),
                  enabled: false,
                ),
                const SizedBox(height: 12),
                _OrderDateField(
                  date: _orderDate,
                  onTap: _pickOrderDate,
                ),
                const SizedBox(height: 24),
                Text(
                  'Items',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 12),
                _buildItemsDropdown(theme),
                const SizedBox(height: 12),
                _buildItemCard(
                  theme,
                  item: _pendingItem,
                  isPlaceholder: true,
                ),
                if (_pendingItemError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _pendingItemError!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                for (var i = 0; i < _items.length; i++) ...[
                  _buildItemCard(
                    theme,
                    item: _items[i],
                    index: i,
                  ),
                  const SizedBox(height: 12),
                ],
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

  Widget _buildVendorField(ThemeData theme) {
    if (_isLoadingReferenceData && _vendorNames.isEmpty) {
      return _ReferenceStatusField(
        label: 'Vendor name',
        child: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Loading vendor list...')),
          ],
        ),
      );
    }

    if (_referenceDataError != null && _vendorNames.isEmpty) {
      return _ReferenceErrorField(
        label: 'Vendor name',
        error: _referenceDataError!,
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    if (_vendorNames.isEmpty) {
      return _ReferenceStatusField(
        label: 'Vendor name',
        child: Row(
          children: const [
            Icon(Icons.info_outline),
            SizedBox(width: 12),
            Expanded(child: Text('No vendors found. Refresh to try again.')),
          ],
        ),
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedVendorName,
      decoration: const InputDecoration(
        labelText: 'Vendor name',
        hintText: 'Select a vendor',
      ),
      items: _vendorNames
          .map(
            (name) => DropdownMenuItem<String>(
              value: name,
              child: Text(name),
            ),
          )
          .toList(growable: false),
      onChanged: (value) {
        setState(() {
          _selectedVendorName = value;
        });
      },
      validator: (value) {
        if ((value ?? '').trim().isEmpty) {
          return 'Vendor name is required.';
        }
        return null;
      },
    );
  }

  Widget _buildItemsDropdown(ThemeData theme) {
    if (_isLoadingReferenceData && _inventoryItems.isEmpty) {
      return _ReferenceStatusField(
        label: 'Items',
        child: Row(
          children: const [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 12),
            Expanded(child: Text('Loading inventory items...')),
          ],
        ),
      );
    }

    if (_referenceDataError != null && _inventoryItems.isEmpty) {
      return _ReferenceErrorField(
        label: 'Items',
        error: _referenceDataError!,
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    if (_inventoryItems.isEmpty) {
      return _ReferenceStatusField(
        label: 'Items',
        child: Row(
          children: const [
            Icon(Icons.info_outline),
            SizedBox(width: 12),
            Expanded(child: Text('No inventory items found. Refresh to try again.')),
          ],
        ),
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    final entries = _inventoryItems
        .map(
          (item) => DropdownMenuEntry<InventoryItem>(
            value: item,
            label: item.name,
          ),
        )
        .toList(growable: false);

    return DropdownMenu<InventoryItem>(
      controller: _itemSearchController,
      requestFocusOnTap: true,
      enableFilter: true,
      leadingIcon: const Icon(Icons.search),
      label: const Text('Select item'),
      dropdownMenuEntries: entries,
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(),
      ),
      onSelected: _updateSelectedItem,
    );
  }

  Widget _buildItemCard(
    ThemeData theme, {
    required _PurchaseOrderItemDraft item,
    bool isPlaceholder = false,
    int? index,
  }) {
    final title = isPlaceholder ? 'Add item details' : 'Item ${index! + 1}';
    final canRemove = !isPlaceholder;
    final canCommit = isPlaceholder;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                if (canRemove)
                  IconButton(
                    tooltip: 'Remove item',
                    onPressed: _isSubmitting || index == null
                        ? null
                        : () => _removeItem(index),
                    icon: const Icon(Icons.delete_outline),
                  )
                else if (canCommit)
                  IconButton.filled(
                    tooltip: 'Add to order',
                    onPressed: _isSubmitting ? null : _commitPendingItem,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.green.shade600,
                      foregroundColor: Colors.white,
                    ),
                    icon: const Icon(Icons.check),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Item name',
                border: OutlineInputBorder(),
              ),
              child: Text(
                item.itemName ??
                    (isPlaceholder
                        ? 'Select an item from the dropdown above'
                        : 'Item unavailable'),
                style: (item.itemName == null)
                    ? theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.hintColor)
                    : theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: item.descriptionController,
              decoration: const InputDecoration(
                labelText: 'Description (optional)',
              ),
              maxLines: 2,
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
                    validator: (value) =>
                        _validateQuantityField(item, isPlaceholder: isPlaceholder),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: item.subtotalController,
                    decoration: const InputDecoration(labelText: 'Subtotal (RM)'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    validator: (value) =>
                        _validateSubtotalField(item, isPlaceholder: isPlaceholder),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextFormField(
                    controller: item.discountController,
                    decoration: const InputDecoration(labelText: 'Discount (RM)'),
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: false,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
                    ],
                    validator: (value) =>
                        _validateDiscountField(item, isPlaceholder: isPlaceholder),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _SystemValueField(
                    label: 'Unit price (RM)',
                    value: item.unitPrice,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _SystemValueField(
                    label: 'Total (RM)',
                    value: item.total,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String? _validateQuantityField(
    _PurchaseOrderItemDraft item, {
    required bool isPlaceholder,
  }) {
    if (isPlaceholder) {
      return null;
    }
    if (item.quantity <= 0) {
      return 'Enter a quantity greater than zero.';
    }
    return null;
  }

  String? _validateSubtotalField(
    _PurchaseOrderItemDraft item, {
    required bool isPlaceholder,
  }) {
    if (isPlaceholder) {
      return null;
    }
    if (item.subtotal < 0) {
      return 'Subtotal cannot be negative.';
    }
    return null;
  }

  String? _validateDiscountField(
    _PurchaseOrderItemDraft item, {
    required bool isPlaceholder,
  }) {
    if (isPlaceholder) {
      return null;
    }
    if (item.discount < 0) {
      return 'Discount cannot be negative.';
    }
    if (item.discount > item.subtotal) {
      return 'Discount cannot exceed subtotal.';
    }
    return null;
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

class _SystemValueField extends StatelessWidget {
  const _SystemValueField({required this.label, required this.value});

  final String label;
  final double value;

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      child: Text(value.toStringAsFixed(2)),
    );
  }
}

class _ReferenceStatusField extends StatelessWidget {
  const _ReferenceStatusField({
    required this.label,
    required this.child,
    this.onRetry,
  });

  final String label;
  final Widget child;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: child,
      ),
    ];

    if (onRetry != null) {
      children.addAll([
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ]);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: children,
    );
  }
}

class _ReferenceErrorField extends StatelessWidget {
  const _ReferenceErrorField({
    required this.label,
    required this.error,
    this.onRetry,
  });

  final String label;
  final String error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: label,
            border: const OutlineInputBorder(),
          ),
          child: const Text('Unable to load data.'),
        ),
        const SizedBox(height: 8),
        Text(
          error,
          style:
              theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.error),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ),
      ],
    );
  }
}

class _PurchaseOrderItemDraft {
  _PurchaseOrderItemDraft({
    required VoidCallback onChanged,
    String? initialItemId,
    String? initialItemName,
    String initialDescription = '',
    String initialQuantity = '1',
    String initialSubtotal = '0',
    String initialDiscount = '0',
  })  : descriptionController = TextEditingController(text: initialDescription),
        quantityController = TextEditingController(text: initialQuantity),
        subtotalController = TextEditingController(text: initialSubtotal),
        discountController = TextEditingController(text: initialDiscount),
        itemId = initialItemId,
        itemName = initialItemName,
        _onChanged = onChanged {
    descriptionController.addListener(onChanged);
    quantityController.addListener(onChanged);
    subtotalController.addListener(onChanged);
    discountController.addListener(onChanged);
  }

  final TextEditingController descriptionController;
  final TextEditingController quantityController;
  final TextEditingController subtotalController;
  final TextEditingController discountController;
  final VoidCallback _onChanged;

  String? itemId;
  String? itemName;

  double get quantity =>
      double.tryParse(quantityController.text.replaceAll(',', '.')) ?? 0;

  double get subtotal =>
      double.tryParse(subtotalController.text.replaceAll(',', '.')) ?? 0;

  double get discount =>
      double.tryParse(discountController.text.replaceAll(',', '.')) ?? 0;

  double get total {
    final value = subtotal - discount;
    if (value.isNaN || value.isInfinite) {
      return 0;
    }
    return value <= 0 ? 0 : value;
  }

  double get unitPrice => quantity <= 0 ? 0 : total / quantity;

  bool get hasContent {
    return (itemName?.trim().isNotEmpty ?? false) ||
        descriptionController.text.trim().isNotEmpty ||
        quantityController.text.trim().isNotEmpty ||
        subtotalController.text.trim().isNotEmpty ||
        discountController.text.trim().isNotEmpty;
  }

  void setItem({String? itemId, String? itemName}) {
    this.itemId = itemId;
    this.itemName = itemName;
    _onChanged();
  }

  void clear() {
    itemId = null;
    itemName = null;
    descriptionController.clear();
    quantityController.text = '1';
    subtotalController.text = '0';
    discountController.text = '0';
    _onChanged();
  }

  void dispose() {
    descriptionController.dispose();
    quantityController.dispose();
    subtotalController.dispose();
    discountController.dispose();
  }
}
