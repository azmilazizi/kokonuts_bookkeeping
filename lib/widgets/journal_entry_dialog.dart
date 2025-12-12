import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/widgets/journal_history_dialog.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/auth_http_client.dart';
import 'attachment_picker.dart';
import 'currency_input_formatter.dart';
import 'form_error_banner.dart';

enum _EntryType {
  cashDeposit('Cash Deposit'),
  cashWithdrawal('Cash Withdrawal'),
  ownersDraw("Owner's Draw"),
  ownersCapitalInjection("Owner's Capital Injection"),
  loanToOwner('Loan to Owner'),
  ownerLoanRepayment('Owner Loan Repayment'),
  reimburseOwner('Reimburse Owner');

  const _EntryType(this.label);
  final String label;
}

enum _PaymentMode {
  cash('Cash', 2),
  bankTransfer('Bank Transfer', 139);

  const _PaymentMode(this.label, this.bankCashAccountId);
  final String label;
  final int bankCashAccountId;
}

enum _Owner {
  azmil('Azmil'),
  fakrul('Fakrul');

  const _Owner(this.label);
  final String label;

  int get equityAccountId => this == _Owner.azmil ? 203 : 204;
  int get dueToOwnerAccountId => this == _Owner.azmil ? 141 : 142;
  int get loanToOwnerAccountId => this == _Owner.azmil ? 206 : 207;
}

class _AccountMapping {
  const _AccountMapping({
    required this.debitAccountId,
    required this.creditAccountId,
  });

  final int debitAccountId;
  final int creditAccountId;
}

class JournalEntryDialog extends StatefulWidget {
  const JournalEntryDialog({super.key, this.initialItem});

  final JournalListItem? initialItem;

  @override
  State<JournalEntryDialog> createState() => _JournalEntryDialogState();
}

