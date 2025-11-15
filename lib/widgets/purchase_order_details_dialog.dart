import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

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
  Map<String, String>? _attachmentPreviewHeaders;

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
    _attachmentPreviewHeaders = null;
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

    final previewHeaders = <String, String>{};
    if (authtokenHeader.isNotEmpty) {
      previewHeaders['authtoken'] = authtokenHeader;
      previewHeaders['Cookie'] = 'authtoken=$authtokenHeader';
    }
    if (normalizedAuth.isNotEmpty) {
      previewHeaders['Authorization'] = normalizedAuth;
    }
    _attachmentPreviewHeaders =
        previewHeaders.isEmpty ? null : Map.unmodifiable(previewHeaders);

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
                          _AttachmentsTab(
                            detail: detail,
                            previewHeaders: _attachmentPreviewHeaders,
                          ),
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
        label: 'Delivery status',
        pillStyle: _buildDeliveryStatusPillStyle(theme, detail),
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

_PillStyle _buildDeliveryStatusPillStyle(
  ThemeData theme,
  PurchaseOrderDetail detail,
) {
  final label = _resolvePillLabel(
    explicit: detail.deliveryStatusLabel,
    id: detail.deliveryStatusId,
    lookup: purchaseOrderDeliveryStatusLabels,
  );

  final id =
      detail.deliveryStatusId ?? _findIdForLabel(label, purchaseOrderDeliveryStatusLabels);
  final colorScheme = theme.colorScheme;

  Color background;
  Color foreground;

  switch (id) {
    case 1:
      background = colorScheme.primaryContainer;
      foreground = colorScheme.onPrimaryContainer;
      break;
    case 0:
      background = colorScheme.errorContainer;
      foreground = colorScheme.onErrorContainer;
      break;
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

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: constraints.maxWidth),
            child: DataTable(
              columnSpacing: 24,
              columns: const [
                DataColumn(label: Text('Amount')),
                DataColumn(label: Text('Payment Mode')),
                DataColumn(label: Text('Date')),
                DataColumn(label: Text('Actions')),
              ],
              rows: detail.payments
                  .map(
                    (payment) => DataRow(
                      cells: [
                        DataCell(Text(payment.amountLabel)),
                        DataCell(Text(payment.methodLabel)),
                        DataCell(Text(payment.dateLabel)),
                        DataCell(
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Edit payment',
                                icon: const Icon(Icons.edit_outlined),
                                onPressed: () {},
                              ),
                              IconButton(
                                tooltip: 'Delete payment',
                                icon: const Icon(Icons.delete_outline),
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  )
                  .toList(),
            ),
          ),
        );
      },
    );
  }
}

class _AttachmentsTab extends StatelessWidget {
  const _AttachmentsTab({required this.detail, this.previewHeaders});

  final PurchaseOrderDetail detail;
  final Map<String, String>? previewHeaders;

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
        return _AttachmentCard(
          attachment: attachment,
          previewHeaders: previewHeaders,
        );
      },
    );
  }
}

class _AttachmentCard extends StatelessWidget {
  const _AttachmentCard({required this.attachment, this.previewHeaders});

