import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/expenses_service.dart';
import '../services/payment_modes_service.dart';
import '../services/vendors_service.dart';
import 'attachment_picker.dart';
import 'currency_input_formatter.dart';

class EditExpenseDialog extends StatefulWidget {
  const EditExpenseDialog({super.key, required this.expense});

  final Expense expense;

  @override
  State<EditExpenseDialog> createState() => _EditExpenseDialogState();
}

class _EditExpenseDialogState extends State<EditExpenseDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _categoryController;
  late final TextEditingController _amountController;
  final _paymentModesService = PaymentModesService();
  final _vendorsService = VendorsService();
  final _expensesService = ExpensesService();

  final _categories = const [
    'Office Supplies',
    'Travel',
    'Meals & Entertainment',
    'Utilities',
    'Professional Services',
    'Other',
  ];

  late DateTime _expenseDate;
  bool _isSaving = false;
  bool _isLoadingReferenceData = false;
  String? _referenceDataError;

  List<PaymentMode> _paymentModes = const [];
  List<VendorSummary> _vendors = const [];

  String? _selectedPaymentMode;
  String? _selectedVendorName;
  String? _selectedVendorId; // Keep track of ID but API might use name

  late final String _initialPaymentModeLabel;

  // Attachment handling
  List<PlatformFile> _supportingAttachments = const [];
  List<ExpenseAttachment> _existingAttachments = const [];
  final Set<String> _attachmentsMarkedForDeletion = {};

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.expense.name);
    _categoryController = TextEditingController(text: widget.expense.categoryName);
    _amountController = TextEditingController(
      text: CurrencyInputFormatter.normalizeExistingValue(
        widget.expense.amount?.toStringAsFixed(2) ?? widget.expense.amountLabel,
      ),
    );
    _initialPaymentModeLabel = widget.expense.paymentMode;
    _expenseDate = widget.expense.date ?? DateTime.now();

    // Initialize existing attachments from the expense object
    _existingAttachments = List.of(widget.expense.attachments);

    // Also verify if we can parse single receipt as attachment if not present in list
    if (_existingAttachments.isEmpty && widget.expense.receipt != null && widget.expense.receipt!.isNotEmpty) {
         // We might want to show the receipt URL as an attachment, but ExpenseAttachment needs ID to delete.
         // If it's just a URL string without ID, we can only view it, not delete it via ID API.
         // For now, we rely on the populated attachments list from the new service logic.
    }

    _selectedVendorName = widget.expense.vendor;
    // We don't have vendor ID in Expense object initially, so we try to match by name when vendors load

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadReferenceData();
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _categoryController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadReferenceData() async {
    setState(() {
      _referenceDataError = null;
      _isLoadingReferenceData = true;
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
        _paymentModesService.fetchPaymentModes(headers: headers),
        _vendorsService.fetchVendors(headers: headers),
      ]);

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentModes = results[0] as List<PaymentMode>;
        _vendors = results[1] as List<VendorSummary>;

        _selectedPaymentMode = _resolveInitialPaymentMode();
        _resolveInitialVendor();
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _referenceDataError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingReferenceData = false);
      }
    }
  }

  void _resolveInitialVendor() {
    if (_vendors.isEmpty || _selectedVendorName == null) return;

    final matched = _vendors.firstWhere(
        (v) => v.name.toLowerCase() == _selectedVendorName!.toLowerCase(),
        orElse: () => VendorSummary(id: '', name: ''),
    );

    if (matched.id.isNotEmpty) {
        _selectedVendorId = matched.id;
        _selectedVendorName = matched.name; // Normalized name
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
    final theme = Theme.of(context);

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
                const SizedBox(height: 24),
                Text('Attachments', style: theme.textTheme.titleMedium),
                const SizedBox(height: 12),
                AttachmentPicker(
                  description: 'Drag and drop files or tap to browse.',
                  files: _supportingAttachments,
                  onPick: _pickAttachment,
                  onFilesSelected: (files) =>
                      setState(() => _supportingAttachments = files),
                  onFileRemoved: (file) => setState(() {
                    _supportingAttachments = List.of(_supportingAttachments)
                      ..remove(file);
                  }),
                ),
                const SizedBox(height: 12),
                _ExistingAttachmentsList(
                    attachments: _existingAttachments,
                    onRemove: _scheduleExistingAttachmentRemoval,
                    pendingDeletionCount: _attachmentsMarkedForDeletion.length,
                  ),
                if (_supportingAttachments.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  _NewAttachmentsList(
                    attachments: _supportingAttachments,
                    onRemove: (file) => setState(() {
                      _supportingAttachments = List.of(_supportingAttachments)
                        ..remove(file);
                    }),
                  ),
                ],
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
     if (_isLoadingReferenceData && _vendors.isEmpty) {
      return _ReferenceStatusField(
        label: 'Vendor',
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

    if (_referenceDataError != null && _vendors.isEmpty) {
      return _ReferenceErrorField(
        label: 'Vendor',
        error: _referenceDataError!,
        onRetry: _isLoadingReferenceData ? null : _loadReferenceData,
      );
    }

    return DropdownButtonFormField<String>(
      value: _selectedVendorName, // Using name as value since ID might be missing on existing expense
      decoration: const InputDecoration(
        labelText: 'Vendor',
        hintText: 'Select a vendor',
      ),
      items: _vendors
          .map(
            (vendor) => DropdownMenuItem<String>(
              value: vendor.name,
              child: Text(vendor.name),
            ),
          )
          .toList(),
      onChanged: (value) {
         if (value != null) {
            setState(() {
                _selectedVendorName = value;
                final matched = _vendors.firstWhere((v) => v.name == value, orElse: () => VendorSummary(id: '', name: ''));
                if (matched.id.isNotEmpty) {
                    _selectedVendorId = matched.id;
                }
            });
         }
      },
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
      inputFormatters: const [CurrencyInputFormatter()],
      validator: (value) {
        final sanitized =
            value?.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', '').trim();
        final parsed = double.tryParse(sanitized ?? '');
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
        helperText: _referenceDataError,
      ),
      isExpanded: true,
      hint: _isLoadingReferenceData
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
      onChanged: _paymentModes.isEmpty || _isLoadingReferenceData
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
      _supportingAttachments = [..._supportingAttachments, ...newFiles];
    });
  }

  void _scheduleExistingAttachmentRemoval(int index) {
    setState(() {
      final removed = _existingAttachments.removeAt(index);
      if (removed.id != null && removed.id!.isNotEmpty) {
        _attachmentsMarkedForDeletion.add(removed.id!);
      }
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isSaving = true);

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) return;

    if (token == null || token.trim().isEmpty) {
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('You are not logged in.')),
            );
        }
        setState(() => _isSaving = false);
        return;
    }

    final headers = _buildAuthHeaders(appState, token);

    final parsedAmount = double.tryParse(
      _amountController.text.replaceAll(RegExp(r'[^0-9.,-]'), '').replaceAll(',', ''),
    );
    final resolvedAmount = parsedAmount ?? widget.expense.amount;

    // Prepare request data
    final requestData = {
        'expense_name': _nameController.text.trim(),
        'amount': resolvedAmount,
        'date': DateFormat('yyyy-MM-dd').format(_expenseDate),
        'category': _categoryController.text.trim().isEmpty
          ? widget.expense.categoryName
          : _categoryController.text.trim(),
        'vendor': _selectedVendorId ?? '', // Send ID if available
        // If vendor ID is not available, we might need to send vendor name or handle differently.
        // Assuming backend accepts vendor name if ID is missing or we rely on what we have.
        // But usually ID is required. If _selectedVendorId is null, it means user typed a name that is not in the list?
        // Or we initialized with a name that is not in the list.
        // Dropdown forces selection, so _selectedVendorId should be populated if list loaded.
        'payment_mode': _selectedPaymentMode ?? '',
        // 'tax': ..., 'tax2': ..., 'reference_no': ..., 'note': ... (add if needed)
    };

    // Fallback for vendor if ID missing (e.g. free text if dropdown allowed it, but it doesn't here)
    if ((requestData['vendor'] as String).isEmpty && _selectedVendorName != null) {
        // Try to find it again just in case
        final matched = _vendors.firstWhere(
            (v) => v.name == _selectedVendorName,
            orElse: () => VendorSummary(id: '', name: '')
        );
        if (matched.id.isNotEmpty) {
            requestData['vendor'] = matched.id;
        }
    }

    try {
        // 1. Update Expense
        final updatedExpense = await _expensesService.updateExpense(
            id: widget.expense.id,
            headers: headers,
            data: requestData,
        );

        // 2. Delete Attachments
        if (_attachmentsMarkedForDeletion.isNotEmpty) {
             await _expensesService.deleteAttachments(
                id: widget.expense.id,
                headers: headers,
                attachmentIds: _attachmentsMarkedForDeletion.toList()
             );
        }

        // 3. Upload New Attachments
        if (_supportingAttachments.isNotEmpty) {
            await _expensesService.uploadAttachments(
                id: widget.expense.id,
                headers: headers,
                attachments: _supportingAttachments
            );
        }

        // Since delete/upload are separate calls, the returned 'updatedExpense' from step 1
        // might not contain the latest attachment changes. We might need to fetch it again
        // OR construct it manually. For simplicity, we assume the caller (ExpensesTab) will refresh.
        // Or we can construct the object to return.

        setState(() => _isSaving = false);
        if (mounted) {
             Navigator.of(context).pop(updatedExpense);
        }

    } catch (error) {
        setState(() => _isSaving = false);
        if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Failed to save expense: $error')),
            );
        }
    }
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
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.error,
          ),
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

