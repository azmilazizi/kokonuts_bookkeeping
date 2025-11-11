import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/purchase_order_service.dart';

class PurchaseOrdersTab extends StatefulWidget {
  const PurchaseOrdersTab({super.key});

  @override
  State<PurchaseOrdersTab> createState() => _PurchaseOrdersTabState();
}

class _PurchaseOrdersTabState extends State<PurchaseOrdersTab> {
  final _service = PurchaseOrderService();
  final _scrollController = ScrollController();

  final List<PurchaseOrder> _orders = [];

  bool _isLoading = false;
  bool _hasMore = true;
  int _nextPage = 1;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) {
      return;
    }
    final threshold = 200;
    final position = _scrollController.position;
    if (position.pixels + threshold >= position.maxScrollExtent) {
      _loadMore();
    }
  }

  Future<void> _loadMore({bool reset = false}) async {
    if (_isLoading) {
      return;
    }
    if (!reset && !_hasMore) {
      return;
    }

    final previousPage = _nextPage;
    if (reset) {
      setState(() {
        _orders.clear();
        _nextPage = 1;
        _hasMore = true;
        _errorMessage = null;
        _isLoading = true;
      });
    } else {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    final appState = AppStateScope.of(context);
    try {
      final headers = await appState.buildAuthHeaders();
      final page = await _service.fetchPurchaseOrders(headers: headers, page: _nextPage);
      if (!mounted) {
        return;
      }
      setState(() {
        _orders.addAll(page.orders);
        _hasMore = page.hasMore;
        if (page.nextPage != null) {
          _nextPage = page.nextPage!;
        } else {
          _nextPage = previousPage + 1;
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _errorMessage = error.toString();
        _nextPage = previousPage;
      });
    } finally {
      if (!mounted) {
        return;
      }
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadMore(reset: true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_orders.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_orders.isEmpty && _errorMessage != null) {
      return _ErrorState(message: _errorMessage!, onRetry: () => _loadMore(reset: true));
    }

    if (_orders.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        child: ListView(
          controller: _scrollController,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 32),
          children: const [
            _EmptyState(),
          ],
        ),
      );
    }

    final entries = _buildEntries();

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView.builder(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        itemCount: entries.length + (_showBottomIndicator ? 1 : 0),
        itemBuilder: (context, index) {
          final isBottomIndicator = index >= entries.length;
          if (isBottomIndicator) {
            if (_errorMessage != null) {
              return _LoadMoreError(onRetry: _loadMore);
            }
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            );
          }

          final entry = entries[index];
          if (entry.isHeader) {
            return _DateHeader(label: entry.dateLabel!);
          }

          return _PurchaseOrderTile(order: entry.order!, theme: theme);
        },
      ),
    );
  }

  bool get _showBottomIndicator => _isLoading || _errorMessage != null;

  List<_PurchaseOrderListEntry> _buildEntries() {
    final entries = <_PurchaseOrderListEntry>[];
    String? lastLabel;

    for (final order in _orders) {
      final label = order.dateLabel;
      if (label != null) {
        if (label != lastLabel) {
          entries.add(_PurchaseOrderListEntry.header(label));
          lastLabel = label;
        }
      } else {
        lastLabel = null;
      }

      entries.add(_PurchaseOrderListEntry.order(order));
    }

    return entries;
  }
}

class _PurchaseOrderListEntry {
  const _PurchaseOrderListEntry.header(this.dateLabel)
      : order = null,
        isHeader = true;

  const _PurchaseOrderListEntry.order(this.order)
      : dateLabel = null,
        isHeader = false;

  final PurchaseOrder? order;
  final String? dateLabel;
  final bool isHeader;
}

class _PurchaseOrderTile extends StatelessWidget {
  const _PurchaseOrderTile({required this.order, required this.theme});

  final PurchaseOrder order;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final onSurface = theme.colorScheme.onSurface;

    final tileColor = theme.colorScheme.surfaceVariant;

    return Container(
      color: tileColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  order.orderNumber,
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: onSurface),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  order.orderName,
                  style: theme.textTheme.bodyMedium?.copyWith(color: onSurface.withOpacity(0.8)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Text(
            order.formattedTotal,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.error,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  const _DateHeader({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
      child: Text(
        label,
        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
        textAlign: TextAlign.left,
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: theme.colorScheme.error, size: 48),
          const SizedBox(height: 16),
          Text(
            'Unable to load purchase orders.',
            style: theme.textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.onRetry});

  final Future<void> Function({bool reset}) onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          Text(
            'Unable to load more orders.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            onPressed: () => onRetry(reset: false),
            icon: const Icon(Icons.refresh),
            label: const Text('Try again'),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inbox_outlined, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            'No purchase orders yet',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to refresh or create a new purchase order.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
