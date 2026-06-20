import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/app/app_state.dart';

import '../app/app_state_scope.dart';
import '../services/expenses_service.dart';
import '../services/payment_modes_service.dart';
import '../services/vendors_service.dart';
import 'create_vendor_dialog.dart';
import 'attachment_picker.dart';
import 'currency_input_formatter.dart';
import 'form_error_banner.dart';
import 'searchable_dropdown_form_field.dart';

class AddExpenseDialog extends StatefulWidget {
  const AddExpenseDialog({
    super.key,
    this.extracted,
    this.scannedFilePath,
    this.scannedFileBytes,
  });

  final Map<String, dynamic>? extracted;
  final String? scannedFilePath;
  final Uint8List? scannedFileBytes;

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
  final _vendorsService = VendorsService();
  final _expensesService = ExpensesService();

  DateTime _expenseDate = DateTime.now();
  String? _selectedCategory;
  String? _selectedPaymentMode;
  String? _selectedVendorId;
  List<PlatformFile> _attachments = [];
  bool _isSubmitting = false;
  String? _submitError;

  bool _isLoadingData = false;
  String? _loadingError;
  bool _hasInitializedData = false;
  String? _extractedVendorName;

  List<PaymentMode> _paymentModes = const [];
  List<VendorSummary> _vendors = const [];
  List<ExpenseCategory> _categories = const [];

  String _vendorLabel(String id) {
    return _vendors
            .firstWhere(
              (vendor) => vendor.id == id,
              orElse: () => VendorSummary(id: id, name: 'Unknown vendor'),
            )
            .name;
  }

  String _categoryLabel(String id) {
    return _categories
            .firstWhere(
              (category) => category.id == id,
              orElse: () => ExpenseCategory(id: id, name: 'Unknown category'),
            )
            .name;
  }

  String _paymentModeLabel(String id) {
    return _paymentModes
            .firstWhere(
              (mode) => mode.id == id,
              orElse: () => PaymentMode(id: id, name: 'Unknown mode'),
            )
            .name;
  }

  @override
  void initState() {
    super.initState();
    _prefillFromExtracted();
    _attachScannedFile();
  }

  void _attachScannedFile() {
    if (kIsWeb) {
      final bytes = widget.scannedFileBytes;
      final name = widget.scannedFilePath;
      if (bytes == null || name == null) return;
      _attachments = [
        PlatformFile(name: name, size: bytes.length, bytes: bytes),
      ];
      return;
    }
    final path = widget.scannedFilePath;
    if (path == null) return;
    try {
      final file = File(path);
      final name = path.split(Platform.pathSeparator).last;
      _attachments = [
        PlatformFile(name: name, size: file.lengthSync(), path: path),
      ];
    } catch (_) {}
  }

