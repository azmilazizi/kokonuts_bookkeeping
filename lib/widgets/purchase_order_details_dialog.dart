import 'dart:math' as math;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';
import '../services/payment_modes_service.dart';
import '../services/purchase_order_detail_service.dart';
import '../services/purchase_orders_service.dart';
import 'attachment_pdf_preview.dart';
import 'attachment_picker.dart';
import 'authenticated_image.dart';
import 'currency_input_formatter.dart';
import 'searchable_dropdown_form_field.dart';

class PurchaseOrderDetailsDialog extends StatefulWidget {
  const PurchaseOrderDetailsDialog({super.key, required this.orderId});

  final String orderId;

  @override
  State<PurchaseOrderDetailsDialog> createState() =>
      _PurchaseOrderDetailsDialogState();
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
      child: Stack(
        children: [
          Positioned(
            top: 0,
            right: 0,
            child: IconButton(
              tooltip: 'Close',
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close),
            ),
          ),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
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
                if (onRetry != null) ...[
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: onRetry,
                    child: const Text('Retry'),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PurchaseOrderDetailsDialogState
    extends State<PurchaseOrderDetailsDialog> {
  late Future<PurchaseOrderDetail> _future;
  final _service = PurchaseOrderDetailService();
  final _purchaseOrdersService = PurchaseOrdersService();
  final _paymentModesService = PaymentModesService();
  final _itemsScrollController = ScrollController();
  bool _initialized = false;
  Map<String, String>? _apiHeaders;

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

    _apiHeaders = {
      'Accept': 'application/json',
      'authtoken': authtokenHeader,
      'Authorization': normalizedAuth,
    };

    return _service.fetchPurchaseOrder(
      id: widget.orderId,
      headers: _apiHeaders!,
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
              return _ErrorView(error: snapshot.error, onRetry: _retry);
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
                    TabBar(
                      labelColor: Theme.of(context).colorScheme.primary,
                      tabs: const [
                        Tab(text: 'Details'),
                        Tab(text: 'Payments'),
                        Tab(text: 'Attachments'),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: TabBarView(
                        children: [
                          _DetailsTab(
                            detail: detail,
                            itemsController: _itemsScrollController,
                          ),
                          _PaymentsTab(
                            orderId: detail.id,
                            orderNumber: detail.number,
                            payments: detail.payments,
                            currencySymbol: detail.currencySymbol,
                            apiHeaders: _apiHeaders,
                            paymentModesService: _paymentModesService,
                            purchaseOrdersService: _purchaseOrdersService,
                            onPaymentsChanged: _retry,
                          ),
                          _AttachmentsTab(
                            orderId: detail.id,
                            attachments: detail.attachments,
                            apiHeaders: _apiHeaders,
                            onAttachmentsChanged: _retry,
                          ),
                        ],
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
  const _DialogHeader({required this.orderNumber, required this.onClose});

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

class _SummaryValue extends StatelessWidget {
  const _SummaryValue({required this.field});

  final _SummaryField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pill = field.pillStyle;
    final value = field.value.trim().isEmpty ? '—' : field.value.trim();

    if (pill == null || value == '—') {
      return Text(value, style: theme.textTheme.bodyMedium);
    }

    final textStyle =
        theme.textTheme.labelSmall?.copyWith(
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
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Text(pill.label, style: textStyle),
    );
  }
}

class _SummaryTile extends StatelessWidget {
  const _SummaryTile({required this.field});

  final _SummaryField field;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
          _SummaryValue(field: field),
        ],
      ),
    );
  }
}

class _SummarySection extends StatelessWidget {
  const _SummarySection({required this.detail});

  final PurchaseOrderDetail detail;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final approvalStatusField = _SummaryField.pill(
      label: 'Approval status',
      pillStyle: _buildApprovalPillStyle(theme, detail),
    );
    final deliveryStatusField = _SummaryField.pill(
      label: 'Delivery status',
      pillStyle: _buildDeliveryStatusPillStyle(theme, detail),
    );
    final vendorField = _SummaryField.text('Vendor', detail.vendorName);
    final orderNameField = _SummaryField.text('Order name', detail.name);
    final orderDateField = _SummaryField.text(
      'Order date',
      detail.orderDateLabel,
    );
    final deliveryDateField = _SummaryField.text(
      'Delivery date',
      detail.deliveryDateLabel,
    );
    final referenceField = detail.referenceLabel != null
        ? _SummaryField.text('Reference', detail.referenceLabel!)
        : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= 720;

        if (!isWide) {
          final fields = <_SummaryField?>[
            approvalStatusField,
            deliveryStatusField,
            vendorField,
            orderNameField,
            orderDateField,
            deliveryDateField,
            referenceField,
          ].whereType<_SummaryField>().toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < fields.length; i++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: i == fields.length - 1 ? 0 : 16,
                  ),
                  child: _SummaryTile(field: fields[i]),
                ),
            ],
          );
        }

        final rows = <Widget>[
          Row(
            children: [
              Expanded(child: _SummaryTile(field: approvalStatusField)),
              const SizedBox(width: 16),
              Expanded(child: _SummaryTile(field: deliveryStatusField)),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryTile(field: vendorField),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(child: _SummaryTile(field: orderNameField)),
              const SizedBox(width: 16),
              Expanded(child: _SummaryTile(field: orderDateField)),
            ],
          ),
          const SizedBox(height: 16),
          _SummaryTile(field: deliveryDateField),
        ];

        if (referenceField != null) {
          rows
            ..add(const SizedBox(height: 16))
            ..add(_SummaryTile(field: referenceField));
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: rows,
        );
      },
    );
  }
}

