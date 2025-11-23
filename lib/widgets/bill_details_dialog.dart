import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:kokonuts_bookkeeping/app/app_state.dart';
import 'package:kokonuts_bookkeeping/app/app_state_scope.dart';
import 'attachment_pdf_preview.dart';

import '../services/accounts_service.dart';
import '../services/bills_service.dart';
import '../services/payment_modes_service.dart';
import 'currency_input_formatter.dart';

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
  bool _isLoadingAccountNames = false;
  Map<String, String> _accountNamesById = const {};

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _loadDetails();
      _loadAccountNames();
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
      _accountsError = null;
    });

    try {
      final bill = await _billsService.getBill(id: widget.bill.id, headers: headers);

      if (!mounted) {
        return bill;
      }

      try {
        final accounts = await _accountsService.fetchAccounts(
          page: 1,
          perPage: 200,
          headers: headers,
        );

        if (mounted) {
          setState(() {
            _accounts = accounts.accounts;
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

      return bill;
    } catch (error) {
      if (mounted) {
        setState(() => _isLoadingAccounts = false);
      }
      rethrow;
    }
  }

  Future<void> _loadAccountNames() async {
    setState(() => _isLoadingAccountNames = true);

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() => _isLoadingAccountNames = false);
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      const perPage = 200;
      var page = 1;
      var hasMore = true;
      final namesById = <String, String>{};

      while (hasMore && mounted) {
        final result = await _accountsService.fetchAccounts(
          page: page,
          perPage: perPage,
          headers: headers,
        );

        namesById.addAll(result.namesById);
        hasMore = result.hasMore;
        page += 1;
      }

      if (!mounted) {
        return;
      }

      setState(() => _accountNamesById = namesById);
    } catch (_) {
      // Account names are optional context for the details view; ignore failures.
    } finally {
      if (mounted) {
        setState(() => _isLoadingAccountNames = false);
      }
    }
  }

  Future<void> _loadAccountNames() async {
    if (_isLoadingAccountNames) {
      return;
    }

    setState(() => _isLoadingAccountNames = true);

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      return;
    }

    if (token == null || token.trim().isEmpty) {
      setState(() {
        _isLoadingAccountNames = false;
        _accountNamesById = const {};
      });
      return;
    }

    final headers = _buildAuthHeaders(appState, token);

    try {
      const perPage = 200;
      var page = 1;
      var hasMore = true;
      final namesById = <String, String>{};

      while (hasMore && mounted) {
        final result = await _accountsService.fetchAccounts(
          page: page,
          perPage: perPage,
          headers: headers,
        );

        namesById.addAll(result.namesById);
        hasMore = result.hasMore;
        page += 1;
      }

      if (!mounted) {
        return;
      }

      setState(() => _accountNamesById = namesById);
    } catch (_) {
      // Account names are optional context for the details view; ignore failures.
      if (mounted) {
        setState(() => _accountNamesById = const {});
      }
    } finally {
      if (mounted) {
        setState(() => _isLoadingAccountNames = false);
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
    return {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };
  }

  final _pendingPayments = <BillPayment>[];

  List<BillPayment> _buildPaymentEntries(Bill bill) {
    final entries = <BillPayment>[];

    if (bill.payments.isNotEmpty) {
      entries.addAll(bill.payments);
    } else if (bill.attachments.isNotEmpty) {
      entries.addAll(
        bill.attachments.map(
          (attachment) => BillPayment(
            id: attachment.paymentId ?? attachment.id ?? attachment.fileName,
            date: attachment.paymentDate ?? attachment.uploadedAt,
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
      final key = attachment.id ?? attachment.downloadUrl ?? attachment.fileName;
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

  Future<void> _openAddPaymentDialog(Bill bill) async {
    final result = await showDialog<BillPayment>(
      context: context,
      barrierDismissible: false,
      builder: (context) => _AddPaymentDialog(currencySymbol: bill.currencySymbol),
    );

    if (result != null) {
      setState(() => _pendingPayments.add(result));
    }
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
        const SnackBar(content: Text('No preview available for this attachment.')),
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
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 820),
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
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      ),
                    if (!isLoading || snapshot.data != null)
                      Expanded(
                        child: Column(
                          children: [
                            if (isLoading) const LinearProgressIndicator(),
                            const SizedBox(height: 12),
                            Expanded(
                              child: TabBarView(
                                children: [
                                  _DetailsTab(
                                    bill: bill,
                                    vendorName: widget.vendorName,
                                    accountNamesById: _accountNamesById,
                                    isLoadingAccountNames: _isLoadingAccountNames,
                                  ),
                                  _PaymentsTab(
                                    bill: bill,
                                    payments: payments,
                                    attachments: attachments,
                                    onAddPayment: () => _openAddPaymentDialog(bill),
                                    onPreviewAttachment: _handlePreviewAttachment,
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
    required this.accountNamesById,
    required this.isLoadingAccountNames,
  });

  final Bill bill;
  final String vendorName;
  final Map<String, String> accountNamesById;
  final bool isLoadingAccountNames;

  String _resolveAccountName(String? value) {
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) {
      return '—';
    }

    final mapped = accountNamesById[trimmed];
    if (mapped != null && mapped.trim().isNotEmpty) {
      return mapped;
    }

    return trimmed;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final creditAccount = _resolveAccountName(bill.creditAccount);
    final debitAccount = _resolveAccountName(bill.debitAccount);
    final isLoading = isLoadingAccountNames &&
        (bill.creditAccount?.isNotEmpty == true ||
            bill.debitAccount?.isNotEmpty == true);

    return Scrollbar(
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _StatusPill(status: bill.status, theme: theme),
            const SizedBox(height: 16),
            _DetailField(
              label: 'Vendor',
              value: vendorName.isEmpty ? '—' : vendorName,
            ),
            const SizedBox(height: 16),
            _DateRow(bill: bill),
            const SizedBox(height: 16),
            _AccountRow(creditAccount: creditAccount, debitAccount: debitAccount),
            if (isLoading) ...[
              const SizedBox(height: 8),
              const _AccountsLoadingIndicator(),
            ],
            const SizedBox(height: 24),
            Align(
              alignment: Alignment.centerRight,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 640),
                child: _SummaryRow(
                  totalAmount: bill.totalLabel,
                  totalPaid: bill.totalPaidLabel,
                  totalDue: bill.totalDueLabel,
                ),
              ),
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
            child: _DetailField(label: 'Due date', value: bill.formattedDueDate),
          ),
        ];

        if (isWide) {
          return Row(children: children);
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            children[0],
            const SizedBox(height: 12),
            children[2],
          ],
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isWide = constraints.maxWidth > 520;
            final children = [
              Expanded(
                child: _DetailField(
                  label: 'Credit Account',
                  value: creditAccount,
                  ellipsize: true,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _DetailField(
                  label: 'Debit Account',
                  value: debitAccount,
                  ellipsize: true,
                ),
              ),
            ];

            if (isWide) {
              return Row(children: children);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                children[0],
                const SizedBox(height: 12),
                children[2],
              ],
            );
          },
        ),
        if (isLoading) ...[
          const SizedBox(height: 8),
          LinearProgressIndicator(
            minHeight: 4,
            color: Theme.of(context).colorScheme.primary,
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
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _BillTotalRow(
            label: 'Total Amount',
            value: totalAmount,
            theme: theme,
            emphasize: true,
          ),
          const SizedBox(height: 8),
          _BillTotalRow(
            label: 'Total Paid',
            value: totalPaid,
            theme: theme,
          ),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        final cards = [
          buildCard(
            'Total Amount',
            totalAmount,
            valueColor: theme.colorScheme.error,
          ),
          const SizedBox(width: 12),
          buildCard('Total Paid', totalPaid, valueColor: Colors.green.shade700),
          const SizedBox(width: 12),
          buildCard('Total Due', totalDue, valueColor: theme.colorScheme.error),
        ];

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards[0],
              const SizedBox(height: 12),
              cards[2],
              const SizedBox(height: 12),
              cards[4],
            ],
          );
        }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 520;
        final cards = [
          buildCard(
            'Total Amount',
            totalAmount,
            valueColor: theme.colorScheme.error,
          ),
          const SizedBox(width: 12),
          buildCard('Total Paid', totalPaid, valueColor: Colors.green.shade700),
          const SizedBox(width: 12),
          buildCard('Total Due', totalDue, valueColor: theme.colorScheme.error),
        ];

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              cards[0],
              const SizedBox(height: 12),
              cards[2],
              const SizedBox(height: 12),
              cards[4],
            ],
          );
        }

        return Row(children: cards);
      },
    );
  }
}