  final PurchaseOrderAttachment attachment;
  final Map<String, String>? previewHeaders;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final labelColor = theme.colorScheme.onSurfaceVariant;
    final previewType = _resolveAttachmentType(attachment);
    final canPreview =
        attachment.hasDownloadUrl && previewType != _AttachmentPreviewType.unsupported;
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
          if (canPreview)
            const SizedBox(width: 8),
          if (canPreview)
            Tooltip(
              message: 'Preview attachment',
              child: Icon(
                previewType == _AttachmentPreviewType.pdf
                    ? Icons.picture_as_pdf_outlined
                    : Icons.image_outlined,
                color: theme.colorScheme.primary,
              ),
            ),
        ],
      ),
      const SizedBox(height: 12),
      _LabelValueRow(label: 'Uploaded on', value: attachment.uploadedAtLabel),
    ];

    if (attachment.uploadedBy != null && attachment.uploadedBy!.trim().isNotEmpty) {
      children.add(
        _LabelValueRow(
          label: 'Uploaded by',
          value: attachment.uploadedBy!.trim(),
        ),
      );
    }

    if (attachment.sizeLabel != null && attachment.sizeLabel!.trim().isNotEmpty) {
      children.add(_LabelValueRow(label: 'Size', value: attachment.sizeLabel!.trim()));
    }

    if (attachment.hasDescription) {
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
        Text(
          attachment.description!.trim(),
          style: theme.textTheme.bodyMedium,
        ),
      ]);
    }

    if (attachment.hasDownloadUrl) {
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
          _normalizeAttachmentPreviewUrl(attachment.downloadUrl!),
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.primary,
          ),
        ),
        const SizedBox(height: 12),
        Align(
          alignment: Alignment.centerRight,
          child: canPreview
              ? OutlinedButton.icon(
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Preview'),
                  onPressed: () => _showPreview(context),
                )
              : Text(
                  'Preview is not available for this file type.',
                  style: theme.textTheme.bodySmall?.copyWith(color: labelColor),
                ),
        ),
      ]);
    }

    final card = Container(
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

    if (!canPreview) {
      return card;
    }

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        mouseCursor: SystemMouseCursors.click,
        onTap: () => _showPreview(context),
        child: card,
      ),
    );
  }

  void _showPreview(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => _AttachmentPreviewDialog(
        attachment: attachment,
        headers: previewHeaders,
      ),
    );
  }
}

class _AttachmentPreviewDialog extends StatelessWidget {
  const _AttachmentPreviewDialog({required this.attachment, this.headers});

  final PurchaseOrderAttachment attachment;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final type = _resolveAttachmentType(attachment);

    Widget preview;
    if (!attachment.hasDownloadUrl) {
      preview = const _AttachmentPreviewMessage(
        icon: Icons.link_off,
        message: 'This attachment does not provide a downloadable preview.',
      );
    } else {
      final url = _normalizeAttachmentPreviewUrl(attachment.downloadUrl!);
      switch (type) {
        case _AttachmentPreviewType.image:
          preview = _ImageAttachmentPreview(url: url, headers: headers);
          break;
        case _AttachmentPreviewType.pdf:
          preview = _PdfAttachmentPreview(url: url, headers: headers);
          break;
        case _AttachmentPreviewType.unsupported:
          preview = _AttachmentPreviewMessage(
            icon: Icons.visibility_off_outlined,
            message:
                'Preview is not available for this file type. Use the download URL to open it externally.',
          );
          break;
      }
    }

    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720, maxHeight: 640),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      attachment.fileName,
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Close preview',
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                    ),
                    child: preview,
                  ),
                ),
              ),
              if (attachment.hasDownloadUrl) ...[
                const SizedBox(height: 16),
                Text(
                  'Download URL',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 4),
                SelectableText(
                  _normalizeAttachmentPreviewUrl(attachment.downloadUrl!),
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.primary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _ImageAttachmentPreview extends StatelessWidget {
  const _ImageAttachmentPreview({required this.url, this.headers});

  final String url;
  final Map<String, String>? headers;

  @override
  Widget build(BuildContext context) {
    return InteractiveViewer(
      maxScale: 5,
      child: Center(
        child: Image.network(
          url,
          headers: headers,
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => const _AttachmentPreviewMessage(
            icon: Icons.broken_image_outlined,
            message: 'Unable to load the image preview.',
          ),
        ),
      ),
    );
  }
}

class _PdfAttachmentPreview extends StatefulWidget {
  const _PdfAttachmentPreview({required this.url, this.headers});

  final String url;
  final Map<String, String>? headers;

  @override
  State<_PdfAttachmentPreview> createState() => _PdfAttachmentPreviewState();
}

class _PdfAttachmentPreviewState extends State<_PdfAttachmentPreview> {
  final PdfViewerController _controller = PdfViewerController();
  PdfDocumentLoadFailedDetails? _loadFailure;

  @override
  void didUpdateWidget(covariant _PdfAttachmentPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        !mapEquals(oldWidget.headers, widget.headers)) {
      setState(() {
        _loadFailure = null;
      });
    }
  }

  Future<Uint8List> _fetchPdfBytes() async {
    final uri = Uri.tryParse(widget.url);
    if (uri == null) {
      throw Exception('The attachment URL is invalid.');
    }

    final requestHeaders = <String, String>{
      if (widget.headers != null) ...widget.headers!,
    };
    requestHeaders.putIfAbsent(
      'Accept',
      () => 'application/pdf,application/octet-stream',
    );

    http.Response response;
    try {
      response = await http.get(uri, headers: requestHeaders);
    } catch (error) {
      throw Exception('Failed to contact the server: $error');
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final reason = response.reasonPhrase?.trim();
      final suffix = reason == null || reason.isEmpty ? '' : ' ($reason)';
      throw Exception('Request failed with status ${response.statusCode}$suffix');
    }

    final bytes = response.bodyBytes;
    if (bytes.isEmpty) {
      throw Exception('The attachment returned no data.');
    }

    return bytes;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }

        if (snapshot.hasError) {
          final description = snapshot.error.toString();
          final details = description.isEmpty ? '' : '\n\n$description';
          return _AttachmentPreviewMessage(
            icon: Icons.picture_as_pdf_outlined,
            message:
                'Unable to load the PDF preview. Try downloading the file to view it externally.$details',
          );
        }

    final headers = widget.headers == null
        ? null
        : Map<String, String>.from(widget.headers!);

    return SfPdfViewer.network(
      widget.url,
      key: ValueKey('${widget.url}-${headers?.hashCode ?? 0}'),
      controller: _controller,
      headers: headers,
      canShowPaginationDialog: true,
      onDocumentLoadFailed: (details) {
        if (!mounted) {
          return;
        }

        final headersHash = widget.headers == null
            ? 0
            : Object.hashAllUnordered(
                widget.headers!.entries
                    .map((entry) => Object.hash(entry.key, entry.value)),
              );
        return SfPdfViewer.memory(
          bytes,
          key: ValueKey('${widget.url}-$headersHash'),
        );
      },
    );
  }
}