class _JournalEntryDialogState extends State<JournalEntryDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(
    text: CurrencyInputFormatter.normalizeExistingValue(null),
  );
  final _descriptionController = TextEditingController();
  final _dateController = TextEditingController();
  final _entryIdController = TextEditingController();

  DateTime _journalDate = DateTime.now();
  int? _nextEntryNumber;
  _EntryType? _entryType;
  _AccountMapping? _editingAccountMapping;
  _PaymentMode? _paymentMode;
  _Owner? _owner;
  bool _isSubmitting = false;
  bool _isFetchingEntryId = false;
  String? _submitError;
  String? _entryId;
  String? _entryIdError;
  List<PlatformFile> _attachments = const [];

  @override
  void dispose() {
    _amountController.dispose();
    _descriptionController.dispose();
    _dateController.dispose();
    _entryIdController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _initializeFromExisting();
    _updateDateText();
  }

  void _initializeFromExisting() {
    final item = widget.initialItem;
    if (item == null) {
      return;
    }

    _journalDate = item.date ?? _journalDate;
    _entryType = _entryTypeFromString(item.type) ?? _entryType;
    _descriptionController.text = item.description ?? '';
    _amountController.text = CurrencyInputFormatter.normalizeExistingValue(item.amount);
    _entryId = item.entryId ?? item.number;
    _entryIdController.text = _entryId ?? '';

    if (item.debitAccountId != null && item.creditAccountId != null) {
      _editingAccountMapping = _AccountMapping(
        debitAccountId: item.debitAccountId!,
        creditAccountId: item.creditAccountId!,
      );
    }
  }

  Future<void> _pickAttachments() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      withData: true,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(),
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    final validFiles = result.files
        .where(
          (file) =>
              isAllowedAttachmentExtension(attachmentExtension(file.name)),
        )
        .toList();

    if (validFiles.isEmpty) {
      return;
    }

    setState(() {
      _attachments = [..._attachments, ...validFiles];
    });
  }

  void _onFilesSelected(List<PlatformFile> files) {
    setState(() => _attachments = files);
  }

  void _removeAttachment(PlatformFile file) {
    setState(() {
      _attachments = List.of(_attachments)..remove(file);
    });
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _journalDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );

    if (selected != null) {
      setState(() {
        _journalDate = selected;
        _updateDateText();
      });
      _updateEntryIdWithCurrentDate();
    }
  }

  String get _formattedDate => DateFormat('yyyy-MM-dd').format(_journalDate);

  String? get _formattedEntryId {
    if (_nextEntryNumber == null) {
      return null;
    }
    final formattedDate = DateFormat('ddMMyyyy').format(_journalDate);
    return '#JE-${_nextEntryNumber!.toString().padLeft(5, '0')}-$formattedDate';
  }

  void _updateDateText() {
    _dateController.text = _formattedDate;
  }

  void _updateEntryIdWithCurrentDate() {
    final formattedEntryId = _formattedEntryId;

    if (!_showsEntryIdField || formattedEntryId == null) {
      return;
    }

    setState(() {
      _entryId = formattedEntryId;
      _entryIdController.text = formattedEntryId;
    });
  }

  bool get _showsPaymentMode {
    return _entryType == _EntryType.ownersDraw ||
        _entryType == _EntryType.ownersCapitalInjection ||
        _entryType == _EntryType.loanToOwner ||
        _entryType == _EntryType.ownerLoanRepayment ||
        _entryType == _EntryType.reimburseOwner;
  }

  bool get _showsOwner {
    return _entryType != null &&
        _entryType != _EntryType.cashDeposit &&
        _entryType != _EntryType.cashWithdrawal;
  }

  bool get _isEditing => widget.initialItem != null;

  bool get _isTransfer {
    if (_isEditing) {
      return widget.initialItem?.isTransfer ?? false;
    }

    return _entryType == _EntryType.cashDeposit ||
        _entryType == _EntryType.cashWithdrawal;
  }

  bool get _showsEntryIdField =>
      (!_isTransfer && _entryType != null) || (_isEditing && !_isTransfer);

  void _onEntryTypeChanged(_EntryType? type) {
    setState(() {
      _entryType = type;
      if (_isTransfer && type != null) {
        _descriptionController.text = type.label;
      } else {
        _descriptionController.clear();
      }
      if (!_showsPaymentMode) {
        _paymentMode = null;
      }
      if (!_showsOwner) {
        _owner = null;
      }
      if (!_showsEntryIdField) {
        _entryId = null;
        _entryIdController.clear();
        _nextEntryNumber = null;
        _entryIdError = null;
        _isFetchingEntryId = false;
      }
    });

    if (_showsEntryIdField) {
      _fetchNextEntryNumber();
    }
  }

  _EntryType? _entryTypeFromString(String? value) {
    if (value == null) return null;
    final normalized = value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
    for (final type in _EntryType.values) {
      final key = type.name.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toLowerCase();
      if (key == normalized) {
        return type;
      }
    }
    return null;
  }

  Future<void> _fetchNextEntryNumber() async {
    setState(() {
      _isFetchingEntryId = true;
      _entryIdError = null;
      _entryId = null;
      _nextEntryNumber = null;
      _entryIdController.clear();
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _entryIdError = 'You are not logged in.';
        _isFetchingEntryId = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);
    final client = createAuthAwareClient();
    http.Response response;

    try {
      response = await client.get(
        Uri.parse(
          'https://crm.kokonuts.my/api/v1/option/next_je_number',
        ),
        headers: headers,
      );
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _entryIdError = 'Failed to fetch entry ID: $error';
        _isFetchingEntryId = false;
      });
      return;
    } finally {
      client.close();
    }

    if (response.statusCode != 200) {
      if (mounted) {
        setState(() {
          _entryIdError =
              'Failed to fetch entry ID: ${response.statusCode} ${response.reasonPhrase ?? ''}'.trim();
          _isFetchingEntryId = false;
        });
      }
      return;
    }

    final decoded = jsonDecode(response.body);
    final nextNumber = _parseNextEntryNumber(decoded);

    if (nextNumber == null) {
      setState(() {
        _entryIdError = 'Invalid response when generating entry ID.';
        _isFetchingEntryId = false;
      });
      return;
    }

    final formattedEntryId =
        '#JE-${nextNumber.toString().padLeft(5, '0')}-${DateFormat('ddMMyyyy').format(_journalDate)}';

    setState(() {
      _nextEntryNumber = nextNumber;
      _entryId = formattedEntryId;
      _entryIdController.text = formattedEntryId;
      _entryIdError = null;
      _isFetchingEntryId = false;
    });
  }

  int? _parseNextEntryNumber(dynamic decoded) {
    int? tryParseValue(dynamic value) {
      if (value is int) {
        return value;
      }
      if (value is String) {
        return int.tryParse(value);
      }
      return null;
    }

    if (decoded is! Map<String, dynamic>) {
      return null;
    }

    final data = decoded['data'];
    final result = decoded['result'];

    return tryParseValue(decoded['next_je_number']) ??
        tryParseValue(decoded['value']) ??
        (data is Map<String, dynamic>
            ? tryParseValue(data['next_je_number']) ?? tryParseValue(data['value'])
            : null) ??
        (result is Map<String, dynamic>
            ? tryParseValue(result['next_je_number']) ??
                tryParseValue(result['value'])
            : null);
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

  double? _parseAmount() {
    final cleaned = _amountController.text
        .replaceAll(RegExp(r'[^0-9.,-]'), '')
        .replaceAll(',', '')
        .trim();
    if (cleaned.isEmpty) {
      return null;
    }
    return double.tryParse(cleaned);
  }

  _AccountMapping? _resolveAccounts() {
    if (_isEditing && _editingAccountMapping != null) {
      return _editingAccountMapping;
    }

    final entryType = _entryType;
    if (entryType == null) {
      return null;
    }

    switch (entryType) {
      case _EntryType.cashDeposit:
        return const _AccountMapping(debitAccountId: 139, creditAccountId: 2);
      case _EntryType.cashWithdrawal:
        return const _AccountMapping(debitAccountId: 2, creditAccountId: 139);
      case _EntryType.ownersDraw:
        if (_owner == null || _paymentMode == null) return null;
        return _AccountMapping(
          debitAccountId: _owner!.equityAccountId,
          creditAccountId: _paymentMode!.bankCashAccountId,
        );
      case _EntryType.ownersCapitalInjection:
        if (_owner == null || _paymentMode == null) return null;
        return _AccountMapping(
          debitAccountId: _paymentMode!.bankCashAccountId,
          creditAccountId: _owner!.equityAccountId,
        );
      case _EntryType.loanToOwner:
        if (_owner == null || _paymentMode == null) return null;
        return _AccountMapping(
          debitAccountId: _owner!.loanToOwnerAccountId,
          creditAccountId: _paymentMode!.bankCashAccountId,
        );
      case _EntryType.ownerLoanRepayment:
        if (_owner == null || _paymentMode == null) return null;
        return _AccountMapping(
          debitAccountId: _paymentMode!.bankCashAccountId,
          creditAccountId: _owner!.loanToOwnerAccountId,
        );
      case _EntryType.reimburseOwner:
        if (_owner == null || _paymentMode == null) return null;
        return _AccountMapping(
          debitAccountId: _owner!.dueToOwnerAccountId,
          creditAccountId: _paymentMode!.bankCashAccountId,
        );
    }
  }

  Map<String, dynamic> _buildTransferPayload(
    _AccountMapping accounts,
    double amount,
    String addedFrom,
  ) {
    final transferFundsFrom = accounts.creditAccountId;
    final transferFundsTo = accounts.debitAccountId;

    final addedFromValue = int.tryParse(addedFrom) ?? addedFrom;

    return {
      'date': _formattedDate,
      'description': _payloadDescription,
      'transfer_amount': amount,
      'transfer_funds_from': transferFundsFrom,
      'transfer_funds_to': transferFundsTo,
      'addedfrom': addedFromValue,
      if (_paymentMode != null) 'payment_mode': _paymentMode!.label,
    };
  }

  String get _payloadDescription {
    if (_isTransfer && _entryType != null) {
      return _entryType!.label;
    }
    return _descriptionController.text.trim();
  }

  Map<String, dynamic> _buildJournalPayload(
    _AccountMapping accounts,
    double amount,
  ) {
    return {
      'journal_date': _formattedDate,
      'datecreated': _formattedDate,
      'number': _entryId,
      'amount': amount,
      'description': _payloadDescription,
      'lines': [
        {
          'account': accounts.debitAccountId,
          'debit': amount,
          'credit': 0,
          'description': _payloadDescription,
        },
        {
          'account': accounts.creditAccountId,
          'debit': 0,
          'credit': amount,
          'description': _payloadDescription,
        },
      ],
    };
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    final amount = _parseAmount();
    if (amount == null || amount <= 0) {
      setState(() {
        _submitError = 'Please enter a valid amount.';
      });
      return;
    }

    final accountMapping = _resolveAccounts();
    if (accountMapping == null) {
      setState(() {
        _submitError = 'Unable to resolve accounts for this entry type.';
      });
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

    final headers = {
      ..._buildAuthHeaders(appState, token),
      'Content-Type': 'application/json',
    };

    final isTransfer = _isTransfer;
    final addedFrom = appState.currentUserId;
    final recordId = widget.initialItem?.id?.toString();

    if (!_isEditing &&
        isTransfer &&
        (addedFrom == null || addedFrom.trim().isEmpty)) {
      setState(() {
        _submitError = 'Unable to determine the current user. Please log in again.';
        _isSubmitting = false;
      });
      return;
    }

    if (!_isEditing && !isTransfer && _entryId == null) {
      setState(() {
        _submitError = _entryIdError ??
            'Unable to generate an entry ID. Please try again.';
        _isSubmitting = false;
      });
      if (_entryIdError != null) {
        _fetchNextEntryNumber();
      }
      return;
    }

    if (_isEditing && recordId == null) {
      setState(() {
        _submitError = 'Unable to determine record id for update.';
        _isSubmitting = false;
      });
      return;
    }

    final payload = isTransfer
        ? _buildTransferPayload(accountMapping, amount, addedFrom ?? '')
        : _buildJournalPayload(accountMapping, amount);

    http.Response response;
    final client = createAuthAwareClient();
    try {
      if (_isEditing) {
        final endpoint = isTransfer
            ? 'https://crm.kokonuts.my/accounting/api/v1/transfer/$recordId'
            : 'https://crm.kokonuts.my/accounting/api/v1/journal_entry/$recordId';
        response = await client.patch(
          Uri.parse(endpoint),
          headers: headers,
          body: jsonEncode(payload),
        );
      } else {
        final endpoint = isTransfer
            ? 'https://crm.kokonuts.my/accounting/api/v1/transfers'
            : 'https://crm.kokonuts.my/accounting/api/v1/journal_entries';
        response = await client.post(
          Uri.parse(endpoint),
          headers: headers,
          body: jsonEncode(payload),
        );
      }
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = 'Failed to reach server: $error';
        _isSubmitting = false;
      });
      return;
    } finally {
      client.close();
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      if (mounted) {
        setState(() {
          _submitError =
              'Request failed with status ${response.statusCode}: ${response.body}';
          _isSubmitting = false;
        });
      }
      return;
    }

    if (!mounted) {
      return;
    }

    setState(() => _isSubmitting = false);
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _isEditing
              ? (isTransfer
                  ? 'Transfer updated successfully.'
                  : 'Journal entry updated successfully.')
              : (isTransfer
                  ? 'Transfer submitted successfully.'
                  : 'Journal entry submitted successfully.'),
        ),
      ),
    );
  }

  Future<void> _openJournalHistory() async {
    await showDialog<void>(
      context: context,
      builder: (context) => JournalHistoryDialog(
        onEdit: (item) async {
          await showDialog(
            context: context,
            builder: (context) => JournalEntryDialog(initialItem: item),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final dialogWidth = (MediaQuery.of(context).size.width * 0.92).clamp(
      420.0,
      840.0,
    );

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: Row(
        children: [
          Expanded(
            child: Text(
              _isEditing
                  ? 'Edit Journal Entry/Transfers'
                  : 'Journal Entry/Transfer',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          if (!_isEditing)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: _openJournalHistory,
                child: const Text('View Journal Entry and Transfers'),
              ),
            ),
          IconButton(
            tooltip: 'Close',
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(right: 12, bottom: 12),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_submitError != null) ...[
                  FormErrorBanner(message: _submitError!),
                  const SizedBox(height: 12),
                ],
                AttachmentPicker(
                  label: 'Attachments',
                  description:
                      'Upload receipts, statements, or supporting files.',
                  files: _attachments,
                  onPick: _pickAttachments,
                  onFilesSelected: _onFilesSelected,
                  onFileRemoved: _removeAttachment,
                ),
                const SizedBox(height: 20),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 620;
                    final dateField = Expanded(
                      child: TextFormField(
                        readOnly: true,
                        controller: _dateController,
                        decoration: const InputDecoration(
                          labelText: 'Journal Date',
                          prefixIcon: Icon(Icons.event),
                        ),
                        onTap: _pickDate,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Journal date is required';
                          }
                          return null;
                        },
                      ),
                    );

                    final entryTypeField = Expanded(
                      child: DropdownButtonFormField<_EntryType>(
                        value: _entryType,
                        decoration:
                            const InputDecoration(labelText: 'Entry Type'),
                        items: _EntryType.values
                            .map(
                              (type) => DropdownMenuItem(
                                value: type,
                                child: Text(type.label),
                              ),
                            )
                            .toList(),
                        onChanged:
                            _isSubmitting || _isEditing ? null : _onEntryTypeChanged,
                        validator: (value) => _isEditing || value != null
                            ? null
                            : 'Please select a journal or transfer type',
                      ),
                    );

                    if (isWide) {
                      return Row(
                        children: [
                          dateField,
                          const SizedBox(width: 16),
                          entryTypeField,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        dateField,
                        const SizedBox(height: 16),
                        entryTypeField,
                      ],
                    );
                  },
                ),
                const SizedBox(height: 16),
                if (_showsEntryIdField)
                  Column(
                    children: [
                      TextFormField(
                        controller: _entryIdController,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Entry ID',
                          prefixIcon: const Icon(Icons.tag),
                          errorText: _entryIdError,
                          suffixIcon: _isFetchingEntryId
                              ? const Padding(
                                  padding: EdgeInsets.all(12),
                                  child: SizedBox(
                                    width: 16,
                                    height: 16,
                                    child:
                                        CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                )
                              : (_entryIdError != null
                                  ? IconButton(
                                      tooltip: 'Retry',
                                      onPressed: _fetchNextEntryNumber,
                                      icon: const Icon(Icons.refresh),
                                    )
                                  : null),
                        ),
                        validator: (_) {
                          if (_showsEntryIdField &&
                              (_entryId == null || _entryId!.isEmpty)) {
                            return _entryIdError ?? 'Entry ID is required';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                    ],
                  ),
                if (_showsPaymentMode || _showsOwner) ...[
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 620;
                      final fieldWidgets = <Widget>[];

                      if (_showsPaymentMode) {
                        fieldWidgets.add(
                          Expanded(
                            child: DropdownButtonFormField<_PaymentMode>(
                              value: _paymentMode,
                              decoration: const InputDecoration(
                                labelText: 'Payment Mode',
                              ),
                              items: _PaymentMode.values
                                  .map(
                                    (mode) => DropdownMenuItem(
                                      value: mode,
                                      child: Text(mode.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _isSubmitting
                                  ? null
                                  : (value) =>
                                        setState(() => _paymentMode = value),
                              validator: (value) =>
                                  _showsPaymentMode && value == null
                                  ? 'Select a payment mode'
                                  : null,
                            ),
                          ),
                        );
                      }

                      if (_showsOwner) {
                        if (fieldWidgets.isNotEmpty) {
                          fieldWidgets.add(const SizedBox(width: 16));
                        }
                        fieldWidgets.add(
                          Expanded(
                            child: DropdownButtonFormField<_Owner>(
                              value: _owner,
                              decoration: const InputDecoration(
                                labelText: 'Owner',
                              ),
                              items: _Owner.values
                                  .map(
                                    (owner) => DropdownMenuItem(
                                      value: owner,
                                      child: Text(owner.label),
                                    ),
                                  )
                                  .toList(),
                              onChanged: _isSubmitting
                                  ? null
                                  : (value) => setState(() => _owner = value),
                              validator: (value) => _showsOwner && value == null
                                  ? 'Select an owner'
                                  : null,
                            ),
                          ),
                        );
                      }

                      if (isWide) {
                        return Row(children: fieldWidgets);
                      }

                      return Column(
                        children: [
                          ...fieldWidgets.expand((field) sync* {
                            yield field;
                            if (field != fieldWidgets.last) {
                              yield const SizedBox(height: 12);
                            }
                          }),
                        ],
                      );
                    },
                  ),
                  const SizedBox(height: 16),
                ],
                TextFormField(
                  controller: _amountController,
                  keyboardType: TextInputType.number,
                  inputFormatters: const [CurrencyInputFormatter()],
                  decoration: const InputDecoration(
                    labelText: 'Amount',
                    prefixIcon: Icon(Icons.payments_outlined),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Amount is required';
                    }
                    return null;
                  },
                  enabled: !_isSubmitting,
                ),
                if (!_isTransfer) ...[
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _descriptionController,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 4,
                    minLines: 3,
                    enabled: !_isSubmitting,
                    validator: (value) {
                      if (value == null || value.trim().isEmpty) {
                        return 'Description is required';
                      }
                      return null;
                    },
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
        ElevatedButton(
          onPressed: _isSubmitting ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
