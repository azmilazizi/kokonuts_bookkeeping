import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/app/app_state.dart';
import 'package:kokonuts_bookkeeping/app/app_state_scope.dart';
import 'attachment_pdf_preview.dart';
import 'attachment_picker.dart';

import '../services/accounts_service.dart';
import '../services/bills_service.dart';
import '../services/payment_modes_service.dart';

class BillDetailsDialog extends StatefulWidget {
  const BillDetailsDialog({
    super.key,
    required this.bill,
    required this.vendorName,
  });

  final Bill bill;
  final String vendorName;

  @override
  State<BillDetailsDialog> createState() => _BillDetailsDialogState();
}

class _BillDetailsDialogState extends State<BillDetailsDialog> {
  late Future<Bill> _future;
  final _billsService = BillsService();
  final _accountsService = AccountsService();
  bool _initialized = false;
  bool _isLoadingAccounts = false;
  bool _isLoadingAccountNames = false;
  bool _isLoadingPayments = false;
  String? _accountsError;
  String? _paymentsError;
  List<Account> _accounts = const [];
  Map<String, String> _accountNamesById = {};
  List<BillPayment> _payments = const [];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _loadDetails();
      _initialized = true;
    }
  }

  Future<Bill> _loadDetails() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      throw BillsException('Dialog no longer mounted');
    }

    if (token == null || token.trim().isEmpty) {
      throw BillsException('You are not logged in.');
    }

    final headers = _buildAuthHeaders(appState, token);

    setState(() {
      _isLoadingAccounts = true;
      _isLoadingAccountNames = false;
      _isLoadingPayments = true;
      _accountsError = null;
      _paymentsError = null;
      _accountNamesById = {};
      _payments = const [];
    });

    try {
      final bill = await _billsService.getBill(
        id: widget.bill.id,
        headers: headers,
      );

      if (!mounted) {
        return bill;
      }

      await Future.wait([
        _loadAccounts(headers),
        _loadAccountNames(bill, headers),
        _loadPayments(bill.id, headers),
      ]);

      return bill;
    } catch (error) {
      if (mounted) {
        setState(() {
          _isLoadingAccounts = false;
          _isLoadingAccountNames = false;
          _isLoadingPayments = false;
        });
      }
      rethrow;
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
    return {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };
  }

  final _pendingPayments = <BillPayment>[];

  List<BillPayment> _buildPaymentEntries(Bill bill) {
    final entries = <BillPayment>[];

    if (_payments.isNotEmpty) {
      entries.addAll(_payments);
    } else if (bill.payments.isNotEmpty) {
      entries.addAll(bill.payments);
    } else if (bill.attachments.isNotEmpty) {
      entries.addAll(
        bill.attachments.map(
          (attachment) => BillPayment(
            id: attachment.paymentId ?? attachment.id ?? attachment.fileName,
            date: attachment.paymentDate ?? attachment.uploadedAt,
            paymentAccount: attachment.description,
            amount: attachment.amount,
            attachment: attachment,
          ),
        ),
      );
    }

    entries.addAll(_pendingPayments);
    return entries;
  }

  List<BillAttachment> _collectAttachments(
    Bill bill,
    List<BillPayment> payments,
  ) {
    final seen = <String>{};
    final attachments = <BillAttachment>[];

    void addAttachment(BillAttachment attachment) {
      final key =
          attachment.id ?? attachment.downloadUrl ?? attachment.fileName;
      if (seen.add(key)) {
        attachments.add(attachment);
      }
    }

    for (final payment in payments) {
      final attachment = payment.attachment;
      if (attachment != null) {
        addAttachment(attachment);
      }
    }

    for (final attachment in bill.attachments) {
      addAttachment(attachment);
    }

    return attachments;
  }

  Future<void> _loadAccounts(Map<String, String> headers) async {
    try {
      final accounts = await _accountsService.fetchAccounts(
        page: 1,
        perPage: 200,
        headers: headers,
      );

      if (mounted) {
        setState(() {
          _accounts = accounts.accounts;
          _accountNamesById = {..._accountNamesById, ...accounts.namesById};
          _isLoadingAccounts = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _accountsError = error.toString();
          _isLoadingAccounts = false;
        });
      }
    }
  }

  Future<void> _loadPayments(
    String billId,
    Map<String, String> headers,
  ) async {
    try {
      final payments = await _billsService.fetchBillPayments(
        billId: billId,
        headers: headers,
      );

      await _populatePaymentAccountNames(payments, headers);

      if (mounted) {
        setState(() {
          _payments = payments;
          _isLoadingPayments = false;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _paymentsError = error.toString();
          _isLoadingPayments = false;
        });
      }
    }
  }

  Future<void> _populatePaymentAccountNames(
    List<BillPayment> payments,
    Map<String, String> headers,
  ) async {
    final creditIds = payments
        .map((payment) => payment.paymentAccountId?.trim())
        .where((id) => id != null && id!.isNotEmpty)
        .where((id) => !_accountNamesById.containsKey(id))
        .toSet();

    if (creditIds.isEmpty) {
      return;
    }

    try {
      final results = await Future.wait(
        creditIds.map(
          (id) async {
            final account = await _accountsService.fetchAccountById(
              id: id!,
              headers: headers,
            );
            return MapEntry(id, account.name);
          },
        ),
      );

      if (mounted) {
        setState(() {
          for (final entry in results) {
            _accountNamesById[entry.key] = entry.value;
          }
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _paymentsError ??=
              'Unable to resolve payment accounts: ${error.toString()}';
        });
      }
    }
  }

  Future<void> _loadAccountNames(
    Bill bill,
    Map<String, String> headers,
  ) async {
    final creditId = bill.creditAccountId;
    final debitId = bill.debitAccountId;

    if ((creditId == null || creditId.trim().isEmpty) &&
        (debitId == null || debitId.trim().isEmpty)) {
      return;
    }

    if (mounted) {
      setState(() {
        _isLoadingAccountNames = true;
        _accountsError = null;
      });
    }

    String? errorMessage;

    Future<void> fetchName(String? id) async {
      final trimmedId = id?.trim();
      if (trimmedId == null || trimmedId.isEmpty) {
        return;
      }

      try {
        final account = await _accountsService.fetchAccountById(
          id: trimmedId,
          headers: headers,
        );

        if (mounted) {
          setState(() {
            _accountNamesById[trimmedId] = account.name;
          });
        }
      } catch (error) {
        errorMessage ??= error.toString();
      }
    }

    await Future.wait([
      fetchName(creditId),
      fetchName(debitId),
    ]);

    if (mounted) {
      setState(() {
        _isLoadingAccountNames = false;
        if (errorMessage != null) {
          _accountsError = errorMessage;
        }
      });
    }
  }

  Future<void> _openAddPaymentDialog(Bill bill) async {
    final result = await showDialog<BillPayment>(
      context: context,
      barrierDismissible: false,
      builder: (context) =>
          _AddPaymentDialog(currencySymbol: bill.currencySymbol),
    );

    if (result != null) {
      setState(() => _pendingPayments.add(result));
    }
  }

  Future<void> _openEditPaymentDialog(
    BillPayment payment,
    Bill bill,
  ) async {
    final result = await showDialog<BillPayment>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _EditPaymentDialog(
        payment: payment,
        currencySymbol: bill.currencySymbol,
      ),
    );

    if (result == null) {
      return;
    }

    setState(() {
      var replaced = false;
      for (var i = 0; i < _payments.length; i++) {
        if (_payments[i].id == result.id) {
          _payments[i] = result;
          replaced = true;
        }
      }

      if (!replaced) {
        for (var i = 0; i < _pendingPayments.length; i++) {
          if (_pendingPayments[i].id == result.id) {
            _pendingPayments[i] = result;
            replaced = true;
          }
        }
      }

      if (!replaced) {
        _pendingPayments.add(result);
      }

      final accountId = result.paymentAccountId?.trim();
      if (accountId != null && accountId.isNotEmpty) {
        final accountName = result.paymentAccount?.trim();
        if (accountName != null && accountName.isNotEmpty) {
          _accountNamesById[accountId] = accountName;
        }
      }
    });
  }

  void _handlePreviewAttachment(BillAttachment attachment) {
    final normalizedDownloadUrl = attachment.downloadUrl != null
        ? _normalizeAttachmentDownloadUrl(attachment.downloadUrl!)
        : null;
    final previewType = _resolvePreviewType(
      attachment.fileName,
      normalizedDownloadUrl,
    );

    if (normalizedDownloadUrl == null || previewType == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No preview available for this attachment.'),
        ),
      );
      return;
    }

    _showAttachmentPreview(
      context: context,
      fileName: attachment.fileName,
      downloadUrl: normalizedDownloadUrl,
      previewType: previewType,
    );
  }

  String _resolveAccountName(String? accountIdOrName) {
    final value = accountIdOrName?.trim();
    if (value == null || value.isEmpty) {
      return '—';
    }

    final mappedName = _accountNamesById[value];
    if (mappedName != null && mappedName.isNotEmpty) {
      return mappedName;
    }

    for (final account in _accounts) {
      final matchesId = account.id == value;
      final matchesName = account.name.toLowerCase() == value.toLowerCase();
      if (matchesId || matchesName) {
        return account.name;
      }
    }

    return value;
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: DefaultTabController(
          length: 2,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: FutureBuilder<Bill>(
              future: _future,
              initialData: widget.bill,
              builder: (context, snapshot) {
                final bill = snapshot.data ?? widget.bill;
                final payments = _buildPaymentEntries(bill);
                final attachments = _collectAttachments(bill, payments);
                final isLoading =
                    snapshot.connectionState == ConnectionState.waiting;
                final hasError = snapshot.hasError;

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DialogHeader(onClose: () => Navigator.of(context).pop()),
                    const SizedBox(height: 12),
                    TabBar(
                      labelColor: Theme.of(context).colorScheme.primary,
                      tabs: const [
                        Tab(text: 'Details'),
                        Tab(text: 'Payments'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (hasError)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Failed to load details: ${snapshot.error}',
                          style: const TextStyle(color: Colors.red),
                        ),
                      ),
                    if (isLoading && snapshot.data == null)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!isLoading || snapshot.data != null)
                      Flexible(
                        fit: FlexFit.loose,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLoading)
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: Center(
                                  child: SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(),
                                  ),
                                ),
                              ),
                            Flexible(
                              fit: FlexFit.loose,
                              child: TabBarView(
                                children: [
                                  _DetailsTab(
                                    bill: bill,
                                    vendorName: widget.vendorName,
                                    creditAccountLabel: _resolveAccountName(
                                      bill.creditAccountId ??
                                          bill.creditAccount,
                                    ),
                                    debitAccountLabel: _resolveAccountName(
                                      bill.debitAccountId ?? bill.debitAccount,
                                    ),
                                    isLoadingAccounts:
                                        _isLoadingAccounts ||
                                            _isLoadingAccountNames,
                                    accountsError: _accountsError,
                                  ),
                                  _PaymentsTab(
                                    bill: bill,
                                    payments: payments,
                                    attachments: attachments,
                                    isLoading: _isLoadingPayments,
                                    error: _paymentsError,
                                    onAddPayment: () =>
                                        _openAddPaymentDialog(bill),
                                    onEditPayment: (payment) =>
                                        _openEditPaymentDialog(payment, bill),
                                    onPreviewAttachment:
                                        _handlePreviewAttachment,
                                    resolveAccountName: _resolveAccountName,
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Bill Details',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        IconButton(
          tooltip: 'Close',
          onPressed: onClose,
          icon: const Icon(Icons.close),
        ),
      ],
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.bill,
    required this.vendorName,
    required this.creditAccountLabel,
    required this.debitAccountLabel,
    required this.isLoadingAccounts,
    this.accountsError,
  });

  final Bill bill;
  final String vendorName;
  final String creditAccountLabel;
  final String debitAccountLabel;
  final bool isLoadingAccounts;
  final String? accountsError;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scrollbar(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Status',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            _StatusPill(status: bill.status, theme: theme),
            const SizedBox(height: 16),
            _DetailField(
              label: 'Vendor',
              value: vendorName.isEmpty ? '—' : vendorName,
            ),
            const SizedBox(height: 16),
            _DateRow(bill: bill),
            const SizedBox(height: 16),
            _AttachmentSection(bill: bill),
            const SizedBox(height: 16),
            _AccountRow(
              creditAccount: creditAccountLabel,
              debitAccount: debitAccountLabel,
              isLoading: isLoadingAccounts,
            ),
            if (accountsError != null) ...[
              const SizedBox(height: 8),
              Text(
                accountsError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
              ),
            ],
            const SizedBox(height: 20),
            _BillTotalsSection(
              totalAmount: bill.totalLabel,
              totalPaid: bill.totalPaidLabel,
              totalDue: bill.totalDueLabel,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _DateRow extends StatelessWidget {
  const _DateRow({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 520;
        final children = [
          Expanded(
            child: _DetailField(label: 'Bill date', value: bill.formattedDate),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _DetailField(
              label: 'Due date',
              value: bill.formattedDueDate,
            ),
          ),
        ];

        if (isWide) {
          return Row(children: children);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [children[0], const SizedBox(height: 12), children[2]],
        );
      },
    );
  }
}

class _AccountRow extends StatelessWidget {
  const _AccountRow({
    required this.creditAccount,
    required this.debitAccount,
    this.isLoading = false,
  });

  final String creditAccount;
  final String debitAccount;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Widget buildCell(String text, {TextStyle? style}) {
      final resolvedText = text.trim().isEmpty ? '—' : text.trim();
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Text(resolvedText, style: style ?? theme.textTheme.bodyMedium),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Table(
          columnWidths: const {
            0: IntrinsicColumnWidth(),
            1: FlexColumnWidth(),
          },
          border: TableBorder.all(
            color: theme.dividerColor,
            width: 1,
            borderRadius: BorderRadius.circular(8),
          ),
          defaultVerticalAlignment: TableCellVerticalAlignment.middle,
          children: [
            TableRow(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(8),
                ),
              ),
              children: [
                buildCell(
                  'Type',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                buildCell(
                  'Account',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            TableRow(
              children: [
                buildCell('Credit Account'),
                buildCell(creditAccount),
              ],
            ),
            TableRow(
              children: [
                buildCell('Debit Account'),
                buildCell(debitAccount),
              ],
            ),
          ],
        ),
        if (isLoading) ...[
          const SizedBox(height: 8),
          const Center(
            child: SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(),
            ),
          ),
        ],
      ],
    );
  }
}

class _BillTotalsSection extends StatelessWidget {
  const _BillTotalsSection({
    required this.totalAmount,
    required this.totalPaid,
    required this.totalDue,
    required this.theme,
  });

  final String totalAmount;
  final String totalPaid;
  final String totalDue;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          _BillTotalRow(
            label: 'Total Amount',
            value: totalAmount,
            theme: theme,
            emphasize: true,
          ),
          const SizedBox(height: 8),
          _BillTotalRow(label: 'Total Paid', value: totalPaid, theme: theme),
          const SizedBox(height: 8),
          _BillTotalRow(
            label: 'Total Due',
            value: totalDue,
            theme: theme,
            emphasize: true,
          ),
        ],
      ),
    );
  }
}