_PillStyle _buildDeliveryStatusPillStyle(
  ThemeData theme,
  PurchaseOrderDetail detail,
) {
  final normalizedStatus = detail.orderStatus.trim().toLowerCase();
  final colorScheme = theme.colorScheme;

  Color background;
  Color foreground;
  String label;

  switch (normalizedStatus) {
    case 'delivered':
      background = Colors.green.shade100;
      foreground = Colors.green.shade900;
      label = 'Delivered';
      break;
    case 'return':
      background = Colors.yellow.shade100;
      foreground = Colors.yellow.shade900;
      label = 'Returned';
      break;
    case 'new':
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
      label = 'Not Yet Delivered';
      break;
    default:
      final fallbackLabel = _resolvePillLabel(
        explicit: detail.deliveryStatusLabel,
        id: detail.deliveryStatusId,
        lookup: purchaseOrderDeliveryStatusLabels,
      );
      final fallbackId =
          detail.deliveryStatusId ??
          _findIdForLabel(fallbackLabel, purchaseOrderDeliveryStatusLabels);
      if (fallbackId == 1) {
        background = Colors.green.shade100;
        foreground = Colors.green.shade900;
        label = 'Delivered';
      } else {
        background = colorScheme.errorContainer;
        foreground = colorScheme.onErrorContainer;
        label = 'Not Yet Delivered';
      }
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
      detail.approvalStatusId ??
      _findIdForLabel(label, purchaseOrderApprovalStatusLabels);
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
    final numericLabel = int.tryParse(trimmed);
    if (numericLabel != null) {
      final mapped = lookup[numericLabel];
      if (mapped != null) {
        return mapped;
      }
    }
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

class _ItemsSection extends StatelessWidget {
  const _ItemsSection({required this.detail, required this.controller});

  final PurchaseOrderDetail detail;
  final ScrollController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (detail.items.isEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Items', style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          Text(
            'No items were returned for this purchase order.',
            style: theme.textTheme.bodyMedium,
          ),
        ],
      );
    }

    const tablePadding = EdgeInsets.symmetric(horizontal: 12, vertical: 10);
    final headerTextStyle =
        theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        theme.textTheme.bodyMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurfaceVariant,
        ) ??
        const TextStyle(fontWeight: FontWeight.w700);
    final cellStyle = theme.textTheme.bodyMedium;
    final dividerColor = theme.dividerColor;

    final hasDiscountColumn = detail.items.any((item) => item.hasDiscount);

    TableRow buildHeaderRow() {
      final headers = [
        'Item',
        'Description',
        'Quantity',
        'Rate',
        if (hasDiscountColumn) 'Discount (RM)',
        'Total',
      ];

      return TableRow(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceVariant.withOpacity(0.4),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
        ),
        children: headers
            .map(
              (label) => Padding(
                padding: tablePadding,
                child: Text(label, style: headerTextStyle),
              ),
            )
            .toList(),
      );
    }

    TableRow buildDataRow(PurchaseOrderItem item) {
      final values = [
        item.name,
        item.description,
        item.quantityLabel,
        item.rateLabel,
        if (hasDiscountColumn) item.discountLabel ?? '—',
        item.amountLabel,
      ];

      return TableRow(
        children: values
            .map(
              (value) => Padding(
                padding: tablePadding,
                child: Text(value, style: cellStyle, softWrap: true),
              ),
            )
            .toList(),
      );
    }

    Table buildTable() {
      final columnWidths = <int, TableColumnWidth>{
        0: const FlexColumnWidth(2),
        1: const FlexColumnWidth(3),
        2: const FlexColumnWidth(1.4),
        3: const FlexColumnWidth(1.4),
      };

      var columnIndex = 4;
      if (hasDiscountColumn) {
        columnWidths[columnIndex] = const FlexColumnWidth(1.4);
        columnIndex++;
      }

      columnWidths[columnIndex] = const FlexColumnWidth(1.4);

      return Table(
        defaultVerticalAlignment: TableCellVerticalAlignment.middle,
        columnWidths: columnWidths,
        border: TableBorder.all(
          color: dividerColor,
          width: 1,
          borderRadius: BorderRadius.circular(8),
        ),
        children: [buildHeaderRow(), ...detail.items.map(buildDataRow)],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items', style: theme.textTheme.titleMedium),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            const minTableWidth = 900.0;
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
        children: [..._buildTotalRows()],
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
          children: [TextSpan(text: value, style: valueStyle)],
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
        Text(title, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        Text(value, style: theme.textTheme.bodyMedium),
      ],
    );
  }
}

