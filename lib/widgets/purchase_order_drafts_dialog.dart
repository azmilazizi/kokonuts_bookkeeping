import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/purchase_order_drafts_service.dart';

class PurchaseOrderDraftsDialog extends StatefulWidget {
  const PurchaseOrderDraftsDialog({super.key, required this.headers});

  final Map<String, String> headers;

  @override
  State<PurchaseOrderDraftsDialog> createState() =>
      _PurchaseOrderDraftsDialogState();
}

class _PurchaseOrderDraftsDialogState extends State<PurchaseOrderDraftsDialog> {
  final _service = PurchaseOrderDraftsService();
  final _deletingIds = <String>{};

  List<PurchaseOrderDraft> _drafts = [];
  int? _nextPage;
  bool _isLoading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadDrafts(reset: true);
  }

  Future<void> _loadDrafts({bool reset = false}) async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      if (reset) {
        _error = null;
        _drafts = [];
        _nextPage = null;
      }
    });

    final pageToLoad = reset ? 1 : _nextPage ?? 1;

    try {
      final page = await _service.fetchDrafts(
        headers: widget.headers,
        page: pageToLoad,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _drafts = [..._drafts, ...page.drafts];
        _nextPage = page.nextPage;
      });
    } catch (error) {
      if (mounted) {
        setState(() {
          _error = error.toString();
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteDraft(String id) async {
    if (_deletingIds.contains(id)) {
      return;
    }

    setState(() {
      _deletingIds.add(id);
    });

    try {
      await _service.deleteDraft(id: id, headers: widget.headers);

      if (!mounted) {
        return;
      }

      setState(() {
        _drafts = _drafts.where((draft) => draft.id != id).toList();
        _deletingIds.remove(id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft deleted successfully.')),
      );
    } catch (error) {
      if (mounted) {
        setState(() {
          _deletingIds.remove(id);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to delete draft: $error')),
        );
      }
    }
  }

  void _handleSelectDraft(PurchaseOrderDraft draft) {
    if (_deletingIds.contains(draft.id)) {
      return;
    }
    Navigator.of(context).pop(draft.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Purchase Order Drafts'),
      contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
      content: SizedBox(
        width: 720,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 540),
          child: _buildContent(theme),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Close'),
        ),
      ],
    );
  }

  Widget _buildContent(ThemeData theme) {
    if (_error != null) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              _error!,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.error,
              ),
            ),
          ),
          TextButton.icon(
            onPressed: () => _loadDrafts(reset: true),
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      );
    }

    if (_isLoading && _drafts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_drafts.isEmpty) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.description_outlined, size: 48),
          SizedBox(height: 12),
          Text('No purchase order drafts available.'),
        ],
      );
    }

    return Column(
      children: [
        _DraftHeader(theme: theme),
        const Divider(height: 0),
        Expanded(
          child: ListView.separated(
            itemBuilder: (context, index) {
              final draft = _drafts[index];
              final isDeleting = _deletingIds.contains(draft.id);
              return _DraftRow(
                draft: draft,
                isDeleting: isDeleting,
                onDelete: () => _deleteDraft(draft.id),
                onTap: () => _handleSelectDraft(draft),
              );
            },
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemCount: _drafts.length,
          ),
        ),
        if (_nextPage != null) ...[
          const Divider(height: 0),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.tonalIcon(
              onPressed: _isLoading ? null : () => _loadDrafts(),
              icon: _isLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.expand_more),
              label: const Text('Load more drafts'),
            ),
          ),
        ],
      ],
    );
  }
}

class _DraftHeader extends StatelessWidget {
  const _DraftHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontWeight: FontWeight.w600,
    );

    return Container(
      color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          _DraftCell(label: 'Order Name', flex: 4, style: headerStyle),
          _DraftCell(label: 'Order Date', flex: 3, style: headerStyle),
          _DraftCell(label: 'Vendor', flex: 3, style: headerStyle),
          SizedBox(
            width: 88,
            child: Text(
              'Action',
              style: headerStyle,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _DraftRow extends StatelessWidget {
  const _DraftRow({
    required this.draft,
    required this.isDeleting,
    required this.onDelete,
    required this.onTap,
  });

  final PurchaseOrderDraft draft;
  final bool isDeleting;
  final VoidCallback onDelete;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateText = DateFormat.yMMMd().format(draft.orderDate);
    final vendor = draft.vendorName?.isNotEmpty == true ? draft.vendorName! : '—';

    return InkWell(
      onTap: isDeleting ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _DraftCell(
              label: draft.orderName.isEmpty ? 'Untitled draft' : draft.orderName,
              flex: 4,
            ),
            _DraftCell(label: dateText, flex: 3),
            _DraftCell(label: vendor, flex: 3),
            SizedBox(
              width: 88,
              child: Center(
                child: IconButton(
                  icon: isDeleting
                      ? const SizedBox(
                          height: 18,
                          width: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                  onPressed: isDeleting ? null : onDelete,
                  tooltip: 'Delete draft',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DraftCell extends StatelessWidget {
  const _DraftCell({required this.label, required this.flex, this.style});

  final String label;
  final int flex;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.fade,
        softWrap: false,
        style: style ?? Theme.of(context).textTheme.bodyMedium,
      ),
    );
  }
}