  void _prefillFromExtracted() {
    final e = widget.extracted;
    if (e == null) return;

    final vendor = e['vendor'] as String?;
    _extractedVendorName = vendor;

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

    final dateStr = e['date'] as String?;
    if (dateStr != null) {
      final parsed = DateTime.tryParse(dateStr);
      if (parsed != null) _expenseDate = parsed;
    }

    final amount = e['grand_total'] ?? e['subtotal'];
    if (amount != null) {
      _amountController.text =
          CurrencyInputFormatter.normalizeExistingValue(
            (amount as num).toStringAsFixed(2),
          );
    }

    // Note: leave empty
  }

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
    if (!_hasInitializedData) {
      _hasInitializedData = true;
      _loadData();
    }
  }

  Future<void> _loadData() async {
    setState(() {
      _loadingError = null;
      _isLoadingData = true;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _loadingError = 'You are not logged in.';
        _isLoadingData = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final results = await Future.wait([
        _paymentModesService.fetchPaymentModes(headers: headers),
        _vendorsService.fetchVendors(headers: headers),
        _expensesService.fetchCategories(headers: headers),
      ]);

      if (!mounted) {
        return;
      }

      final modes = results[0] as List<PaymentMode>;
      final vendors = results[1] as List<VendorSummary>;
      final categories = results[2] as List<ExpenseCategory>;

      setState(() {
        _paymentModes = modes;
        _vendors = vendors;
        _categories = categories;

        if (_selectedPaymentMode != null &&
            !_paymentModes.any((mode) => mode.id == _selectedPaymentMode)) {
          _selectedPaymentMode = null;
        }
        if (_selectedVendorId != null &&
            !_vendors.any((vendor) => vendor.id == _selectedVendorId)) {
          _selectedVendorId = null;
        }
        if (_selectedCategory != null &&
            !_categories.any((cat) => cat.id == _selectedCategory)) {
          _selectedCategory = null;
        }

        if (_selectedVendorId == null && _extractedVendorName != null) {
          final normalized = _extractedVendorName!.toLowerCase().trim();
          VendorSummary? match = _vendors
              .where((v) => v.name.toLowerCase().trim() == normalized)
              .firstOrNull;
          match ??= _vendors.where((v) {
            final vn = v.name.toLowerCase();
            return vn.contains(normalized) || normalized.contains(vn);
          }).firstOrNull;
          if (match == null) {
            final queryWords = normalized.split(RegExp(r'\s+')).toSet();
            int bestScore = 0;
            for (final v in _vendors) {
              final score = queryWords
                  .intersection(
                      v.name.toLowerCase().split(RegExp(r'\s+')).toSet())
                  .length;
              if (score > bestScore) {
                bestScore = score;
                match = v;
              }
            }
          }
          if (match != null) _selectedVendorId = match.id;
        }

        final paymentMethod =
            widget.extracted?['payment_method'] as String?;
        if (_selectedPaymentMode == null &&
            paymentMethod != null &&
            paymentMethod.isNotEmpty) {
          final normalized = paymentMethod.toLowerCase().trim();
          PaymentMode? matched = modes
              .where((m) => m.name.toLowerCase().trim() == normalized)
              .firstOrNull;
          matched ??= modes.where((m) {
            final mn = m.name.toLowerCase();
            return mn.contains(normalized) || normalized.contains(mn);
          }).firstOrNull;
          if (matched == null) {
            final queryWords = normalized.split(RegExp(r'\s+')).toSet();
            int bestScore = 0;
            for (final m in modes) {
              final score = queryWords
                  .intersection(
                      m.name.toLowerCase().split(RegExp(r'\s+')).toSet())
                  .length;
              if (score > bestScore) {
                bestScore = score;
                matched = m;
              }
            }
          }
          if (matched != null) _selectedPaymentMode = matched.id;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadingError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingData = false);
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
                  if (_submitError != null) ...[
                    FormErrorBanner(message: _submitError!),
                    const SizedBox(height: 16),
                  ],
                  if (widget.extracted != null &&
                      widget.extracted!['confidence'] == 'low') ...[
                    Container(
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
                              'Low confidence scan — please review all fields carefully.',
                              style: TextStyle(
                                  color: Colors.amber.shade900, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
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
                const SizedBox(height: 20),
                Text('Attachments', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                AttachmentPicker(
                  description:
                      'Drag and drop receipts or supporting documents, or tap to browse.',
                  files: _attachments,
                  enablePreview: true,
                  onPick: _pickAttachment,
                  onFilesSelected: (files) =>
                      setState(() => _attachments = files),
                  onFileRemoved: (file) => setState(() {
                    _attachments = List.of(_attachments)..remove(file);
                  }),
                ),
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
    return SearchableDropdownFormField<String>(
      initialValue: _selectedVendorId,
      items: _vendors.map((vendor) => vendor.id).toList(),
      itemToString: _vendorLabel,
      decoration: InputDecoration(
        labelText: 'Vendor',
        helperText: _loadingError,
      ),
      hintText: _isLoadingData ? 'Loading vendors...' : 'Select a vendor',
      enabled: !_isLoadingData,
      dialogTitle: 'Select vendor',
      createLabel: 'Create new vendor',
      onCreateNew: (_) => _handleCreateVendor(),
      onChanged: (value) => setState(() => _selectedVendorId = value),
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Vendor is required.';
        }
        return null;
      },
    );
  }

  Future<String?> _handleCreateVendor() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (token == null || token.trim().isEmpty) {
      setState(() => _submitError = 'You are not logged in.');
      return null;
    }
    final headers = _buildAuthHeaders(appState, token);
    final created = await showCreateVendorDialog(
      context: context,
      headers: headers,
    );
    if (created == null) return null;

    setState(() {
      _vendors = [..._vendors, created]
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
      _selectedVendorId = created.id;
    });
    return created.id;
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
    return SearchableDropdownFormField<String>(
      initialValue: _selectedCategory,
      items: _categories.map((category) => category.id).toList(),
      itemToString: _categoryLabel,
      decoration: InputDecoration(
        labelText: 'Expense category',
        helperText: _loadingError,
      ),
      hintText: _isLoadingData ? 'Loading categories...' : 'Select a category',
      enabled: !_isLoadingData,
      dialogTitle: 'Select expense category',
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
    return SearchableDropdownFormField<String>(
      initialValue: _selectedPaymentMode,
      items: _paymentModes.map((mode) => mode.id).toList(),
      itemToString: _paymentModeLabel,
      decoration: InputDecoration(
        labelText: 'Payment mode',
        helperText: _loadingError,
      ),
      hintText: _isLoadingData ? 'Loading payment modes...' : 'Choose payment mode',
      enabled: !_isLoadingData,
      dialogTitle: 'Select payment mode',
      onChanged: (value) => setState(() => _selectedPaymentMode = value),
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

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _submitError = 'You are not logged in.';
        _isSubmitting = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    final categoryName = _categories
        .firstWhere(
          (c) => c.id == _selectedCategory,
          orElse: () => const ExpenseCategory(id: '', name: ''),
        )
        .name;

    final paymentModeName = _paymentModes
        .firstWhere(
          (mode) => mode.id == _selectedPaymentMode,
          orElse: () => const PaymentMode(id: '', name: ''),
        )
        .name;

    final parsedAmount = double.tryParse(
      _amountController.text
          .replaceAll(RegExp(r'[^0-9.,-]'), '')
          .replaceAll(',', ''),
    );

    final requestData = {
      'expense_name': _nameController.text.trim(),
      'note': _notesController.text.trim(),
      'date': DateFormat('yyyy-MM-dd').format(_expenseDate),
      'amount': parsedAmount ?? 0,
      'vendor': _selectedVendorId ?? '',
      'category': categoryName.isNotEmpty ? categoryName : _selectedCategory,
      'paymentmode': _selectedPaymentMode ?? '',
      'payment_method_name': paymentModeName,
      if (_attachments.isNotEmpty) 'attachment': _attachments.first.name,
    };

    try {
      final created = await _expensesService.createExpense(
        headers: headers,
        data: requestData,
      );

      if (_attachments.isNotEmpty) {
        try {
          await _expensesService.uploadAttachments(
            id: created.id,
            headers: headers,
            attachments: _attachments,
          );
        } catch (error) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  'Expense created but failed to upload attachments: $error',
                ),
              ),
            );
          }
        }
      }

      if (!mounted) {
        return;
      }

      setState(() => _isSubmitting = false);
      Navigator.of(context).pop(created);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = error.toString();
        _isSubmitting = false;
      });
    }
  }
}