class _DetailsTab extends StatelessWidget {
  const _DetailsTab({required this.detail, required this.itemsController});

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
          _ItemsSection(detail: detail, controller: itemsController),
          const SizedBox(height: 24),
          _TotalsSection(detail: detail, theme: theme),
          if (detail.hasNotes) ...[
            const SizedBox(height: 24),
            _RichTextSection(title: 'Notes', value: detail.notes!),
          ],
          if (detail.hasTerms) ...[
            const SizedBox(height: 24),
            _RichTextSection(title: 'Terms & Conditions', value: detail.terms!),
          ],
        ],
      ),
    );
  }
}

class _PaymentsTab extends StatefulWidget {
  const _PaymentsTab({
    required this.orderId,
    required this.orderNumber,
    required this.payments,
    required this.currencySymbol,
    required this.paymentModesService,
    required this.purchaseOrdersService,
    this.apiHeaders,
    this.onPaymentsChanged,
  });

  final String orderId;
  final String orderNumber;
  final List<PurchaseOrderPayment> payments;
  final String currencySymbol;
  final PaymentModesService paymentModesService;
  final PurchaseOrdersService purchaseOrdersService;
  final Map<String, String>? apiHeaders;
  final VoidCallback? onPaymentsChanged;

  @override
  State<_PaymentsTab> createState() => _PaymentsTabState();
}

class _PaymentsTabState extends State<_PaymentsTab> {
  late List<PurchaseOrderPayment> _payments;
  List<PaymentMode> _paymentModes = const [];
  Map<String, String>? _paymentModesById;
  bool _isLoadingPaymentModes = false;
  bool _hasAttemptedLoadingModes = false;
  String? _paymentModesError;
  final Set<String> _deletingPaymentIds = {};
  bool _isCreatingPayment = false;

  @override
  void initState() {
    super.initState();
    _payments = _deduplicatePayments(widget.payments);
  }

