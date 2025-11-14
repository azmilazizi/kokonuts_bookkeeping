import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/purchase_order_detail_service.dart';

class PurchaseOrderDetailsDialog extends StatefulWidget {
  const PurchaseOrderDetailsDialog({super.key, required this.orderId});

  final String orderId;

  @override
  State<PurchaseOrderDetailsDialog> createState() =>
      _PurchaseOrderDetailsDialogState();
}

class _PurchaseOrderDetailsDialogState
    extends State<PurchaseOrderDetailsDialog> {
  final _service = PurchaseOrderDetailService();
  final _itemsScrollController = ScrollController();

  late Future<PurchaseOrderDetail> _future;
  bool _initialized = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_initialized) {
      _future = _loadDetails();
      _initialized = true;
    }
  }

  @override
  void dispose() {
    _itemsScrollController.dispose();
    super.dispose();
  }

  Future<PurchaseOrderDetail> _loadDetails() async {
    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();

    if (!mounted) {
      throw const PurchaseOrderDetailException('Dialog no longer mounted');
    }

    if (token == null || token.trim().isEmpty) {
      throw const PurchaseOrderDetailException('You are not logged in.');
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

    return _service.fetchPurchaseOrder(
      id: widget.orderId,
      headers: {
        'Accept': 'application/json',
        'authtoken': authtokenHeader,
        'Authorization': normalizedAuth,
      },
    );
  }

  void _retry() {
    setState(() {
      _future = _loadDetails();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: SizedBox(
        width: 840,
        height: 620,
        child: FutureBuilder<PurchaseOrderDetail>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator());
            }

            if (snapshot.hasError) {
              return _ErrorView(
                error: snapshot.error,
                onRetry: _retry,
              );
            }

            if (!snapshot.hasData) {
              return const _ErrorView(
                error: 'Unable to load purchase order details.',
              );
            }

            final detail = snapshot.data!;

            return DefaultTabController(
              length: 3,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _DialogHeader(
                      orderNumber: detail.number,
                      onClose: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(height: 12),
                    _DialogTabs(),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _DetailsTab(
                            detail: detail,
                            itemsController: _itemsScrollController,
                          ),
                          _PaymentsTab(detail: detail),
                          _AttachmentsTab(detail: detail),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Close'),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _DialogHeader extends StatelessWidget {
  const _DialogHeader({
    required this.orderNumber,
    required this.onClose,
  });

  final String orderNumber;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Expanded(
          child: Text(
            'Purchase Order $orderNumber',
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

class _DialogTabs extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return TabBar(
      labelStyle: labelStyle,
      labelColor: theme.colorScheme.primary,
      unselectedLabelColor: theme.colorScheme.onSurfaceVariant,
      indicatorColor: theme.colorScheme.primary,
      tabs: const [
        Tab(text: 'Details'),
        Tab(text: 'Payments'),
        Tab(text: 'Attachments'),
      ],
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.detail});

  final PurchaseOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fields = <_SummaryField>[
      _SummaryField.text('Order name', detail.name),
      _SummaryField.text('Vendor', detail.vendorName),
      _SummaryField.pill(
        label: 'Status',
        pillStyle: _buildStatusPillStyle(theme, detail),
      ),
      _SummaryField.pill(
        label: 'Approval status',
        pillStyle: _buildApprovalPillStyle(theme, detail),
      ),
      _SummaryField.text('Order date', detail.orderDateLabel),
      _SummaryField.text('Delivery date', detail.deliveryDateLabel),
    ];

    if (detail.referenceLabel != null) {
      fields.add(_SummaryField.text('Reference', detail.referenceLabel!));
    }

    return Wrap(
      spacing: 24,
      runSpacing: 16,
      children: fields
          .map((field) => _SummaryTile(field: field, theme: theme))
          .toList(),
    );
  }
}

_PillStyle _buildStatusPillStyle(ThemeData theme, PurchaseOrderDetail detail) {
  final label = _resolvePillLabel(
    explicit: detail.status,
    id: detail.statusId,
    lookup: purchaseOrderStatusLabels,
  );

  final id = detail.statusId ?? _findIdForLabel(label, purchaseOrderStatusLabels);
  final colorScheme = theme.colorScheme;

  Color background;
  Color foreground;

  switch (id) {
    case 2:
      background = colorScheme.primaryContainer;
      foreground = colorScheme.onPrimaryContainer;
      break;
    case 3:
      background = colorScheme.secondaryContainer;
      foreground = colorScheme.onSecondaryContainer;
      break;
    case 4:
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
      break;
    case 1:
    default:
      background = colorScheme.surfaceVariant;
      foreground = colorScheme.onSurfaceVariant;
      break;
  }

  return _PillStyle(
    label: label,
    backgroundColor: background,
    foregroundColor: foreground,
  );
}

_PillStyle _buildApprovalPillStyle(
  ThemeData theme,
  PurchaseOrderDetail detail,
) {
  final label = _resolvePillLabel(
    explicit: detail.approvalStatus,
    id: detail.approvalStatusId,
    lookup: purchaseOrderApprovalStatusLabels,
  );

  final id =
      detail.approvalStatusId ?? _findIdForLabel(label, purchaseOrderApprovalStatusLabels);
  final colorScheme = theme.colorScheme;

  Color background;
  Color foreground;

  switch (id) {
    case 2:
      background = colorScheme.primaryContainer;
      foreground = colorScheme.onPrimaryContainer;
      break;
    case 3:
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
      break;
    case 4:
      background = colorScheme.tertiaryContainer;
      foreground = colorScheme.onTertiaryContainer;
      break;
    case 1:
    default:
      background = colorScheme.surfaceVariant;
      foreground = colorScheme.onSurfaceVariant;
      break;
  }

  return _PillStyle(
    label: label,
    backgroundColor: background,
    foregroundColor: foreground,
  );
}

String _resolvePillLabel({
  required String explicit,
  required int? id,
  required Map<int, String> lookup,
}) {
  final trimmed = explicit.trim();
  if (trimmed.isNotEmpty && trimmed != '—') {
    return trimmed;
  }
  if (id != null) {
    final mapped = lookup[id];
    if (mapped != null) {
      return mapped;
    }
  }
  return '—';
}

int? _findIdForLabel(String label, Map<int, String> lookup) {
  final normalized = label.trim().toLowerCase();
  for (final entry in lookup.entries) {
    if (entry.value.toLowerCase() == normalized) {
      return entry.key;
    }
  }
  return null;
}

class _SummaryField {
  const _SummaryField._(this.label, this.value, this.pillStyle);

  const _SummaryField.text(String label, String value)
      : this._(label, value, null);

  _SummaryField.pill({required String label, required _PillStyle pillStyle})
      : this._(label, pillStyle.label, pillStyle);

  final String label;
  final String value;
  final _PillStyle? pillStyle;
}

class _PillStyle {
  const _PillStyle({
    required this.label,
    required this.backgroundColor,
    required this.foregroundColor,
  });

  final String label;
  final Color backgroundColor;
  final Color foregroundColor;
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.field, required this.theme});

  final _SummaryField field;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 160),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            field.label,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          _SummaryValue(
            field: field,
            theme: theme,
          ),
        ],
      ),
    );
  }
}

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.field, required this.theme});

  final _SummaryField field;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final pill = field.pillStyle;
    final value = field.value.trim().isEmpty ? '—' : field.value.trim();

    if (pill == null || value == '—') {
      return Text(
        value,
        style: theme.textTheme.bodyMedium,
      );
    }

    final textStyle = theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w600,
          color: pill.foregroundColor,
        ) ??
        TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: pill.foregroundColor,
        );

    return Container(
      decoration: BoxDecoration(
        color: pill.backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 12,
        vertical: 6,
      ),
      child: Text(pill.label, style: textStyle),
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({
    required this.detail,
    required this.itemsController,
  });

  final PurchaseOrderDetail detail;
  final ScrollController itemsController;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SummarySection(detail: detail),
          const SizedBox(height: 24),
          _ItemsSection(
            detail: detail,
            controller: itemsController,
          ),
          const SizedBox(height: 24),
          _TotalsSection(detail: detail, theme: theme),
          if (detail.hasNotes) ...[
            const SizedBox(height: 24),
            _RichTextSection(
              title: 'Notes',
              value: detail.notes!,
            ),
          ],
          if (detail.hasTerms) ...[
            const SizedBox(height: 24),
            _RichTextSection(
              title: 'Terms & Conditions',
              value: detail.terms!,
            ),
          ],
        ],
      ),
    );
  }
}

