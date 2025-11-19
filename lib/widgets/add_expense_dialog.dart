import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/app/app_state.dart';

import '../app/app_state_scope.dart';
import '../services/payment_modes_service.dart';
import 'attachment_picker.dart';
import 'currency_input_formatter.dart';

class AddExpenseDialog extends StatefulWidget {
  const AddExpenseDialog({super.key});

  @override
  State<AddExpenseDialog> createState() => _AddExpenseDialogState();
}

class _AddExpenseDialogState extends State<AddExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  final _vendorController = TextEditingController();
  final _nameController = TextEditingController();
  final _amountController =
      TextEditingController(text: CurrencyInputFormatter.normalizeExistingValue(null));
  final _notesController = TextEditingController();
  final _paymentModesService = PaymentModesService();

  final List<String> _categories = const [
    'Office Supplies',
    'Travel',
    'Meals & Entertainment',
    'Utilities',
    'Professional Services',
    'Other',
  ];

  DateTime _expenseDate = DateTime.now();
  String? _selectedCategory;
  String? _selectedPaymentMode;
  List<PlatformFile> _attachments = [];
  bool _isSubmitting = false;
  String? _submitError;
  bool _isLoadingPaymentModes = false;
  String? _paymentModeError;
  bool _hasInitializedPaymentModes = false;
  List<PaymentMode> _paymentModes = const [];

  @override
  void dispose() {
    _vendorController.dispose();
    _nameController.dispose();
    _amountController.dispose();
    _notesController.dispose();
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
      final modes = await _paymentModesService.fetchPaymentModes(
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentModes = modes;
        if (_selectedPaymentMode != null &&
            !_paymentModes.any((mode) => mode.id == _selectedPaymentMode)) {
          _selectedPaymentMode = null;
        }
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

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken = token
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final normalizedAuth = sanitizedToken.isNotEmpty
        ? 'Bearer $sanitizedToken'
        : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    final authtokenHeader = autoTokenValue.isNotEmpty
        ? autoTokenValue
        : sanitizedToken;
    return {'authtoken': authtokenHeader, 'Authorization': normalizedAuth};
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dialogWidth = (MediaQuery.of(context).size.width * 0.92).clamp(
      420.0,
      900.0,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      title: const Text('Create Expense'),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 8),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Attachments', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                AttachmentPicker(
                  description:
                      'Drag and drop receipts or supporting documents, or tap to browse.',
                  files: _attachments,
                  onPick: _pickAttachment,
                  onFilesSelected: (files) =>
                      setState(() => _attachments = files),
                  onFileRemoved: (file) => setState(() {
                    _attachments = List.of(_attachments)..remove(file);
                  }),
                ),
                const SizedBox(height: 20),
                _buildVendorField(),
                const SizedBox(height: 12),
                _buildExpenseNameField(),
                const SizedBox(height: 12),
                _buildCategoryDropdown(),
                const SizedBox(height: 12),
                _buildDateField(context),
                const SizedBox(height: 12),
                _buildAmountField(),
                const SizedBox(height: 12),
                _buildPaymentModeField(),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _notesController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Notes (optional)',
                    hintText: 'Add any additional details for this expense',
                  ),
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    _submitError!,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.error,
                    ),
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

  Widget _buildCategoryDropdown() {
    return DropdownButtonFormField<String>(
      value: _selectedCategory,
      decoration: const InputDecoration(labelText: 'Expense category'),
      hint: const Text('Select a category'),
      items: _categories
          .map(
            (category) => DropdownMenuItem<String>(
              value: category,
              child: Text(category),
            ),
          )
          .toList(),
      onChanged: (value) => setState(() => _selectedCategory = value),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Expense category is required.';
        }
        return null;
      },
    );
  }

  Widget _buildDateField(BuildContext context) {
    final formattedDate = DateFormat.yMMMd().format(_expenseDate);
    return InkWell(
      onTap: _isSubmitting ? null : () => _pickDate(context),
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
      inputFormatters: const [CurrencyInputFormatter()],
      validator: (value) {
        final parsed = double.tryParse(value ?? '');
        if (parsed == null || parsed <= 0) {
          return 'Enter a valid amount.';
        }
        return null;
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

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: kIsWeb,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(growable: false),
    );

    if (!mounted || result == null || result.files.isEmpty) {
      return;
    }

    final newFiles = result.files
        .where(
          (file) => isAllowedAttachmentExtension(
            file.extension ?? attachmentExtension(file.name),
          ),
        )
        .toList(growable: false);

    if (newFiles.isEmpty) {
      return;
    }

    setState(() {
      _attachments = [..._attachments, ...newFiles];
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _submitError = null;
      _isSubmitting = true;
    });

    await Future<void>.delayed(const Duration(milliseconds: 400));

    if (!mounted) {
      return;
    }

    setState(() => _isSubmitting = false);

    Navigator.of(context).pop({
      'vendor': _vendorController.text.trim(),
      'name': _nameController.text.trim(),
      'category': _selectedCategory,
      'date': _expenseDate.toIso8601String(),
      'amount': _amountController.text.trim(),
      'paymentMode': _selectedPaymentMode,
      'notes': _notesController.text.trim(),
      'attachments': _attachments,
    });
  }
}