  @override
  void didUpdateWidget(covariant _PaymentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.payments != widget.payments) {
      _payments = _deduplicatePayments(widget.payments);
    }
    if (widget.apiHeaders != null && !_hasAttemptedLoadingModes) {
      _loadPaymentModes();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.apiHeaders != null && !_hasAttemptedLoadingModes) {
      _loadPaymentModes();
    }
  }

  Future<void> _loadPaymentModes() async {
    if (_isLoadingPaymentModes || widget.apiHeaders == null) {
      return;
    }

    setState(() {
      _isLoadingPaymentModes = true;
      _paymentModesError = null;
      _hasAttemptedLoadingModes = true;
    });

    try {
      final modes = await widget.paymentModesService.fetchPaymentModes(
        headers: widget.apiHeaders!,
      );
      setState(() {
        _paymentModes = modes;
        _paymentModesById = {for (final mode in modes) mode.id: mode.name};
      });
    } catch (error) {
      setState(() {
        _paymentModesError = error.toString();
      });
    } finally {
      if (mounted) {
        setState(() => _isLoadingPaymentModes = false);
      }
    }
  }

  int? _parsePurchaseOrderNumber(String orderNumber) {
    final match = RegExp(r'#?PO-(\d+)').firstMatch(orderNumber);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return int.tryParse(orderNumber);
  }

  List<PurchaseOrderPayment> _deduplicatePayments(
    List<PurchaseOrderPayment> payments,
  ) {
    final seenIds = <String>{};
    final deduplicated = <PurchaseOrderPayment>[];

    for (final payment in payments) {
      final paymentId = payment.id?.trim();
      if (paymentId != null && paymentId.isNotEmpty) {
        if (seenIds.contains(paymentId)) {
          continue;
        }
        seenIds.add(paymentId);
      }
      deduplicated.add(payment);
    }

    return deduplicated;
  }

  Future<void> _openAddPaymentDialog() async {
    if (_isCreatingPayment) return;

    final headers = widget.apiHeaders;
    if (headers == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing credentials to add payments.')),
      );
      return;
    }

    if (_paymentModes.isEmpty && !_isLoadingPaymentModes) {
      await _loadPaymentModes();
    }

    final appState = AppStateScope.of(context);
    final requester = appState.currentUserId;
    final purchaseOrderNumber = _parsePurchaseOrderNumber(widget.orderNumber);

    final newPayments = await showDialog<List<_NewPaymentEntry>>(
      context: context,
      builder: (context) => _AddPaymentDialog(
        currencySymbol: widget.currencySymbol,
        paymentModes: _paymentModes,
        isLoadingPaymentModes: _isLoadingPaymentModes,
      ),
    );

    if (newPayments == null || newPayments.isEmpty) {
      return;
    }

    setState(() {
      _isCreatingPayment = true;
    });

    try {
      await widget.purchaseOrdersService.createPayments(
        id: widget.orderId,
        headers: headers,
        payments: newPayments
            .map(
              (entry) => CreatePurchaseOrderPayment(
                purchaseOrderNumber: purchaseOrderNumber,
                amount: entry.amount,
                paymentMode: entry.paymentModeId,
                date: entry.date,
                requester: requester,
              ),
            )
            .toList(growable: false),
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payments added successfully.')),
      );

      widget.onPaymentsChanged?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add payments: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isCreatingPayment = false;
        });
      }
    }
  }

  String _resolvePaymentMethod(PurchaseOrderPayment payment) {
    final rawMethod = payment.method?.trim();
    if (rawMethod != null && rawMethod.isNotEmpty) {
      final mapped = _paymentModesById?[rawMethod];
      if (mapped != null && mapped.isNotEmpty) {
        return mapped;
      }
    }

    final label = payment.methodLabel;
    if (label != '—') {
      return label;
    }

    if (rawMethod != null && rawMethod.isNotEmpty) {
      return rawMethod;
    }

    return '—';
  }

  String _formatAmount(PurchaseOrderPayment payment) {
    if (payment.amountValue != null) {
      final formatted = payment.amountValue!.toStringAsFixed(2);
      final symbol = widget.currencySymbol;
      if (symbol.isNotEmpty && symbol.toLowerCase() != '0') {
        return '$symbol $formatted';
      }
      return formatted;
    }

    return payment.amountLabel;
  }

  Future<void> _handleDelete(PurchaseOrderPayment payment) async {
    final paymentId = payment.id?.trim();
    if (paymentId == null || paymentId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to delete this payment.')),
      );
      return;
    }

    final headers = widget.apiHeaders;
    if (headers == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing credentials to delete this payment.'),
        ),
      );
      return;
    }

    setState(() {
      _deletingPaymentIds.add(paymentId);
    });

    try {
      await widget.purchaseOrdersService.deletePayments(
        id: widget.orderId,
        headers: headers,
        paymentIds: [paymentId],
      );

      if (!mounted) return;

      setState(() {
        _payments.removeWhere((entry) => entry.id == payment.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Payment deleted successfully.')),
      );

      widget.onPaymentsChanged?.call();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete payment: $error')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _deletingPaymentIds.remove(paymentId);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final addPaymentButton = ElevatedButton.icon(
      onPressed: _isCreatingPayment ? null : _openAddPaymentDialog,
      icon: _isCreatingPayment
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.add),
      label: const Text('Add Payment'),
    );

    if (_payments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.payments_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              'No payments recorded for this purchase order.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            addPaymentButton,
            if (_paymentModesError != null) ...[
              const SizedBox(height: 8),
              Text(
                'Failed to load payment methods: $_paymentModesError',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    final headerStyle = theme.textTheme.labelMedium?.copyWith(
      fontWeight: FontWeight.w700,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_paymentModesError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Failed to load payment methods: $_paymentModesError',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
        if (_isLoadingPaymentModes)
          const Padding(
            padding: EdgeInsets.only(bottom: 8),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
          ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final minWidth = math.max(constraints.maxWidth, 640.0);
              return Scrollbar(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minWidth: minWidth),
                    child: Table(
                      columnWidths: const {
                        0: FlexColumnWidth(2),
                        1: FlexColumnWidth(3),
                        2: FlexColumnWidth(2),
                        3: IntrinsicColumnWidth(),
                      },
                      border: TableBorder.all(
                        color: theme.dividerColor,
                        width: 1,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      defaultVerticalAlignment:
                          TableCellVerticalAlignment.middle,
                      children: [
                        TableRow(
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceVariant.withOpacity(
                              0.4,
                            ),
                            borderRadius: const BorderRadius.vertical(
                              top: Radius.circular(8),
                            ),
                          ),
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                              child: Text('Date', style: headerStyle),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                              child: Text('Payment Method', style: headerStyle),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                              child: Text('Amount', style: headerStyle),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                vertical: 10,
                                horizontal: 12,
                              ),
                              child: Text(
                                'Actions',
                                style: headerStyle,
                                textAlign: TextAlign.end,
                              ),
                            ),
                          ],
                        ),
                        ..._payments.map((payment) {
                          final paymentId = payment.id ?? payment.reference;
                          final dateLabel = payment.date != null
                              ? DateFormat.yMMMd().format(payment.date!)
                              : payment.dateLabel;
                          final methodLabel = _resolvePaymentMethod(payment);
                          final isDeleting =
                              paymentId != null &&
                              _deletingPaymentIds.contains(paymentId);

                          return TableRow(
                            children: [
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                child: Text(dateLabel),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                child: Text(methodLabel),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 10,
                                  horizontal: 12,
                                ),
                                child: Text(
                                  _formatAmount(payment),
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  vertical: 8,
                                  horizontal: 12,
                                ),
                                child: Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    tooltip: 'Delete payment',
                                    icon: isDeleting
                                        ? const SizedBox(
                                            width: 16,
                                            height: 16,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                            ),
                                          )
                                        : const Icon(Icons.delete_outline),
                                    color: theme.colorScheme.error,
                                    onPressed: isDeleting
                                        ? null
                                        : () => _handleDelete(payment),
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
            },
          ),
        ),
        const SizedBox(height: 12),
        Align(alignment: Alignment.centerRight, child: addPaymentButton),
      ],
    );
  }
}