class _BillTotalRow extends StatelessWidget {
  const _BillTotalRow({
    required this.label,
    required this.value,
    required this.theme,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final ThemeData theme;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final labelStyle = theme.textTheme.bodyMedium;
    final valueStyle = emphasize
        ? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)
        : theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600);

    return Align(
      alignment: Alignment.centerRight,
      child: Text.rich(
        TextSpan(
          text: '$label: ',
          style: labelStyle,
          children: [TextSpan(text: value, style: valueStyle)],
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.status, required this.theme});

  final BillStatus status;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    Color background;
    Color foreground;
    switch (status.code) {
      case 2:
        background = Colors.green.shade100;
        foreground = Colors.green.shade800;
        break;
      case 1:
        background = Colors.yellow.shade100;
        foreground = Colors.yellow.shade900;
        break;
      default:
        background = Colors.red.shade100;
        foreground = Colors.red.shade800;
        break;
    }

    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(
          status.label,
          style: theme.textTheme.bodySmall?.copyWith(
            color: foreground,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _DetailField extends StatelessWidget {
  const _DetailField({
    required this.label,
    required this.value,
    this.valueStyle,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedValue = value.trim().isEmpty ? '—' : value.trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 4),
        Text(resolvedValue, style: valueStyle ?? theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({
    required this.bill,
    required this.payments,
    required this.attachments,
    required this.isLoading,
    this.error,
    required this.onAddPayment,
    required this.onEditPayment,
    required this.onPreviewAttachment,
    required this.resolveAccountName,
  });

  final Bill bill;
  final List<BillPayment> payments;
  final List<BillAttachment> attachments;
  final bool isLoading;
  final String? error;
  final VoidCallback onAddPayment;
  final void Function(BillPayment payment) onEditPayment;
  final void Function(BillAttachment attachment) onPreviewAttachment;
  final String Function(String? value) resolveAccountName;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (payments.isEmpty) {
      return Column(
        children: [
          Expanded(
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.payments_outlined, size: 40),
                  const SizedBox(height: 12),
                  if (error != null)
                    Text(
                      'Failed to load payments: $error',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.error),
                    )
                  else
                    Text(
                      isLoading
                          ? 'Loading payments...'
                          : 'No payments recorded yet.',
                      style: theme.textTheme.bodyMedium,
                    ),
                  const SizedBox(height: 16),
                  ElevatedButton.icon(
                    onPressed: onAddPayment,
                    icon: const Icon(Icons.add),
                    label: const Text('Add Payment'),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Failed to load payments: $error',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
          ),
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (isLoading)
                    const Padding(
                      padding: EdgeInsets.only(bottom: 8),
                      child: Center(
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(),
                        ),
                      ),
                    ),
                  _PaymentsTable(
                    bill: bill,
                    payments: payments,
                    attachments: attachments,
                    resolveAccountName: resolveAccountName,
                    onEditPayment: onEditPayment,
                    onPreviewAttachment: onPreviewAttachment,
                  ),
                  const SizedBox(height: 16),
                  if (attachments.isNotEmpty) ...[
                    Text(
                      'Payment attachments',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...attachments
                        .map(
                          (attachment) => Padding(
                            padding: const EdgeInsets.only(bottom: 12),
                            child: _BillAttachmentCard(
                              attachment: attachment,
                              billId: bill.id,
                            ),
                          ),
                        )
                        .toList(),
                  ],
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: onAddPayment,
            icon: const Icon(Icons.add),
            label: const Text('Add Payment'),
          ),
        ),
      ],
    );
  }
}

class _PaymentsTable extends StatelessWidget {
  const _PaymentsTable({
    required this.bill,
    required this.payments,
    required this.attachments,
    required this.resolveAccountName,
    required this.onEditPayment,
    required this.onPreviewAttachment,
  });

  final Bill bill;
  final List<BillPayment> payments;
  final List<BillAttachment> attachments;
  final String Function(String? value) resolveAccountName;
  final void Function(BillPayment payment) onEditPayment;
  final void Function(BillAttachment attachment) onPreviewAttachment;

  BillAttachment? _findAttachment(BillPayment payment) {
    if (payment.attachment != null) {
      return payment.attachment;
    }
    for (final attachment in attachments) {
      if (attachment.paymentId == payment.id || attachment.id == payment.id) {
        return attachment;
      }
    }
    return null;
  }

  String _formatAmount(double? amount) {
    if (amount == null) {
      return '-';
    }
    final symbol = bill.currencySymbol;
    final formatted = amount.toStringAsFixed(2);
    if (symbol.isNotEmpty && symbol.toLowerCase() != '0') {
      return '$symbol $formatted';
    }
    return formatted;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Scrollbar(
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 720),
          child: Table(
            columnWidths: const {
              0: FlexColumnWidth(2),
              1: FlexColumnWidth(3),
              2: FlexColumnWidth(2),
              3: IntrinsicColumnWidth(),
            },
            border: TableBorder.all(color: theme.dividerColor),
            defaultVerticalAlignment: TableCellVerticalAlignment.middle,
            children: [
              TableRow(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
                ),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Text('Date', style: headerStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Text('Payment Account', style: headerStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Text('Amount', style: headerStyle),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Text(
                      'Options',
                      style: headerStyle,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
              ...payments.map((payment) {
                final attachment = _findAttachment(payment);
                final dateLabel = payment.date != null
                    ? DateFormat.yMMMd().format(payment.date!)
                    : '—';
                final paymentAccountLabel = resolveAccountName(
                  payment.paymentAccountId ?? payment.paymentAccount,
                );
                return TableRow(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text(dateLabel),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text(
                        paymentAccountLabel.trim().isNotEmpty
                            ? paymentAccountLabel
                            : '—',
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                      child: Text(
                        _formatAmount(payment.amount),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'View attachment',
                              icon: const Icon(Icons.visibility_outlined),
                              onPressed: attachment == null
                                  ? null
                                  : () => onPreviewAttachment(attachment),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Edit payment',
                              icon: const Icon(Icons.edit_outlined),
                              onPressed: () => onEditPayment(payment),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              tooltip: 'Delete payment',
                              icon: const Icon(Icons.delete_outline),
                              color: theme.colorScheme.error,
                              onPressed: () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content:
                                        Text('Delete payment coming soon.'),
                                  ),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttachmentSection extends StatelessWidget {
  const _AttachmentSection({required this.bill});

  final Bill bill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (bill.attachments.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Attachment',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.attach_file),
            label: const Text('Add Attachment'),
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Attachment',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 12),
        Column(
          children: bill.attachments
              .map(
                (attachment) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _BillAttachmentCard(
                    attachment: attachment,
                    billId: bill.id,
                  ),
                ),
              )
              .toList(),
        ),
      ],
    );
  }
}

class _BillAttachmentCard extends StatelessWidget {
  const _BillAttachmentCard({required this.attachment, required this.billId});

  final BillAttachment attachment;
  final String billId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;

    final normalizedDownloadUrl = attachment.downloadUrl != null
        ? _normalizeAttachmentDownloadUrl(attachment.downloadUrl!)
        : null;

    final previewType = _resolvePreviewType(
      attachment.fileName,
      normalizedDownloadUrl,
    );

    final children = <Widget>[
      Row(
        children: [
          Icon(Icons.attach_file, color: labelColor),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              attachment.fileName,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 12),
    ];

    if (attachment.uploadedAt != null) {
      children.add(
        _LabelValueRow(
          label: 'Uploaded on',
          value: DateFormat.yMMMd().format(attachment.uploadedAt!),
        ),
      );
    }

    if (attachment.uploadedBy != null &&
        attachment.uploadedBy!.trim().isNotEmpty) {
      children.add(
        _LabelValueRow(
          label: 'Uploaded by',
          value: attachment.uploadedBy!.trim(),
        ),
      );
    }

    if (attachment.sizeLabel != null &&
        attachment.sizeLabel!.trim().isNotEmpty) {
      children.add(
        _LabelValueRow(label: 'Size', value: attachment.sizeLabel!.trim()),
      );
    }

    if (attachment.description != null &&
        attachment.description!.trim().isNotEmpty) {
      children.addAll([
        const SizedBox(height: 12),
        Text(
          'Description',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        Text(attachment.description!.trim(), style: theme.textTheme.bodyMedium),
      ]);
    }

    if (normalizedDownloadUrl != null) {
      children.addAll([
        const SizedBox(height: 12),
        Text(
          'Download URL',
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
            color: labelColor,
          ),
        ),
        const SizedBox(height: 4),
        SelectableText(
          normalizedDownloadUrl,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
      ]);
    }

    if (previewType != null && normalizedDownloadUrl != null) {
      children.addAll([
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerRight,
          child: FilledButton.icon(
            icon: const Icon(Icons.visibility),
            label: const Text('Preview'),
            onPressed: () {
              _showAttachmentPreview(
                context: context,
                fileName: attachment.fileName,
                downloadUrl: normalizedDownloadUrl,
                previewType: previewType,
              );
            },
          ),
        ),
      ]);
    }

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: children,
      ),
    );
  }
}

class _EditPaymentDialog extends StatefulWidget {
  const _EditPaymentDialog({
    required this.payment,
    required this.currencySymbol,
  });

  final BillPayment payment;
  final String currencySymbol;

  @override
  State<_EditPaymentDialog> createState() => _EditPaymentDialogState();
}

class _EditPaymentDialogState extends State<_EditPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amountController = TextEditingController();
  final _accountsService = AccountsService();

  DateTime _selectedDate = DateTime.now();
  PlatformFile? _selectedFile;
  bool _removeExistingAttachment = false;
  bool _isLoadingAccounts = false;
  String? _loadError;
  List<Account> _accounts = const [];
  Account? _selectedPaymentAccount;
  Account? _selectedDepositAccount;

  @override
  void initState() {
    super.initState();
    _selectedDate = widget.payment.date ?? DateTime.now();
    _amountController.text = widget.payment.amount != null
        ? widget.payment.amount!.toStringAsFixed(2)
        : '';
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAccounts());
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadAccounts() async {
    setState(() {
      _isLoadingAccounts = true;
      _loadError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _isLoadingAccounts = false;
        _loadError = 'You are not logged in.';
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final accounts = await _accountsService.fetchAccounts(
        page: 1,
        perPage: 200,
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _accounts = accounts.accounts;
        _loadError = null;
      });

      _syncSelectedAccounts(accounts.accounts);
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingAccounts = false);
      }
    }
  }

  void _syncSelectedAccounts(List<Account> accounts) {
    Account? match(String? idOrName) {
      if (idOrName == null || idOrName.trim().isEmpty) {
        return null;
      }
      final trimmed = idOrName.trim();
      try {
        return accounts.firstWhere(
          (account) =>
              account.id == trimmed || account.name.toLowerCase() == trimmed.toLowerCase(),
        );
      } catch (_) {
        return null;
      }
    }

    final paymentAccount =
        match(widget.payment.paymentAccountId ?? widget.payment.paymentAccount);
    final depositAccount = match(widget.payment.depositAccountId);

    setState(() {
      _selectedPaymentAccount =
          paymentAccount != null && paymentAccount.id.isNotEmpty ? paymentAccount : null;
      _selectedDepositAccount =
          depositAccount != null && depositAccount.id.isNotEmpty ? depositAccount : null;
    });
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
    final authtokenHeader = autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;
    return {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };
  }

  void _setSelectedFile(PlatformFile? file) {
    setState(() {
      _selectedFile = file;
      _removeExistingAttachment = false;
    });
  }

  void _onFilesSelected(List<PlatformFile> files) {
    if (files.isEmpty) {
      return;
    }

    final validFile = files.lastWhere(
      (file) => isAllowedAttachmentExtension(attachmentExtension(file.name)),
      orElse: () => files.last,
    );

    _setSelectedFile(validFile);
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: false,
      withData: true,
      withReadStream: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(),
    );

    if (result != null && result.files.isNotEmpty) {
      _onFilesSelected(result.files);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (selected != null) {
      setState(() => _selectedDate = selected);
    }
  }

  void _clearSelectedFile() {
    setState(() {
      _selectedFile = null;
      _removeExistingAttachment = false;
    });
  }

  void _handleRemoveAttachment() {
    setState(() {
      _selectedFile = null;
      _removeExistingAttachment = true;
    });
  }

  String _formatFileSize(int sizeInBytes) {
    const kilo = 1024;
    const mega = kilo * 1024;
    if (sizeInBytes >= mega) {
      return '${(sizeInBytes / mega).toStringAsFixed(2)} MB';
    }
    if (sizeInBytes >= kilo) {
      return '${(sizeInBytes / kilo).toStringAsFixed(2)} KB';
    }
    return '$sizeInBytes B';
  }

  BillAttachment? _buildAttachment() {
    if (_selectedFile != null) {
      return BillAttachment(
        fileName: _selectedFile!.name,
        description: _selectedFile!.name,
        downloadUrl: _selectedFile!.path,
        uploadedAt: _selectedDate,
        sizeLabel: _formatFileSize(_selectedFile!.size),
        id: null,
        paymentId: widget.payment.id,
        paymentDate: _selectedDate,
        amount: double.tryParse(_amountController.text.trim()) ?? widget.payment.amount,
      );
    }

    if (_removeExistingAttachment) {
      return null;
    }

    return widget.payment.attachment;
  }

  void _handleSubmit() {
    if (_formKey.currentState?.validate() != true) {
      return;
    }

    final amountText = _amountController.text.trim();
    final parsedAmount = amountText.isEmpty
        ? widget.payment.amount
        : double.tryParse(amountText);

    final updatedPayment = widget.payment.copyWith(
      date: _selectedDate,
      amount: parsedAmount,
      paymentAccount: _selectedPaymentAccount?.name ?? widget.payment.paymentAccount,
      paymentAccountId: _selectedPaymentAccount?.id ?? widget.payment.paymentAccountId,
      depositAccountId: _selectedDepositAccount?.id ?? widget.payment.depositAccountId,
      attachment: _buildAttachment(),
    );

    Navigator.of(context).pop(updatedPayment);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Edit Payment',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_isLoadingAccounts)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AttachmentPicker(
                      label: 'Attachment',
                      description:
                          'Drag and drop files or tap to browse for payment attachments.',
                      files:
                          _selectedFile != null ? [_selectedFile!] : const [],
                      onPick: _pickAttachment,
                      onFilesSelected: _onFilesSelected,
                      onFileRemoved: (_) => _clearSelectedFile(),
                    ),
                    if (_selectedFile == null &&
                        !_removeExistingAttachment &&
                        widget.payment.attachment != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Current: ${widget.payment.attachment!.fileName}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ),
                            TextButton(
                              onPressed: _handleRemoveAttachment,
                              child: const Text('Remove current attachment'),
                            ),
                          ],
                        ),
                      ),
                    const SizedBox(height: 16),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Date Paid',
                        border: OutlineInputBorder(),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              DateFormat.yMMMd().format(_selectedDate),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.calendar_today_outlined),
                            onPressed: _pickDate,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedPaymentAccount?.id,
                            decoration: const InputDecoration(
                              labelText: 'Payment Account',
                              border: OutlineInputBorder(),
                            ),
                            items: _accounts
                                .map(
                                  (account) => DropdownMenuItem(
                                    value: account.id,
                                    child: Text(account.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentAccount = value == null
                                    ? null
                                    : _accounts.firstWhere(
                                        (account) => account.id == value,
                                      );
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedDepositAccount?.id,
                            decoration: const InputDecoration(
                              labelText: 'Deposit Account',
                              border: OutlineInputBorder(),
                            ),
                            items: _accounts
                                .map(
                                  (account) => DropdownMenuItem(
                                    value: account.id,
                                    child: Text(account.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedDepositAccount = value == null
                                    ? null
                                    : _accounts.firstWhere(
                                        (account) => account.id == value,
                                      );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            'Amount (${widget.currencySymbol.isEmpty ? 'value' : widget.currencySymbol})',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return null;
                        }
                        if (double.tryParse(value.trim()) == null) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _handleSubmit,
                    child: const Text('Save Changes'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AddPaymentDialog extends StatefulWidget {
  const _AddPaymentDialog({required this.currencySymbol});

  final String currencySymbol;

  @override
  State<_AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends State<_AddPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  final _paymentIdController = TextEditingController();
  final _amountController = TextEditingController();
  final _paymentModesService = PaymentModesService();
  final _accountsService = AccountsService();

  DateTime _selectedDate = DateTime.now();
  PaymentMode? _selectedPaymentMode;
  Account? _selectedPaymentAccount;
  Account? _selectedDepositAccount;
  PlatformFile? _selectedFile;
  bool _isSubmitting = false;
  bool _isLoadingOptions = false;
  String? _loadError;
  List<PaymentMode> _paymentModes = const [];
  List<Account> _accounts = const [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadOptions());
  }

  @override
  void dispose() {
    _paymentIdController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _isLoadingOptions = true;
      _loadError = null;
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _isLoadingOptions = false;
        _loadError = 'You are not logged in.';
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      final paymentModes = await _paymentModesService.fetchPaymentModes(
        headers: headers,
      );
      final accounts = await _accountsService.fetchAccounts(
        page: 1,
        perPage: 200,
        headers: headers,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _paymentModes = paymentModes;
        _accounts = accounts.accounts;
        _loadError = null;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loadError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingOptions = false);
      }
    }
  }

  Map<String, String> _buildAuthHeaders(AppState appState, String token) {
    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken = token
        .replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '')
        .trim();
    final normalizedAuth = sanitizedToken.isNotEmpty
        ? 'Bearer $sanitizedToken'
        : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\s+', caseSensitive: false), '')
        .trim();
    final authtokenHeader = autoTokenValue.isNotEmpty
        ? autoTokenValue
        : sanitizedToken;
    return {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };
  }

  Future<void> _pickAttachment() async {
    final result = await FilePicker.platform.pickFiles(withReadStream: false);
    if (result != null && result.files.isNotEmpty) {
      setState(() => _selectedFile = result.files.first);
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final selected = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );

    if (selected != null) {
      setState(() => _selectedDate = selected);
    }
  }

  String _formatFileSize(int sizeInBytes) {
    if (sizeInBytes <= 0) {
      return '0 B';
    }
    const units = ['B', 'KB', 'MB', 'GB'];
    var size = sizeInBytes.toDouble();
    var unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  String _attachmentDescription() {
    final paymentMode = _selectedPaymentMode?.name ?? '-';
    final paymentAccount = _selectedPaymentAccount?.name ?? '-';
    final depositTo = _selectedDepositAccount?.name ?? '-';
    return 'Payment mode: $paymentMode\nPayment account: $paymentAccount\nDeposit to: $depositTo';
  }

  void _handleSubmit() {
    final form = _formKey.currentState;
    if (form == null || !form.validate()) {
      return;
    }

    setState(() => _isSubmitting = true);

    final parsedAmount = double.tryParse(_amountController.text.trim());
    final paymentId = _paymentIdController.text.trim().isEmpty
        ? 'PAY-${DateTime.now().millisecondsSinceEpoch}'
        : _paymentIdController.text.trim();

    final attachment = _selectedFile == null
        ? null
        : BillAttachment(
            fileName: _selectedFile!.name,
            description: _attachmentDescription(),
            downloadUrl: _selectedFile!.path,
            uploadedAt: _selectedDate,
            sizeLabel: _formatFileSize(_selectedFile!.size),
            id: null,
            paymentId: paymentId,
            paymentDate: _selectedDate,
            amount: parsedAmount,
          );

    final payment = BillPayment(
      id: paymentId,
      date: _selectedDate,
      amount: parsedAmount,
      attachment: attachment,
    );

    Navigator.of(context).pop(payment);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Add Payment',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_loadError != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    _loadError!,
                    style: const TextStyle(color: Colors.red),
                  ),
                ),
              if (_isLoadingOptions)
                const Padding(
                  padding: EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(),
                    ),
                  ),
                )
              else
                const SizedBox(height: 12),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFormField(
                      controller: _paymentIdController,
                      decoration: const InputDecoration(
                        labelText: 'Payment ID',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _amountController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText:
                            'Amount (${widget.currencySymbol.isEmpty ? 'value' : widget.currencySymbol})',
                        border: const OutlineInputBorder(),
                      ),
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Enter an amount';
                        }
                        if (double.tryParse(value.trim()) == null) {
                          return 'Enter a valid number';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      value: _selectedPaymentMode?.id,
                      decoration: const InputDecoration(
                        labelText: 'Payment Mode',
                        border: OutlineInputBorder(),
                      ),
                      items: _paymentModes
                          .map(
                            (mode) => DropdownMenuItem(
                              value: mode.id,
                              child: Text(mode.name),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        setState(() {
                          _selectedPaymentMode = value == null
                              ? null
                              : _paymentModes.firstWhere(
                                  (mode) => mode.id == value,
                                );
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: InputDecorator(
                            decoration: const InputDecoration(
                              labelText: 'Payment Date',
                              border: OutlineInputBorder(),
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    DateFormat.yMMMd().format(_selectedDate),
                                  ),
                                ),
                                IconButton(
                                  icon: const Icon(
                                    Icons.calendar_today_outlined,
                                  ),
                                  onPressed: _pickDate,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedPaymentAccount?.id,
                            decoration: const InputDecoration(
                              labelText: 'Payment Account',
                              border: OutlineInputBorder(),
                            ),
                            items: _accounts
                                .map(
                                  (account) => DropdownMenuItem(
                                    value: account.id,
                                    child: Text(account.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedPaymentAccount = value == null
                                    ? null
                                    : _accounts.firstWhere(
                                        (account) => account.id == value,
                                      );
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: DropdownButtonFormField<String>(
                            value: _selectedDepositAccount?.id,
                            decoration: const InputDecoration(
                              labelText: 'Deposit To',
                              border: OutlineInputBorder(),
                            ),
                            items: _accounts
                                .map(
                                  (account) => DropdownMenuItem(
                                    value: account.id,
                                    child: Text(account.name),
                                  ),
                                )
                                .toList(),
                            onChanged: (value) {
                              setState(() {
                                _selectedDepositAccount = value == null
                                    ? null
                                    : _accounts.firstWhere(
                                        (account) => account.id == value,
                                      );
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pickAttachment,
                      icon: const Icon(Icons.attach_file),
                      label: Text(
                        _selectedFile == null
                            ? 'Upload attachment'
                            : 'Selected: ${_selectedFile!.name}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 12),
                  ElevatedButton(
                    onPressed: _isSubmitting ? null : _handleSubmit,
                    child: const Text('Save Payment'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LabelValueRow extends StatelessWidget {
  const _LabelValueRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final labelStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w600,
      color: labelColor,
    );

    final displayValue = value.trim().isEmpty ? '—' : value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: labelStyle)),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayValue,
              style: theme.textTheme.bodyMedium,
              softWrap: true,
            ),
          ),
        ],
      ),
    );
  }
}

String _normalizeAttachmentDownloadUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  if (trimmed.startsWith('//')) {
    return 'https:$trimmed';
  }

  final uri = Uri.tryParse(trimmed);
  if (uri == null) {
    return trimmed;
  }

  if (uri.hasScheme) {
    return uri.toString();
  }

  final base = Uri.base;
  final canUseBase =
      base.hasScheme && (base.scheme == 'http' || base.scheme == 'https');
  if (canUseBase) {
    return base.resolveUri(uri).toString();
  }

  return uri.toString();
}

enum _AttachmentPreviewType { image, pdf }

_AttachmentPreviewType? _resolvePreviewType(
  String fileName,
  String? downloadUrl,
) {
  if (_matchesExtension(fileName, _imageExtensions) ||
      _matchesExtension(downloadUrl, _imageExtensions)) {
    return _AttachmentPreviewType.image;
  }

  if (_matchesExtension(fileName, _pdfExtensions) ||
      _matchesExtension(downloadUrl, _pdfExtensions)) {
    return _AttachmentPreviewType.pdf;
  }

  return null;
}

const _imageExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.bmp',
  '.webp',
  '.heic',
};

const _pdfExtensions = <String>{'.pdf'};

bool _matchesExtension(String? value, Set<String> extensions) {
  if (value == null || value.trim().isEmpty) {
    return false;
  }

  bool match(String candidate) {
    final lower = candidate.toLowerCase();
    for (final ext in extensions) {
      final normalizedExt = ext.startsWith('.') ? ext : '.$ext';
      if (lower.endsWith(normalizedExt)) {
        return true;
      }
    }
    return false;
  }

  final trimmed = value.trim();
  if (match(trimmed)) {
    return true;
  }

  final parsed = Uri.tryParse(trimmed);
  if (parsed != null && match(parsed.path)) {
    return true;
  }

  return false;
}

void _showAttachmentPreview({
  required BuildContext context,
  required String fileName,
  required String downloadUrl,
  required _AttachmentPreviewType previewType,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => _AttachmentPreviewDialog(
      fileName: fileName,
      downloadUrl: downloadUrl,
      previewType: previewType,
    ),
  );
}

class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({
    required this.fileName,
    required this.downloadUrl,
    required this.previewType,
  });

  final String fileName;
  final String downloadUrl;
  final _AttachmentPreviewType previewType;

  @override
  Widget build(BuildContext context) {
    final title = '$fileName preview';
    final theme = Theme.of(context);
    Widget content;

    switch (previewType) {
      case _AttachmentPreviewType.image:
        content = _ImagePreview(downloadUrl: downloadUrl);
        break;
      case _AttachmentPreviewType.pdf:
        content = _PdfPreview(downloadUrl: downloadUrl);
        break;
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 720,
        height: 560,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      title,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.downloadUrl});

  final String downloadUrl;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      child: Center(
        child: Image.network(
          downloadUrl,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
            if (loadingProgress == null) {
              return child;
            }
            return const Center(child: CircularProgressIndicator());
          },
          errorBuilder: (context, error, stackTrace) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text('Unable to load image preview.'),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _PdfPreview extends StatelessWidget {
  const _PdfPreview({required this.downloadUrl});

  final String downloadUrl;

  @override
  Widget build(BuildContext context) {
    return buildAttachmentPdfPreview(downloadUrl);
  }
}
