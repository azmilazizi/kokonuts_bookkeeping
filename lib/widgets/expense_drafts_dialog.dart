import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/expenses_service.dart';

class ExpenseDraftsDialog extends StatefulWidget {
  const ExpenseDraftsDialog({super.key, required this.headers});

  final Map<String, String> headers;

  @override
  State<ExpenseDraftsDialog> createState() => _ExpenseDraftsDialogState();
}

class _ExpenseDraftsDialogState extends State<ExpenseDraftsDialog> {
  final _service = ExpensesService();
  final _deletingIds = <String>{};

  List<Expense> _drafts = [];
  bool _isLoading = false;
  bool _hasMore = true;
  int _nextPage = 1;
  String? _error;

  static const _perPage = 20;

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
        _drafts = [];
        _nextPage = 1;
        _hasMore = true;
        _error = null;
      }
    });

    final pageToLoad = reset ? 1 : _nextPage;

    try {
      final result = await _service.fetchExpenses(
        page: pageToLoad,
        perPage: _perPage,
        headers: widget.headers,
        isDraft: true,
      );

      if (!mounted) {
        return;
      }

      setState(() {
        _drafts = [..._drafts, ...result.expenses];
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _error = error.toString();
        _hasMore = false;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _deleteDraft(Expense draft) async {
    if (_deletingIds.contains(draft.id)) {
      return;
    }

    setState(() {
      _deletingIds.add(draft.id);
    });

    try {
      await _service.deleteExpense(id: draft.id, headers: widget.headers);

      if (!mounted) {
        return;
      }

      setState(() {
        _drafts = _drafts.where((item) => item.id != draft.id).toList();
        _deletingIds.remove(draft.id);
      });

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Draft deleted successfully.')),
      );
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _deletingIds.remove(draft.id);
      });

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Failed to delete draft: $error')));
    }
  }

  void _handleSelectDraft(Expense draft) {
    if (_deletingIds.contains(draft.id)) {
      return;
    }

    Navigator.of(context).pop(draft.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: const Text('Expense Drafts'),
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
          Text('No expense drafts available.'),
        ],
      );
    }

    return Column(
      children: [
        _DraftHeader(theme: theme),
        const Divider(height: 0),
        Expanded(
          child: ListView.separated(
            itemCount: _drafts.length,
            separatorBuilder: (_, __) => const Divider(height: 0),
            itemBuilder: (context, index) {
              final draft = _drafts[index];
              final isDeleting = _deletingIds.contains(draft.id);
              return _DraftRow(
                draft: draft,
                isDeleting: isDeleting,
                onTap: () => _handleSelectDraft(draft),
                onDelete: () => _deleteDraft(draft),
              );
            },
          ),
        ),
        if (_hasMore) ...[
          const Divider(height: 0),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: FilledButton.tonalIcon(
              onPressed: _isLoading ? null : () => _loadDrafts(),
              icon: _isLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
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
          _DraftCell(label: 'Expense Name', flex: 4, style: headerStyle),
          _DraftCell(label: 'Expense Date', flex: 3, style: headerStyle),
          _DraftCell(label: 'Vendor', flex: 3, style: headerStyle),
          SizedBox(
            width: 88,
            child: Text(
              'Action',
              textAlign: TextAlign.center,
              style: headerStyle,
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
    required this.onTap,
    required this.onDelete,
  });

  final Expense draft;
  final bool isDeleting;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final dateText = draft.date == null
        ? '—'
        : DateFormat.yMMMd().format(draft.date!);
    final vendorText = draft.vendor.trim().isEmpty ? '—' : draft.vendor;
    final nameText = draft.name.trim().isEmpty ? 'Untitled draft' : draft.name;

    return InkWell(
      onTap: isDeleting ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            _DraftCell(label: nameText, flex: 4),
            _DraftCell(label: dateText, flex: 3),
            _DraftCell(label: vendorText, flex: 3),
            SizedBox(
              width: 88,
              child: Center(
                child: IconButton(
                  tooltip: 'Delete draft',
                  onPressed: isDeleting ? null : onDelete,
                  icon: isDeleting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.delete_outline),
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
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