class _AddPaymentDialog extends StatefulWidget {
  const _AddPaymentDialog({
    required this.paymentModes,
    required this.currencySymbol,
    required this.isLoadingPaymentModes,
  });

  final List<PaymentMode> paymentModes;
  final String currencySymbol;
  final bool isLoadingPaymentModes;

  @override
  State<_AddPaymentDialog> createState() => _AddPaymentDialogState();
}

class _AddPaymentDialogState extends State<_AddPaymentDialog> {
  final _formKey = GlobalKey<FormState>();
  late final String? _defaultPaymentModeId;
  final List<_PaymentFormEntry> _entries = [_PaymentFormEntry()];
  String? _submitError;

  @override
  void initState() {
    super.initState();
    _defaultPaymentModeId = _findDefaultPaymentModeId();
    if (_defaultPaymentModeId != null) {
      _entries.first.paymentModeId = _defaultPaymentModeId;
    }
  }

  String? _findDefaultPaymentModeId() {
    for (final mode in widget.paymentModes) {
      if (mode.name.toLowerCase() == 'bank transfer') {
        return mode.id;
      }
    }
    return null;
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate(_PaymentFormEntry entry) async {
    final selected = await showDatePicker(
      context: context,
      firstDate: DateTime(DateTime.now().year - 10),
      lastDate: DateTime(DateTime.now().year + 10),
      initialDate: entry.date,
    );

    if (selected != null) {
      setState(() {
        entry.date = selected;
      });
    }
  }

  void _addEntry() {
    setState(() {
      _entries.add(_PaymentFormEntry(paymentModeId: _defaultPaymentModeId));
    });
  }

  void _removeEntry(int index) {
    if (_entries.length == 1) {
      return;
    }

    setState(() {
      _entries.removeAt(index).dispose();
    });
  }

  void _handleSubmit() {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    final parsed = <_NewPaymentEntry>[];
    for (final entry in _entries) {
      final amount =
          double.tryParse(entry.amountController.text.replaceAll(',', '')) ?? 0;
      final paymentMode = entry.paymentModeId?.trim() ?? '';
      if (amount <= 0 || paymentMode.isEmpty) {
        setState(() {
          _submitError =
              'Enter a payment mode and amount greater than zero for all payments.';
        });
        return;
      }
      parsed.add(
        _NewPaymentEntry(
          amount: amount,
          paymentModeId: paymentMode,
          date: entry.date,
        ),
      );
    }

    Navigator.of(context).pop(parsed);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.titleMedium?.copyWith(
      fontWeight: FontWeight.w600,
    );

    return AlertDialog(
      title: const Text('Add Payments'),
      content: SizedBox(
        width: 720,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Use the form below to add one or more payments using the same fields as the Create Purchase Order dialog.',
                  style: theme.textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),
                if (widget.isLoadingPaymentModes)
                  Row(
                    children: const [
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                      SizedBox(width: 8),
                      Expanded(child: Text('Loading payment modes...')),
                    ],
                  ),
                const SizedBox(height: 8),
                for (var i = 0; i < _entries.length; i++) ...[
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Payment ${i + 1}',
                                  style: headerStyle,
                                ),
                              ),
                              IconButton(
                                tooltip: 'Remove payment',
                                icon: const Icon(Icons.delete_outline),
                                color: theme.colorScheme.error,
                                onPressed: () => _removeEntry(i),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _DialogResponsiveFieldsRow(
                            children: [
                              TextFormField(
                                controller: _entries[i].amountController,
                                decoration: const InputDecoration(
                                  labelText: 'Amount (RM)',
                                  border: OutlineInputBorder(),
                                  prefixText: 'RM ',
                                ),
                                keyboardType:
                                    const TextInputType.numberWithOptions(
                                      decimal: true,
                                    ),
                                inputFormatters: const [
                                  CurrencyInputFormatter(),
                                ],
                                textAlign: TextAlign.right,
                                validator: (value) {
                                  final parsed =
                                      double.tryParse(
                                        (value ?? '').replaceAll(',', ''),
                                      ) ??
                                      0;
                                  if (parsed <= 0) {
                                    return 'Enter an amount greater than zero.';
                                  }
                                  return null;
                                },
                              ),
                              SearchableDropdownFormField<String>(
                                initialValue: _entries[i].paymentModeId,
                                items: widget.paymentModes
                                    .map((mode) => mode.id)
                                    .toList(),
                                itemToString: (id) => widget.paymentModes
                                    .firstWhere(
                                      (mode) => mode.id == id,
                                      orElse: () => PaymentMode(
                                        id: id ?? '',
                                        name: 'Unknown',
                                      ),
                                    )
                                    .name,
                                decoration: const InputDecoration(
                                  labelText: 'Payment mode',
                                  border: OutlineInputBorder(),
                                ),
                                hintText: widget.isLoadingPaymentModes
                                    ? 'Loading payment modes...'
                                    : 'Select payment mode',
                                enabled:
                                    widget.paymentModes.isNotEmpty &&
                                    !widget.isLoadingPaymentModes,
                                dialogTitle: 'Select payment mode',
                                onChanged: widget.paymentModes.isEmpty
                                    ? null
                                    : (value) => setState(
                                        () => _entries[i].paymentModeId = value,
                                      ),
                                validator: (value) {
                                  if ((value ?? '').trim().isEmpty) {
                                    return 'Select a payment mode.';
                                  }
                                  return null;
                                },
                              ),
                              _PaymentDateField(
                                label: 'Payment date',
                                dateLabel: _entries[i].dateLabel,
                                onTap: () => _pickDate(_entries[i]),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                TextButton.icon(
                  onPressed: _addEntry,
                  icon: const Icon(Icons.add),
                  label: const Text('Add payment'),
                ),
                if (_submitError != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _submitError!,
                    style: theme.textTheme.bodySmall?.copyWith(
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
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _handleSubmit, child: const Text('Submit')),
      ],
    );
  }
}

class _PaymentFormEntry {
  _PaymentFormEntry({DateTime? initialDate, this.paymentModeId})
    : date = initialDate ?? DateTime.now(),
      amountController = TextEditingController(
        text: CurrencyInputFormatter.normalizeExistingValue(null),
      );

  final TextEditingController amountController;
  DateTime date;
  String? paymentModeId;

  String get dateLabel => DateFormat.yMMMd().format(date);

  void dispose() {
    amountController.dispose();
  }
}

class _NewPaymentEntry {
  const _NewPaymentEntry({
    required this.amount,
    required this.paymentModeId,
    required this.date,
  });

  final double amount;
  final String paymentModeId;
  final DateTime date;
}

class _DialogResponsiveFieldsRow extends StatelessWidget {
  const _DialogResponsiveFieldsRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isStacked = constraints.maxWidth < 680;
        if (isStacked) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < children.length; i++) ...[
                children[i],
                if (i != children.length - 1) const SizedBox(height: 12),
              ],
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              Expanded(child: children[i]),
              if (i != children.length - 1) const SizedBox(width: 12),
            ],
          ],
        );
      },
    );
  }
}

