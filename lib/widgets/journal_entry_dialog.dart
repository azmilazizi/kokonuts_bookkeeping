import 'dart:convert';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/widgets/journal_history_dialog.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/accounts_service.dart';
import '../services/auth_http_client.dart';
import '../services/payment_modes_service.dart';
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
  reimburseOwner('Reimburse Owner'),
  transfer('Transfer');

  const _EntryType(this.label);
  final String label;
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
  static const _attachmentFieldName = 'file';
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController(
    text: CurrencyInputFormatter.normalizeExistingValue(null),
  );
  final _descriptionController = TextEditingController();
  final _dateController = TextEditingController();
  final _entryIdController = TextEditingController();
  final _paymentModesService = PaymentModesService();
  final _accountsService = AccountsService();

  DateTime _journalDate = DateTime.now();
  int? _nextEntryNumber;
  _EntryType? _entryType;
  _AccountMapping? _editingAccountMapping;
  PaymentMode? _paymentMode;
  _Owner? _owner;
  bool _isSubmitting = false;
  bool _isFetchingEntryId = false;
  bool _isLoadingPaymentModes = false;
  String? _submitError;
  String? _entryId;
  String? _entryIdError;
  String? _paymentModesError;
  List<PlatformFile> _attachments = const [];
  List<PaymentMode> _paymentModes = const [];
  List<Account> _transferAccounts = const [];
  Account? _transferFundsFrom;
  Account? _transferFundsTo;
  bool _isLoadingTransferAccounts = false;
  String? _transferAccountsError;

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
    _loadPaymentModes();
    if (_showsTransferAccounts) {
      _loadTransferAccounts();
    }
  }

  Future<void> _loadTransferAccounts() async {
    setState(() {
      _isLoadingTransferAccounts = true;
      _transferAccountsError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _transferAccountsError = 'You are not logged in.';
        _isLoadingTransferAccounts = false;
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final result = await _accountsService.fetchAccounts(
        page: 1,
        perPage: 300,
        headers: headers,
        includeBalances: false,
      );
      final fetchedAccounts = result.accounts;

      if (!mounted) {
        return;
      }

      Account? resolveSelectedAccount(int? id) {
        if (id == null) {
          return null;
        }
        final idText = id.toString();
        for (final account in fetchedAccounts) {
          if (account.id == idText) {
            return account;
          }
        }
        return null;
      }

      setState(() {
        _transferAccounts = fetchedAccounts;
        _isLoadingTransferAccounts = false;

        final existingFrom = resolveSelectedAccount(
          widget.initialItem?.creditAccountId,
        );
        if (_transferFundsFrom == null ||
            !_transferAccounts.any((item) => item.id == _transferFundsFrom!.id)) {
          _transferFundsFrom = existingFrom;
        }

        final existingTo = resolveSelectedAccount(widget.initialItem?.debitAccountId);
        if (_transferFundsTo == null ||
            !_transferAccounts.any((item) => item.id == _transferFundsTo!.id)) {
          _transferFundsTo = existingTo;
        }
      });
    } on AccountsException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _transferAccountsError = error.message;
        _isLoadingTransferAccounts = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _transferAccountsError = 'Failed to load accounts: $error';
        _isLoadingTransferAccounts = false;
      });
    }
  }

  Future<void> _loadPaymentModes() async {
    setState(() {
      _isLoadingPaymentModes = true;
      _paymentModesError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _paymentModesError = 'You are not logged in.';
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
        _isLoadingPaymentModes = false;
        if (_paymentMode != null &&
            !_paymentModes.any((mode) => mode.id == _paymentMode!.id)) {
          _paymentMode = null;
        }
      });
    } on PaymentModesException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paymentModesError = error.message;
        _isLoadingPaymentModes = false;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _paymentModesError = 'Failed to load payment modes: $error';
        _isLoadingPaymentModes = false;
      });
    }
  }

  void _initializeFromExisting() {
    final item = widget.initialItem;
    if (item == null) {
      return;
    }

    _journalDate = item.date ?? _journalDate;
    _entryType = _entryTypeFromString(item.type) ?? _entryType;
    _descriptionController.text = item.description ?? '';
    _amountController.text = CurrencyInputFormatter.normalizeExistingValue(
      item.amount.toString(),
    );
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
    return _entryType == _EntryType.ownersDraw ||
        _entryType == _EntryType.ownersCapitalInjection ||
        _entryType == _EntryType.loanToOwner ||
        _entryType == _EntryType.ownerLoanRepayment ||
        _entryType == _EntryType.reimburseOwner;
  }

  bool get _showsAttachmentPicker =>
      _entryType != _EntryType.cashDeposit &&
      _entryType != _EntryType.cashWithdrawal;

  bool get _showsTransferAccounts => _entryType == _EntryType.transfer;

  bool get _showsDescriptionField =>
      !_isTransfer || _entryType == _EntryType.transfer;

  bool get _isEditing => widget.initialItem != null;

  bool get _isTransfer {
    if (_isEditing) {
      return widget.initialItem?.isTransfer ?? false;
    }

    return _entryType == _EntryType.cashDeposit ||
        _entryType == _EntryType.cashWithdrawal ||
        _entryType == _EntryType.transfer;
  }

  bool get _showsEntryIdField =>
      (!_isTransfer && _entryType != null) || (_isEditing && !_isTransfer);

  void _onEntryTypeChanged(_EntryType? type) {
    setState(() {
      _entryType = type;
      if (type == _EntryType.cashDeposit || type == _EntryType.cashWithdrawal) {
        _descriptionController.text = type!.label;
      } else {
        _descriptionController.clear();
      }
      if (!_showsPaymentMode) {
        _paymentMode = null;
      }
      if (!_showsOwner) {
        _owner = null;
      }
      if (!_showsAttachmentPicker) {
        _attachments = const [];
      }
      if (!_showsTransferAccounts) {
        _transferFundsFrom = null;
        _transferFundsTo = null;
        _transferAccountsError = null;
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

    if (_showsTransferAccounts) {
      _loadTransferAccounts();
    }
  }

  _EntryType? _entryTypeFromString(String? value) {
    if (value == null) return null;
    final normalized = value
        .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
        .toLowerCase();
    for (final type in _EntryType.values) {
      final key = type.name
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toLowerCase();
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
        Uri.parse('https://crm.kokonuts.my/api/v1/option/next_je_number'),
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
              'Failed to fetch entry ID: ${response.statusCode} ${response.reasonPhrase ?? ''}'
                  .trim();
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
            ? tryParseValue(data['next_je_number']) ??
                  tryParseValue(data['value'])
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
        if (_owner == null || _paymentMode?.bankCashAccountId == null) {
          return null;
        }
        return _AccountMapping(
          debitAccountId: _owner!.equityAccountId,
          creditAccountId: _paymentMode!.bankCashAccountId!,
        );
      case _EntryType.ownersCapitalInjection:
        if (_owner == null || _paymentMode?.bankCashAccountId == null) {
          return null;
        }
        return _AccountMapping(
          debitAccountId: _paymentMode!.bankCashAccountId!,
          creditAccountId: _owner!.equityAccountId,
        );
      case _EntryType.loanToOwner:
        if (_owner == null || _paymentMode?.bankCashAccountId == null) {
          return null;
        }
        return _AccountMapping(
          debitAccountId: _owner!.loanToOwnerAccountId,
          creditAccountId: _paymentMode!.bankCashAccountId!,
        );
      case _EntryType.ownerLoanRepayment:
        if (_owner == null || _paymentMode?.bankCashAccountId == null) {
          return null;
        }
        return _AccountMapping(
          debitAccountId: _paymentMode!.bankCashAccountId!,
          creditAccountId: _owner!.loanToOwnerAccountId,
        );
      case _EntryType.reimburseOwner:
        if (_owner == null || _paymentMode?.bankCashAccountId == null) {
          return null;
        }
        return _AccountMapping(
          debitAccountId: _owner!.dueToOwnerAccountId,
          creditAccountId: _paymentMode!.bankCashAccountId!,
        );
      case _EntryType.transfer:
        final from = _transferFundsFrom;
        final to = _transferFundsTo;
        final fromAccountId = int.tryParse(from?.id ?? '');
        final toAccountId = int.tryParse(to?.id ?? '');
        if (fromAccountId == null || toAccountId == null) {
          return null;
        }
        return _AccountMapping(
          debitAccountId: toAccountId,
          creditAccountId: fromAccountId,
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
      if (_paymentMode != null) 'payment_mode': _paymentMode!.name,
    };
  }

  String get _payloadDescription {
    if ((_entryType == _EntryType.cashDeposit ||
            _entryType == _EntryType.cashWithdrawal) &&
        _entryType != null) {
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

  void _addJournalFields(
    http.MultipartRequest request,
    Map<String, dynamic> payload,
  ) {
    void addField(String key, dynamic value) {
      if (value == null) {
        return;
      }
      request.fields[key] = value.toString();
    }

    addField('journal_date', payload['journal_date']);
    addField('datecreated', payload['datecreated']);
    addField('number', payload['number']);
    addField('amount', payload['amount']);
    addField('description', payload['description']);

    final lines = payload['lines'];
    if (lines is List) {
      for (var index = 0; index < lines.length; index++) {
        final line = lines[index];
        if (line is! Map<String, dynamic>) {
          continue;
        }

        void addLineField(String key, dynamic value) {
          if (value == null) return;
          request.fields['lines[$index][$key]'] = value.toString();
        }

        addLineField('account', line['account']);
        addLineField('debit', line['debit']);
        addLineField('credit', line['credit']);
        addLineField('description', line['description']);
      }
    }
  }

  Future<http.Response> _sendJournalEntryRequest({
    required http.Client client,
    required String endpoint,
    required Map<String, dynamic> payload,
    required Map<String, String> headers,
    required bool isUpdate,
  }) async {
    final request = http.MultipartRequest(
      isUpdate ? 'PUT' : 'POST',
      Uri.parse(endpoint),
    );

    final normalizedHeaders = {'Accept': 'application/json', ...headers};
    normalizedHeaders.removeWhere(
      (key, _) => key.toLowerCase() == 'content-type',
    );

    request.headers.addAll(normalizedHeaders);
    _addJournalFields(request, payload);

    final streamedResponse = await client.send(request);
    return http.Response.fromStream(streamedResponse);
  }

  Future<http.MultipartFile?> _buildAttachmentFile(PlatformFile file) async {
    final sanitizedName = file.name.trim();
    if (sanitizedName.isEmpty) {
      return null;
    }

    if (file.readStream != null) {
      return http.MultipartFile(
        _attachmentFieldName,
        file.readStream!,
        file.size,
        filename: sanitizedName,
      );
    }

    if (file.bytes != null) {
      return http.MultipartFile.fromBytes(
        _attachmentFieldName,
        file.bytes!,
        filename: sanitizedName,
      );
    }

    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      return http.MultipartFile.fromPath(
        _attachmentFieldName,
        path,
        filename: sanitizedName,
      );
    }

    return null;
  }

  String _resolveAttachmentEndpoint({
    required String recordId,
    required bool isTransfer,
  }) {
    final baseUrl = isTransfer
        ? 'https://crm.kokonuts.my/accounting/api/v1/transfers'
        : 'https://crm.kokonuts.my/accounting/api/v1/journal_entry';
    return '$baseUrl/$recordId/attachments';
  }

  Future<void> _uploadAttachments({
    required http.Client client,
    required String recordId,
    required Map<String, String> headers,
    required bool isTransfer,
  }) async {
    if (_attachments.isEmpty) {
      return;
    }

    final files = await Future.wait(
      _attachments.map(_buildAttachmentFile),
      eagerError: false,
    );

    final uploadFiles =
        files.whereType<http.MultipartFile>().toList(growable: false);
    if (uploadFiles.isEmpty) {
      return;
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse(
        _resolveAttachmentEndpoint(recordId: recordId, isTransfer: isTransfer),
      ),
    )
      ..headers.addAll({'Accept': 'application/json', ...headers})
      ..files.addAll(uploadFiles);

    http.StreamedResponse response;
    try {
      response = await client.send(request);
    } catch (error) {
      throw Exception('We couldn\'t upload the attachments. Please try again.');
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 &&
        resolved.statusCode != 201 &&
        resolved.statusCode != 204) {
      throw Exception(
        'The attachments couldn\'t be uploaded right now. Please try again later.',
      );
    }
  }

  String? _extractRecordIdFromResponse(Map<String, dynamic>? decoded) {
    if (decoded == null) {
      return null;
    }

    String? resolveId(dynamic value) {
      if (value is int) {
        return value.toString();
      }
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      return null;
    }

    final directId = resolveId(decoded['id']) ??
        resolveId(decoded['journal_entry_id']) ??
        resolveId(decoded['transfer_id']);
    if (directId != null) {
      return directId;
    }

    final data = decoded['data'];
    if (data is Map<String, dynamic>) {
      final dataId = resolveId(data['id']) ??
          resolveId(data['journal_entry_id']) ??
          resolveId(data['transfer_id']);
      if (dataId != null) {
        return dataId;
      }
    }

    final result = decoded['result'];
    if (result is Map<String, dynamic>) {
      final resultId = resolveId(result['id']) ??
          resolveId(result['journal_entry_id']) ??
          resolveId(result['transfer_id']);
      if (resultId != null) {
        return resultId;
      }
    }

    return null;
  }

  Future<void> _submit() async {
    if (_isSubmitting) {
      return;
    }

    final isValid = _formKey.currentState?.validate() ?? false;
    if (!isValid) {
      return;
    }

    if (_showsTransferAccounts &&
        _transferFundsFrom != null &&
        _transferFundsTo != null &&
        _transferFundsFrom!.id == _transferFundsTo!.id) {
      setState(() {
        _submitError =
            'Transfer Funds From and Transfer Funds To must be different accounts.';
      });
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

    final authHeaders = _buildAuthHeaders(appState, token);

    final isTransfer = _isTransfer;
    final addedFrom = appState.currentUserId;
    final recordId = widget.initialItem?.id?.toString();

    if (!_isEditing &&
        isTransfer &&
        (addedFrom == null || addedFrom.trim().isEmpty)) {
      setState(() {
        _submitError =
            'Unable to determine the current user. Please log in again.';
        _isSubmitting = false;
      });
      return;
    }

    if (!_isEditing && !isTransfer && _entryId == null) {
      setState(() {
        _submitError =
            _entryIdError ??
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
            ? 'https://crm.kokonuts.my/accounting/api/v1/transfers/$recordId'
            : 'https://crm.kokonuts.my/accounting/api/v1/journal_entries/$recordId';

        if (isTransfer) {
          response = await client.put(
            Uri.parse(endpoint),
            headers: {...authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
        } else {
          response = await _sendJournalEntryRequest(
            client: client,
            endpoint: endpoint,
            payload: payload,
            headers: authHeaders,
            isUpdate: true,
          );
        }
      } else {
        final endpoint = isTransfer
            ? 'https://crm.kokonuts.my/accounting/api/v1/transfers'
            : 'https://crm.kokonuts.my/accounting/api/v1/journal_entries';

        if (isTransfer) {
          response = await client.post(
            Uri.parse(endpoint),
            headers: {...authHeaders, 'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          );
        } else {
          response = await _sendJournalEntryRequest(
            client: client,
            endpoint: endpoint,
            payload: payload,
            headers: authHeaders,
            isUpdate: false,
          );
        }
      }
    } catch (error) {
      client.close();
      if (!mounted) {
        return;
      }
      setState(() {
        _submitError = 'Failed to reach server: $error';
        _isSubmitting = false;
      });
      return;
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      client.close();
      if (mounted) {
        setState(() {
          _submitError =
              'Request failed with status ${response.statusCode}: ${response.body}';
          _isSubmitting = false;
        });
      }
      return;
    }

    Map<String, dynamic>? decodedBody;
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        decodedBody = decoded;
      }
    } catch (_) {}

    final resolvedRecordId =
        _isEditing ? recordId : _extractRecordIdFromResponse(decodedBody);

    if (!mounted) {
      client.close();
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    if (_attachments.isNotEmpty) {
      if (resolvedRecordId == null) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'Entry saved, but we could not determine the record id to upload attachments.',
            ),
          ),
        );
      } else {
        try {
          await _uploadAttachments(
            client: client,
            recordId: resolvedRecordId,
            headers: authHeaders,
            isTransfer: isTransfer,
          );
        } catch (error) {
          messenger.showSnackBar(
            SnackBar(
              content: Text(
                'Entry saved, but failed to upload attachments: $error',
              ),
            ),
          );
        }
      }
    }

    setState(() => _isSubmitting = false);
    Navigator.of(context).pop();
    client.close();

    messenger.showSnackBar(
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
    final screenSize = MediaQuery.of(context).size;
    final dialogWidth = math.min(screenSize.width * 0.92, 840.0);
    final maxDialogHeight = screenSize.height * 0.8;

    return AlertDialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      titlePadding: const EdgeInsets.fromLTRB(24, 20, 12, 0),
      title: SizedBox(
        width: dialogWidth,
        child: Builder(
          builder: (context) {
            final isCompact = dialogWidth < 520;
            final titleText = Text(
              _isEditing
                  ? 'Edit Journal Entry/Transfers'
                  : 'Journal Entry/Transfer',
              style: const TextStyle(fontWeight: FontWeight.w700),
            );
            final historyButton = !_isEditing
                ? Padding(
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
                  )
                : null;

            if (!isCompact) {
              return Row(
                children: [
                  Expanded(child: titleText),
                  if (historyButton != null) historyButton,
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              );
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(child: titleText),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
                if (historyButton != null) ...[
                  const SizedBox(height: 8),
                  Align(alignment: Alignment.centerLeft, child: historyButton),
                ],
              ],
            );
          },
        ),
      ),
      content: SizedBox(
        width: dialogWidth,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxDialogHeight),
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
                  if (_showsAttachmentPicker) ...[
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
                  ],
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final isWide = constraints.maxWidth >= 620;
                      final dateField = TextFormField(
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
                      );

                      final fields = <Widget>[dateField];

                      if (!_isEditing) {
                        if (isWide) {
                          fields.addAll([
                            const SizedBox(width: 16),
                            Expanded(
                              child: DropdownButtonFormField<_EntryType>(
                                value: _entryType,
                                decoration: const InputDecoration(
                                  labelText: 'Entry Type',
                                ),
                                items: _EntryType.values
                                    .map(
                                      (type) => DropdownMenuItem(
                                        value: type,
                                        child: Text(type.label),
                                      ),
                                    )
                                    .toList(),
                                onChanged: _isSubmitting
                                    ? null
                                    : _onEntryTypeChanged,
                                validator: (value) => value != null
                                    ? null
                                    : 'Please select a journal or transfer type',
                              ),
                            ),
                          ]);

                          return Row(
                            children: fields.map((field) {
                              if (field == dateField) {
                                return Expanded(child: field);
                              }
                              return field;
                            }).toList(),
                          );
                        }

                        fields.addAll([
                          const SizedBox(height: 16),
                          DropdownButtonFormField<_EntryType>(
                            value: _entryType,
                            decoration: const InputDecoration(
                              labelText: 'Entry Type',
                            ),
                            items: _EntryType.values
                                .map(
                                  (type) => DropdownMenuItem(
                                    value: type,
                                    child: Text(type.label),
                                  ),
                                )
                                .toList(),
                            onChanged:
                                _isSubmitting ? null : _onEntryTypeChanged,
                            validator: (value) => value != null
                                ? null
                                : 'Please select a journal or transfer type',
                          ),
                        ]);
                      }

                      if (isWide) {
                        return Row(
                          children: fields.map((field) {
                            if (field == dateField) {
                              return Expanded(child: field);
                            }
                            return field;
                          }).toList(),
                        );
                      }

                      return Column(children: fields);
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
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                      ),
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
                        Widget? paymentModeField;
                        if (_showsPaymentMode) {
                          paymentModeField =
                              DropdownButtonFormField<PaymentMode>(
                            value: _paymentMode,
                            decoration: const InputDecoration(
                              labelText: 'Payment Mode',
                            ),
                            items: _paymentModes
                                .map(
                                  (mode) => DropdownMenuItem(
                                    value: mode,
                                    child: Text(mode.name),
                                  ),
                                )
                                .toList(),
                            onChanged: _isSubmitting || _isLoadingPaymentModes
                                ? null
                                : (value) =>
                                      setState(() => _paymentMode = value),
                            validator: (value) {
                              if (!_showsPaymentMode) {
                                return null;
                              }
                              if (value == null) {
                                return 'Select a payment mode';
                              }
                              if (value.bankCashAccountId == null) {
                                return 'Selected payment mode has no mapped account';
                              }
                              return null;
                            },
                          );
                        }

                        Widget? ownerField;
                        if (_showsOwner) {
                          ownerField = DropdownButtonFormField<_Owner>(
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
                            validator: (value) =>
                                _showsOwner && value == null
                                ? 'Select an owner'
                                : null,
                          );
                        }

                        if (isWide) {
                          return Row(
                            children: [
                              if (paymentModeField != null)
                                Expanded(child: paymentModeField),
                              if (paymentModeField != null &&
                                  ownerField != null)
                                const SizedBox(width: 16),
                              if (ownerField != null)
                                Expanded(child: ownerField),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            if (paymentModeField != null) paymentModeField,
                            if (_showsPaymentMode && _isLoadingPaymentModes)
                              const Padding(
                                padding: EdgeInsets.only(top: 8),
                                child: LinearProgressIndicator(minHeight: 2),
                              ),
                            if (_showsPaymentMode && _paymentModesError != null)
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: _isLoadingPaymentModes
                                      ? null
                                      : _loadPaymentModes,
                                  icon: const Icon(Icons.refresh),
                                  label: const Text('Retry payment modes'),
                                ),
                              ),
                            if (paymentModeField != null && ownerField != null)
                              const SizedBox(height: 12),
                            if (ownerField != null) ownerField,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (_showsTransferAccounts) ...[
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final isWide = constraints.maxWidth >= 620;
                        final fromField = DropdownButtonFormField<Account>(
                          value: _transferFundsFrom,
                          decoration: const InputDecoration(
                            labelText: 'Transfer Funds From',
                          ),
                          items: _transferAccounts
                              .map(
                                (account) => DropdownMenuItem(
                                  value: account,
                                  child: Text(account.name),
                                ),
                              )
                              .toList(),
                          onChanged: _isSubmitting || _isLoadingTransferAccounts
                              ? null
                              : (value) =>
                                    setState(() => _transferFundsFrom = value),
                          validator: (value) {
                            if (!_showsTransferAccounts) {
                              return null;
                            }
                            if (value == null) {
                              return 'Select an account';
                            }
                            return null;
                          },
                        );

                        final toField = DropdownButtonFormField<Account>(
                          value: _transferFundsTo,
                          decoration: const InputDecoration(
                            labelText: 'Transfer Funds To',
                          ),
                          items: _transferAccounts
                              .map(
                                (account) => DropdownMenuItem(
                                  value: account,
                                  child: Text(account.name),
                                ),
                              )
                              .toList(),
                          onChanged: _isSubmitting || _isLoadingTransferAccounts
                              ? null
                              : (value) =>
                                    setState(() => _transferFundsTo = value),
                          validator: (value) {
                            if (!_showsTransferAccounts) {
                              return null;
                            }
                            if (value == null) {
                              return 'Select an account';
                            }
                            if (_transferFundsFrom != null &&
                                value.id == _transferFundsFrom!.id) {
                              return 'Please choose a different account';
                            }
                            return null;
                          },
                        );

                        if (isWide) {
                          return Row(
                            children: [
                              Expanded(child: fromField),
                              const SizedBox(width: 16),
                              Expanded(child: toField),
                            ],
                          );
                        }

                        return Column(
                          children: [
                            fromField,
                            const SizedBox(height: 12),
                            toField,
                          ],
                        );
                      },
                    ),
                    if (_isLoadingTransferAccounts)
                      const Padding(
                        padding: EdgeInsets.only(top: 8),
                        child: LinearProgressIndicator(minHeight: 2),
                      ),
                    if (_transferAccountsError != null)
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: _isLoadingTransferAccounts
                              ? null
                              : _loadTransferAccounts,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry accounts'),
                        ),
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
                  if (_showsDescriptionField) ...[
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
