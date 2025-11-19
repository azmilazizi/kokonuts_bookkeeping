import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/expenses_service.dart';
import '../services/payment_modes_service.dart';

class EditExpenseDialog extends StatefulWidget {
  const EditExpenseDialog({super.key, required this.expense});

  final Expense expense;

  @override
  State<EditExpenseDialog> createState() => _EditExpenseDialogState();
}

class _EditExpenseDialogState extends State<EditExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _vendorController;
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _amountController;
  final _paymentModesService = PaymentModesService();

  final _categories = const [
    'Office Supplies',
    'Travel',
    'Meals & Entertainment',
    'Utilities',
    'Professional Services',
    'Other',
  ];

  final _currencyFormatter = NumberFormat.currency(symbol: '', decimalDigits: 2);

  late DateTime _expenseDate;
  bool _isSaving = false;
  bool _isLoadingPaymentModes = false;
  String? _paymentModeError;
  bool _hasInitializedPaymentModes = false;
  List<PaymentMode> _paymentModes = const [];
  String? _selectedPaymentMode;
  late final String _initialPaymentModeLabel;

  @override
  void initState() {
    super.initState();
    _vendorController = TextEditingController(text: widget.expense.vendor);
    _nameController = TextEditingController(text: widget.expense.name);
    _categoryController = TextEditingController(text: widget.expense.categoryName);
    _amountController = TextEditingController(
      text: widget.expense.amount?.toStringAsFixed(2) ?? widget.expense.amountLabel,
    );
    _initialPaymentModeLabel = widget.expense.paymentMode;
    _expenseDate = widget.expense.date ?? DateTime.now();
  }

  @override
  void dispose() {
    _vendorController.dispose();
    _nameController.dispose();
    _categoryController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hasInitializedPaymentModes) {
      _hasInitializedPaymentModes = true;
      _loadPaymentModes();
    }
  }

  Future<void> _loadPaymentModes() async {
    setState(() {
      _paymentModeError = null;
      _isLoadingPaymentModes = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _paymentModeError = 'You are not logged in.';
        _isLoadingPaymentModes = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final modes = await _paymentModesService.fetchPaymentModes(headers: headers);

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentModes = modes;
        _selectedPaymentMode = _resolveInitialPaymentMode();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paymentModeError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPaymentModes = false);
      }
    }
  }

  String? _resolveInitialPaymentMode() {
    if (_paymentModes.isEmpty) {
      return null;
    }

    final currentSelection = _selectedPaymentMode;
    if (currentSelection != null &&
        _paymentModes.any((mode) => mode.id == currentSelection)) {
      return currentSelection;
    }

    final matched = _paymentModes.firstWhere(
      (mode) => mode.name.toLowerCase() == _initialPaymentModeLabel.toLowerCase(),
      orElse: () => _paymentModes.first,
    );

    return matched.id;
  }

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken = token
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final normalizedAuth =
        sanitizedToken.isNotEmpty ? 'Bearer $sanitizedToken' : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final authtokenHeader =
        autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;
    return {'authtoken': authtokenHeader, 'Authorization': normalizedAuth};
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.92).clamp(420.0, 900.0);

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: const Text('Edit Expense'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildVendorField(),
                const SizedBox(height: 12),
                _buildExpenseNameField(),
                const SizedBox(height: 12),
                _buildCategoryField(),
                const SizedBox(height: 12),
                _buildDateField(context),
                const SizedBox(height: 12),
                _buildAmountField(),
                const SizedBox(height: 12),
                _buildPaymentModeField(),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _isSaving ? null : _submit,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save changes'),
        ),
      ],
    );
  }

  Widget _buildVendorField() {
    return TextFormField(
      controller: _vendorController,
      decoration: const InputDecoration(
        labelText: 'Vendor',
        hintText: 'e.g., ABC Supplies',
      ),
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Vendor is required.';
        }
        return null;
      },
    );
  }

  Widget _buildExpenseNameField() {
    return TextFormField(
      controller: _nameController,
      decoration: const InputDecoration(
        labelText: 'Expense name',
        hintText: 'Describe the expense',
      ),
      textInputAction: TextInputAction.next,
      validator: (value) {
        if (value == null || value.trim().isEmpty) {
          return 'Expense name is required.';
        }
        return null;
      },
    );
  }

  Widget _buildCategoryField() {
    final items = {
      ..._categories,
      if (widget.expense.categoryName.trim().isNotEmpty) widget.expense.categoryName,
    }.toList();

    return DropdownButtonFormField<String>(
      value: items.contains(_categoryController.text) ? _categoryController.text : null,
      decoration: const InputDecoration(labelText: 'Expense category'),
      hint: const Text('Select a category'),
      items: items
          .map(
            (category) => DropdownMenuItem<String>(
              value: category,
              child: Text(category),
            ),
          )
          .toList(),
      onChanged: (value) {
        if (value != null) {
          _categoryController.text = value;
        }
      },
      validator: (value) {
        final resolved = value ?? _categoryController.text;
        if (resolved.trim().isEmpty) {
          return 'Expense category is required.';
        }
        return null;
      },
    );
  }

  Widget _buildDateField(BuildContext context) {
    final formattedDate = DateFormat.yMMMd().format(_expenseDate);
    return InkWell(
      onTap: _isSaving ? null : () => _pickDate(context),
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: const InputDecoration(labelText: 'Expense date'),
        child: Row(
          children: [
            const Icon(Icons.event, size: 20),
            const SizedBox(width: 12),
            Text(formattedDate),
          ],
        ),
      ),
    );
  }

  Widget _buildAmountField() {
    return TextFormField(
      controller: _amountController,
      decoration: const InputDecoration(
        labelText: 'Amount',
        prefixText: 'RM ',
        hintText: '0.00',
      ),
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      textInputAction: TextInputAction.next,
      inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]'))],
      validator: (value) {
        final sanitized =
            value?.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', '').trim();
        final parsed = double.tryParse(sanitized ?? '');
        if (parsed == null || parsed <= 0) {
          return 'Enter a valid amount.';
        }
        return null;
      },
      onChanged: (value) {
        final sanitized = value.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', '');
        final parsed = double.tryParse(sanitized);
        if (parsed != null) {
          final formatted = _currencyFormatter.format(parsed);
          if (formatted != sanitized && _amountController.text != formatted) {
            _amountController
              ..text = formatted
              ..selection = TextSelection.collapsed(offset: formatted.length);
          }
        }
      },
    );
  }

  Widget _buildPaymentModeField() {
    return DropdownButtonFormField<String>(
      value: _selectedPaymentMode,
      decoration: InputDecoration(
        labelText: 'Payment mode',
        helperText: _paymentModeError,
      ),
      isExpanded: true,
      hint: _isLoadingPaymentModes
          ? Row(
              children: const [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 8),
                Text('Loading payment modes...'),
              ],
            )
          : const Text('Choose payment mode'),
      items: _paymentModes
          .map(
            (mode) => DropdownMenuItem<String>(
              value: mode.id,
              child: Text(mode.name),
            ),
          )
          .toList(),
      onChanged: _paymentModes.isEmpty || _isLoadingPaymentModes
          ? null
          : (value) => setState(() => _selectedPaymentMode = value),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Payment mode is required.';
        }
        return null;
      },
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _expenseDate,
      firstDate: DateTime.now().subtract(const Duration(days: 365 * 5)),
      lastDate: DateTime.now().add(const Duration(days: 365 * 5)),
    );

    if (picked != null && mounted) {
      setState(() => _expenseDate = picked);
    }
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);
    await Future<void>.delayed(const Duration(milliseconds: 200));
    if (!mounted) {
      return;
    }

    final parsedAmount = double.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', ''),
    );
    final resolvedAmount = parsedAmount ?? widget.expense.amount;
    final amountLabel = resolvedAmount?.toStringAsFixed(2) ?? widget.expense.amountLabel;

    final updatedExpense = Expense(
      id: widget.expense.id,
      vendor: _vendorController.text.trim(),
      name: _nameController.text.trim(),
      categoryName: _categoryController.text.trim().isEmpty
          ? widget.expense.categoryName
          : _categoryController.text.trim(),
      amount: resolvedAmount,
      amountLabel: amountLabel,
      currencySymbol: widget.expense.currencySymbol,
      date: _expenseDate,
      receipt: widget.expense.receipt,
      paymentMode: _selectedPaymentMode ?? widget.expense.paymentMode,
      createdBy: widget.expense.createdBy,
    );

    setState(() => _isSaving = false);
    if (mounted) {
      Navigator.of(context).pop(updatedExpense);
    }
  }
}