class _AddAttachmentDialog extends StatefulWidget {
  const _AddAttachmentDialog();

  @override
  State<_AddAttachmentDialog> createState() => _AddAttachmentDialogState();
}

class _AddAttachmentDialogState extends State<_AddAttachmentDialog> {
  List<PlatformFile> _files = const [];
  String? _error;

  Future<void> _pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.custom,
      allowedExtensions: allowedAttachmentExtensions.toList(growable: false),
      withData: true,
      withReadStream: true,
    );

    if (result == null || result.files.isEmpty) {
      return;
    }

    _replaceFiles([..._files, ...result.files]);
  }

  void _replaceFiles(List<PlatformFile> files) {
    for (final file in files) {
      final ext = attachmentExtension(file.name);
      if (!isAllowedAttachmentExtension(ext)) {
        setState(() {
          _error =
              'Unsupported file type. Please select PDF or image attachments.';
        });
        return;
      }
    }

    setState(() {
      _files = files;
      _error = null;
    });
  }

  void _removeFile(PlatformFile file) {
    setState(() {
      _files = List.of(_files)..remove(file);
    });
  }

  void _submit() {
    if (_files.isEmpty) {
      setState(() {
        _error = 'Select at least one attachment to continue.';
      });
      return;
    }

    Navigator.of(context).pop(_files);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Add Attachments'),
      content: SizedBox(
        width: 720,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Use the same attachment picker as the Create Purchase Order dialog to add supporting files.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 16),
              AttachmentPicker(
                description:
                    'Drag and drop receipts or supporting documents, or tap to browse.',
                files: _files,
                onPick: _pickFiles,
                onFilesSelected: _replaceFiles,
                onFileRemoved: _removeFile,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(
                  _error!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(onPressed: _submit, child: const Text('Submit')),
      ],
    );
  }
}