class _AccountsLoadingIndicator extends StatelessWidget {
  const _AccountsLoadingIndicator();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        SizedBox(
          height: 16,
          width: 16,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation(theme.colorScheme.primary),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'Loading account names…',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
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
    this.ellipsize = false,
  });

  final String label;
  final String value;
  final TextStyle? valueStyle;
  final bool ellipsize;

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
        Text(
          resolvedValue,
          style: valueStyle ?? theme.textTheme.bodyMedium,
          maxLines: ellipsize ? 1 : null,
          overflow: ellipsize ? TextOverflow.ellipsis : null,
        ),
      ],
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({
    required this.bill,
    required this.payments,
    required this.attachments,
    required this.onAddPayment,
    required this.onPreviewAttachment,
  });

  final Bill bill;
  final List<BillPayment> payments;
  final List<BillAttachment> attachments;
  final VoidCallback onAddPayment;
  final void Function(BillAttachment attachment) onPreviewAttachment;

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
                  Text(
                    'No payments recorded yet.',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
          ),
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _PaymentsTable(
                    bill: bill,
                    payments: payments,
                    attachments: attachments,
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
    required this.onPreviewAttachment,
  });

  final Bill bill;
  final List<BillPayment> payments;
  final List<BillAttachment> attachments;
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

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor),
      ),
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(2),
          2: FlexColumnWidth(2),
          3: IntrinsicColumnWidth(),
        },
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        children: [
          TableRow(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Payment ID', style: headerStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Date', style: headerStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Amount', style: headerStyle),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Text('Actions', style: headerStyle, textAlign: TextAlign.end),
              ),
            ],
          ),
          ...payments.map((payment) {
            final attachment = _findAttachment(payment);
            final dateLabel = payment.date != null
                ? DateFormat.yMMMd().format(payment.date!)
                : '—';
            return TableRow(
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(payment.id.isEmpty ? '—' : payment.id),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(dateLabel),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    _formatAmount(payment.amount),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Wrap(
                      spacing: 8,
                      children: [
                        IconButton(
                          tooltip: 'View attachment',
                          icon: const Icon(Icons.visibility_outlined),
                          onPressed: attachment == null
                              ? null
                              : () => onPreviewAttachment(attachment),
                        ),
                        IconButton(
                          tooltip: 'Edit payment',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Edit payment coming soon.')),
                            );
                          },
                        ),
                        IconButton(
                          tooltip: 'Delete payment',
                          icon: const Icon(Icons.delete_outline),
                          color: theme.colorScheme.error,
                          onPressed: () {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Delete payment coming soon.')),
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
          Text('No attachment available', style: theme.textTheme.bodyMedium),
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
    _amountController.text =
        CurrencyInputFormatter.normalizeExistingValue(_amountController.text);
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
      final paymentModes =
          await _paymentModesService.fetchPaymentModes(headers: headers);
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
    final authtokenHeader =
        autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;
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
                const LinearProgressIndicator(),
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
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      inputFormatters: const [CurrencyInputFormatter()],
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
                              : _paymentModes
                                  .firstWhere((mode) => mode.id == value);
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
                                  child: Text(DateFormat.yMMMd().format(_selectedDate)),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.calendar_today_outlined),
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