class _ExistingAttachmentsList extends StatelessWidget {
  const _ExistingAttachmentsList({
    required this.attachments,
    required this.onRemove,
    required this.pendingDeletionCount,
  });

  final List<ExpenseAttachment> attachments;
  final ValueChanged<int> onRemove;
  final int pendingDeletionCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Existing attachments', style: theme.textTheme.titleSmall),
            if (pendingDeletionCount > 0) ...[
              const SizedBox(width: 8),
              Chip(
                label: Text('Deleting on save: $pendingDeletionCount'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ],
        ),
        const SizedBox(height: 8),
        if (attachments.isEmpty)
          Text(
            'No attachments uploaded for this expense.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
          )
        else
          ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: attachments.length,
            itemBuilder: (context, index) {
              final attachment = attachments[index];
              final subtitleParts = <String>[];
              final sizeLabel = attachment.sizeLabel?.trim();
              if (sizeLabel != null && sizeLabel.isNotEmpty) {
                subtitleParts.add(sizeLabel);
              }
              final uploadedBy = attachment.uploadedBy?.trim();
              if (uploadedBy != null && uploadedBy.isNotEmpty) {
                subtitleParts.add('Uploaded by $uploadedBy');
              }
              final subtitle = subtitleParts.isEmpty
                  ? null
                  : subtitleParts.join(' • ');

              return Card(
                key: ValueKey(
                  'existing-attachment-$index-${attachment.fileName}',
                ),
                margin: const EdgeInsets.symmetric(vertical: 4),
                child: ListTile(
                  leading: const Icon(Icons.attach_file),
                  title: Text(attachment.fileName),
                  subtitle: subtitle == null ? null : Text(subtitle),
                  trailing: IconButton(
                    tooltip: 'Remove attachment',
                    icon: const Icon(Icons.close),
                    onPressed: () => onRemove(index),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _NewAttachmentsList extends StatelessWidget {
  const _NewAttachmentsList({
    required this.attachments,
    required this.onRemove,
  });

  final List<PlatformFile> attachments;
  final ValueChanged<PlatformFile> onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'New attachments (uploaded on save)',
          style: theme.textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        ListView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: attachments.length,
          itemBuilder: (context, index) {
            final file = attachments[index];
            return Card(
              key: ValueKey(
                'new-attachment-$index-${file.name}-${file.identifier ?? ''}',
              ),
              margin: const EdgeInsets.symmetric(vertical: 4),
              child: ListTile(
                leading: const Icon(Icons.insert_drive_file_outlined),
                title: Text(file.name),
                subtitle: Text(_formatSize(file.size)),
                trailing: IconButton(
                  tooltip: 'Remove attachment',
                  icon: const Icon(Icons.close),
                  onPressed: () => onRemove(file),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  String _formatSize(int size) {
    const kb = 1024;
    const mb = kb * 1024;
    if (size >= mb) {
      return '${(size / mb).toStringAsFixed(1)} MB';
    }
    if (size >= kb) {
      return '${(size / kb).toStringAsFixed(1)} KB';
    }
    return '$size B';
  }
}