class _AttachmentsTab extends StatefulWidget {
  const _AttachmentsTab({
    required this.orderId,
    required this.attachments,
    this.apiHeaders,
    this.onAttachmentsChanged,
  });

  final String orderId;
  final List<PurchaseOrderAttachment> attachments;
  final Map<String, String>? apiHeaders;
  final VoidCallback? onAttachmentsChanged;

  @override
  State<_AttachmentsTab> createState() => _AttachmentsTabState();
}

class _AttachmentsTabState extends State<_AttachmentsTab> {
  final _purchaseOrdersService = PurchaseOrdersService();
  late List<PurchaseOrderAttachment> _attachments;
  bool _isUploading = false;
  String? _uploadError;

  @override
  void initState() {
    super.initState();
    _attachments = List<PurchaseOrderAttachment>.from(widget.attachments);
  }

  @override
  void didUpdateWidget(covariant _AttachmentsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.attachments != widget.attachments) {
      _attachments = List<PurchaseOrderAttachment>.from(widget.attachments);
    }
  }

  Future<void> _openAddAttachmentDialog() async {
    if (_isUploading) return;

    final headers = widget.apiHeaders;
    if (headers == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Missing credentials to upload attachments.'),
        ),
      );
      return;
    }

    final files = await showDialog<List<PlatformFile>>(
      context: context,
      builder: (context) => const _AddAttachmentDialog(),
    );

    if (!mounted || files == null || files.isEmpty) {
      return;
    }

    await _uploadAttachments(headers, files);
  }

  Future<void> _uploadAttachments(
    Map<String, String> headers,
    List<PlatformFile> files,
  ) async {
    final invalid = files.where((file) {
      final ext = attachmentExtension(file.name);
      return !isAllowedAttachmentExtension(ext);
    }).toList();

    if (invalid.isNotEmpty) {
      setState(() {
        _uploadError =
            'Unsupported file type. Please select PDF or image attachments.';
      });
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadError = null;
    });

    try {
      await _purchaseOrdersService.uploadAttachments(
        id: widget.orderId,
        headers: headers,
        attachments: files,
      );

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Attachments uploaded successfully.')),
      );

      widget.onAttachmentsChanged?.call();
    } catch (error) {
      if (mounted) {
        setState(() {
          _uploadError = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_attachments.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.attachment_outlined, size: 40),
            const SizedBox(height: 12),
            Text(
              'No attachments uploaded for this purchase order.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isUploading ? null : _openAddAttachmentDialog,
              icon: _isUploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.attach_file),
              label: const Text('Add Attachment'),
            ),
            if (_uploadError != null) ...[
              const SizedBox(height: 8),
              Text(
                _uploadError!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.error,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_uploadError != null) ...[
          const SizedBox(height: 8),
          Text(
            _uploadError!,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.error,
            ),
          ),
        ],
        const SizedBox(height: 12),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.only(bottom: 16),
            itemCount: _attachments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final attachment = _attachments[index];
              return _PurchaseOrderAttachmentCard(
                attachment: attachment,
                orderId: widget.orderId,
                apiHeaders: widget.apiHeaders,
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: ElevatedButton.icon(
            onPressed: _isUploading ? null : _openAddAttachmentDialog,
            icon: _isUploading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.attach_file),
            label: const Text('Add Attachment'),
          ),
        ),
      ],
    );
  }
}