String _normalizeAttachmentPreviewUrl(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) {
    return trimmed;
  }

  Uri? parsed;
  try {
    parsed = Uri.parse(trimmed);
  } on FormatException {
    parsed = null;
  }

  if (parsed != null) {
    return parsed.toString();
  }

  final encoded = Uri.encodeFull(trimmed)
      .replaceAll('(', '%28')
      .replaceAll(')', '%29');
  return encoded;
}

class _AttachmentPreviewMessage extends StatelessWidget {
  const _AttachmentPreviewMessage({required this.icon, required this.message});

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
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

enum _AttachmentPreviewType { image, pdf, unsupported }

_AttachmentPreviewType _resolveAttachmentType(PurchaseOrderAttachment attachment) {
  final extension = _resolveAttachmentExtension(
    [attachment.fileName, attachment.downloadUrl],
  );

  if (extension == null) {
    return _AttachmentPreviewType.unsupported;
  }

  if (_imageAttachmentExtensions.contains(extension)) {
    return _AttachmentPreviewType.image;
  }

  if (extension == 'pdf') {
    return _AttachmentPreviewType.pdf;
  }

  return _AttachmentPreviewType.unsupported;
}

String? _resolveAttachmentExtension(List<Object?> candidates) {
  for (final candidate in candidates) {
    final value = switch (candidate) {
      String s => s,
      Uri u => u.toString(),
      _ => null,
    };
    if (value == null || value.trim().isEmpty) {
      continue;
    }
    final sanitized = value.split('?').first.split('#').first;
    final dotIndex = sanitized.lastIndexOf('.');
    if (dotIndex == -1 || dotIndex == sanitized.length - 1) {
      continue;
    }
    return sanitized.substring(dotIndex + 1).toLowerCase();
  }
  return null;
}

const _imageAttachmentExtensions = <String>{
  'apng',
  'avif',
  'bmp',
  'gif',
  'jpeg',
  'jpg',
  'png',
  'webp',
};

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