class _PaymentsTab extends StatelessWidget {
  const _PaymentsTab({required this.detail});

  final PurchaseOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    if (!detail.hasPayments) {
      return const _EmptyTabMessage(
        icon: Icons.receipt_long,
        message: 'No payments recorded for this purchase order.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: detail.payments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final payment = detail.payments[index];
        return _PaymentCard(
          payment: payment,
          index: index + 1,
        );
      },
    );
  }
}

class _AttachmentsTab extends StatelessWidget {
  const _AttachmentsTab({required this.detail});

  final PurchaseOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    if (!detail.hasAttachments) {
      return const _EmptyTabMessage(
        icon: Icons.attach_file,
        message: 'No attachments were uploaded for this purchase order.',
      );
    }

    return ListView.separated(
      padding: EdgeInsets.zero,
      itemCount: detail.attachments.length,
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        final attachment = detail.attachments[index];
        return _AttachmentCard(attachment: attachment);
      },
    );
  }
}

class _PaymentCard extends StatelessWidget {
  const _PaymentCard({
    required this.payment,
    required this.index,
  });

  final PurchaseOrderPayment payment;
  final int index;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final titleStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );
    final referenceLabel =
        payment.reference.trim().isEmpty || payment.reference == '—'
            ? 'Payment $index'
            : payment.reference;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(referenceLabel, style: titleStyle),
          const SizedBox(height: 12),
          _LabelValueRow(label: 'Date', value: payment.dateLabel),
          _LabelValueRow(label: 'Amount', value: payment.amountLabel),
          _LabelValueRow(label: 'Method', value: payment.methodLabel),
          _LabelValueRow(label: 'Status', value: payment.statusLabel),
          if (payment.recordedBy != null && payment.recordedBy!.trim().isNotEmpty)
            _LabelValueRow(label: 'Recorded by', value: payment.recordedBy!.trim()),
          if (payment.hasNote) ...[
            const SizedBox(height: 12),
            Text(
              'Notes',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              payment.note!.trim(),
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ],
      ),
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment});

  final PurchaseOrderAttachment attachment;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: theme.dividerColor),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
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
          _LabelValueRow(label: 'Uploaded on', value: attachment.uploadedAtLabel),
          if (attachment.uploadedBy != null &&
              attachment.uploadedBy!.trim().isNotEmpty)
            _LabelValueRow(
              label: 'Uploaded by',
              value: attachment.uploadedBy!.trim(),
            ),
          if (attachment.sizeLabel != null && attachment.sizeLabel!.trim().isNotEmpty)
            _LabelValueRow(label: 'Size', value: attachment.sizeLabel!.trim()),
          if (attachment.hasDescription) ...[
            const SizedBox(height: 12),
            Text(
              'Description',
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: labelColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              attachment.description!.trim(),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (attachment.hasDownloadUrl) ...[
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
              attachment.downloadUrl!.trim(),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyTabMessage extends StatelessWidget {
  const _EmptyTabMessage({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurfaceVariant;

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 36, color: color),
          const SizedBox(height: 12),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: color),
            textAlign: TextAlign.center,
          ),
        ],
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
          SizedBox(
            width: 120,
            child: Text(
              label,
              style: labelStyle,
            ),
          ),
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

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({
    required this.detail,
    required this.controller,
  });

  final PurchaseOrderDetail detail;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (detail.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Items',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            'No items were returned for this purchase order.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    const tablePadding = EdgeInsets.symmetric(horizontal: 16, vertical: 12);
    final headerTextStyle =
        theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600) ??
            theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600) ??
            const TextStyle(fontWeight: FontWeight.w600);
    final cellStyle = theme.textTheme.bodyMedium;
    final dividerColor = theme.dividerColor;

    TableRow buildHeaderRow() {
      return TableRow(
        children: const [
          'Item',
          'Description',
          'Quantity',
          'Rate',
          'Amount',
        ].map((label) {
          return Padding(
            padding: tablePadding,
            child: Text(
              label,
              style: headerTextStyle,
            ),
          );
        }).toList(),
      );
    }

    TableRow buildDataRow(PurchaseOrderItem item) {
      return TableRow(
        children: [
          item.name,
          item.description,
          item.quantityLabel,
          item.rateLabel,
          item.amountLabel,
        ].map((value) {
          return Padding(
            padding: tablePadding,
            child: Text(
              value,
              style: cellStyle,
              softWrap: true,
            ),
          );
        }).toList(),
      );
    }

    Table buildTable() {
      return Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: const {
          0: FlexColumnWidth(2),
          1: FlexColumnWidth(3),
          2: FlexColumnWidth(1.4),
          3: FlexColumnWidth(1.4),
          4: FlexColumnWidth(1.4),
        },
        border: TableBorder.all(color: dividerColor),
        children: [
          buildHeaderRow(),
          ...detail.items.map(buildDataRow),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Items',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const minTableWidth = 720.0;
            return Scrollbar(
              controller: controller,
              thumbVisibility: true,
              notificationPredicate: (notification) =>
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minWidth: math.max(constraints.maxWidth, minTableWidth),
                  ),
                  child: buildTable(),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _TotalsSection extends StatelessWidget {
  const _TotalsSection({required this.detail, required this.theme});

  final PurchaseOrderDetail detail;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ..._buildTotalRows(),
        ],
      ),
    );
  }

  List<Widget> _buildTotalRows() {
    final rows = <Widget>[];

    void addRow(String label, String value, {bool emphasize = false}) {
      if (rows.isNotEmpty) {
        rows.add(const SizedBox(height: 8));
      }
      rows.add(
        _TotalRow(
          label: label,
          value: value,
          theme: theme,
          emphasize: emphasize,
        ),
      );
    }

    addRow('Subtotal', detail.subtotalLabel);

    if (detail.hasDiscount && detail.discountLabel != null) {
      addRow('Discount', detail.discountLabel!);
    }

    if (detail.hasShippingFee && detail.shippingFeeLabel != null) {
      addRow('Shipping Fee', detail.shippingFeeLabel!);
    }

    addRow('Total', detail.totalLabel, emphasize: true);

    return rows;
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow({
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
          children: [
            TextSpan(
              text: value,
              style: valueStyle,
            ),
          ],
        ),
        textAlign: TextAlign.right,
      ),
    );
  }
}

class _RichTextSection extends StatelessWidget {
  const _RichTextSection({required this.title, required this.value});

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          value,
          style: theme.textTheme.bodyMedium,
        ),
      ],
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({this.error, this.onRetry});

  final Object? error;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(
            Icons.error_outline,
            color: theme.colorScheme.error,
            size: 48,
          ),
          const SizedBox(height: 16),
          Text(
            'Something went wrong',
            style: theme.textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          Text(
            error?.toString() ?? 'Unable to load purchase order details.',
            style: theme.textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Close'),
              ),
              if (onRetry != null) ...[
                const SizedBox(width: 12),
                ElevatedButton(
                  onPressed: onRetry,
                  child: const Text('Retry'),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