class _PurchaseOrderAttachmentCard extends StatelessWidget {
  const _PurchaseOrderAttachmentCard({
    required this.attachment,
    required this.orderId,
    this.apiHeaders,
  });

  final PurchaseOrderAttachment attachment;
  final String orderId;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;

    final normalizedDownloadUrl = attachment.downloadUrl != null
        ? _normalizeAttachmentDownloadUrl(attachment.downloadUrl!)
        : null;

    final previewType = _resolveAttachmentPreviewType(
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

    final uploadedAtLabel = attachment.uploadedAtLabel.trim();
    if (uploadedAtLabel.isNotEmpty && uploadedAtLabel != '—') {
      children.add(
        _LabelValueRow(label: 'Uploaded on', value: uploadedAtLabel),
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
          child: _PreviewButton(
            fileName: attachment.fileName,
            downloadUrl: normalizedDownloadUrl!,
            previewType: previewType,
            apiHeaders: apiHeaders,
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

_AttachmentPreviewType? _resolveAttachmentPreviewType(
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
  Map<String, String>? apiHeaders,
}) {
  showDialog<void>(
    context: context,
    builder: (context) => _AttachmentPreviewDialog(
      fileName: fileName,
      downloadUrl: downloadUrl,
      previewType: previewType,
      apiHeaders: apiHeaders,
    ),
  );
}

class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({
    required this.fileName,
    required this.downloadUrl,
    required this.previewType,
    this.apiHeaders,
  });

  final String fileName;
  final String downloadUrl;
  final _AttachmentPreviewType previewType;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    final title = '$fileName preview';
    final theme = Theme.of(context);
    Widget content;

    switch (previewType) {
      case _AttachmentPreviewType.image:
        content = _ImagePreview(
          downloadUrl: downloadUrl,
          apiHeaders: apiHeaders,
        );
        break;
      case _AttachmentPreviewType.pdf:
        content = _PdfPreview(downloadUrl: downloadUrl, apiHeaders: apiHeaders);
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
  const _ImagePreview({required this.downloadUrl, this.apiHeaders});

  final String downloadUrl;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      child: Center(
        child: AuthenticatedImage(
          imageUrl: downloadUrl,
          headers: apiHeaders,
          fit: BoxFit.contain,
          loadingBuilder: (context, child, loadingProgress) {
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

class _PaymentDateField extends StatelessWidget {
  const _PaymentDateField({
    required this.label,
    required this.dateLabel,
    required this.onTap,
  });

  final String label;
  final String dateLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
        ),
        child: Row(
          children: [
            Icon(Icons.event, color: theme.colorScheme.primary),
            const SizedBox(width: 8),
            Expanded(child: Text(dateLabel)),
            const Icon(Icons.expand_more),
          ],
        ),
      ),
    );
  }
}

class _PdfPreview extends StatelessWidget {
  const _PdfPreview({required this.downloadUrl, this.apiHeaders});

  final String downloadUrl;
  final Map<String, String>? apiHeaders;

  @override
  Widget build(BuildContext context) {
    return buildAttachmentPdfPreview(downloadUrl, headers: apiHeaders);
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

class _PreviewButton extends StatefulWidget {
  const _PreviewButton({
    required this.fileName,
    required this.downloadUrl,
    required this.previewType,
    this.apiHeaders,
  });

  final String fileName;
  final String downloadUrl;
  final _AttachmentPreviewType previewType;
  final Map<String, String>? apiHeaders;

  @override
  State<_PreviewButton> createState() => _PreviewButtonState();
}

class _PreviewButtonState extends State<_PreviewButton> {
  bool _isLoading = false;

  Future<void> _onPressed() async {
    if (_isLoading) return;

    Map<String, String>? headers = widget.apiHeaders;

    if (headers == null || !headers.containsKey('authtoken')) {
      setState(() => _isLoading = true);
      try {
        final appState = AppStateScope.of(context);
        final token = await appState.getValidAuthToken();
        if (token != null && mounted) {
          headers = _buildAuthHeaders(appState, token);
        }
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }

    if (!mounted) return;

    _showAttachmentPreview(
      context: context,
      fileName: widget.fileName,
      downloadUrl: widget.downloadUrl,
      previewType: widget.previewType,
      apiHeaders: headers,
    );
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: _isLoading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white,
              ),
            )
          : const Icon(Icons.visibility),
      label: const Text('Preview'),
      onPressed: _onPressed,
    );
  }
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
