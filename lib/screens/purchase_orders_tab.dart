import 'dart:math' as math;

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
          switch (entry.type) {
            case _PurchaseOrderEntryType.dateHeader:
              return _DateHeader(label: entry.dateLabel!);
            case _PurchaseOrderEntryType.columnHeader:
              return _PurchaseOrderColumnHeader(theme: theme);
            case _PurchaseOrderEntryType.order:
              return _PurchaseOrderTile(order: entry.order!, theme: theme);
          }
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
          entries.add(_PurchaseOrderListEntry.dateHeader(label));
          entries.add(_PurchaseOrderListEntry.columnHeader());
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

enum _PurchaseOrderEntryType { dateHeader, columnHeader, order }

class _PurchaseOrderListEntry {
  const _PurchaseOrderListEntry._({
    required this.type,
    this.order,
    this.dateLabel,
  });

  factory _PurchaseOrderListEntry.dateHeader(String label) =>
      _PurchaseOrderListEntry._(
        type: _PurchaseOrderEntryType.dateHeader,
        dateLabel: label,
      );

  factory _PurchaseOrderListEntry.columnHeader() =>
      const _PurchaseOrderListEntry._(type: _PurchaseOrderEntryType.columnHeader);

  factory _PurchaseOrderListEntry.order(PurchaseOrder order) =>
      _PurchaseOrderListEntry._(
        type: _PurchaseOrderEntryType.order,
        order: order,
      );

  final _PurchaseOrderEntryType type;
  final PurchaseOrder? order;
  final String? dateLabel;
}

class _PurchaseOrderColumnHeader extends StatelessWidget {
  const _PurchaseOrderColumnHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final borderColor = theme.colorScheme.outline.withOpacity(0.4);
    final textStyle = theme.textTheme.labelLarge?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(color: borderColor, width: 1),
          bottom: BorderSide(color: borderColor, width: 1),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: _ScrollableTableRow(
        children: [
          _TableHeaderCell(
            label: 'Order Number',
            flex: _orderNumberColumnFlex,
            style: textStyle,
          ),
          _TableHeaderCell(
            label: 'Order Name',
            flex: _orderNameColumnFlex,
            style: textStyle,
          ),
          _TableHeaderCell(
            label: 'Total',
            flex: _totalColumnFlex,
            style: textStyle,
            textAlign: TextAlign.right,
          ),
          _TableHeaderCell(
            label: 'Actions',
            flex: _actionsColumnFlex,
            style: textStyle,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _PurchaseOrderTile extends StatefulWidget {
  const _PurchaseOrderTile({required this.order, required this.theme});

  final PurchaseOrder order;
  final ThemeData theme;

  @override
  State<_PurchaseOrderTile> createState() => _PurchaseOrderTileState();
}

class _PurchaseOrderTileState extends State<_PurchaseOrderTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final baseColor = Color.lerp(
      theme.colorScheme.surfaceVariant,
      theme.colorScheme.surface,
      0.7,
    )!;
    final hoverColor = Color.alphaBlend(
      theme.colorScheme.primary.withOpacity(0.04),
      baseColor,
    );
    final borderColor = theme.colorScheme.outline.withOpacity(0.6);

    final onSurface = theme.colorScheme.onSurface;
    final actionButtonStyle = OutlinedButton.styleFrom(
      minimumSize: const Size(40, 40),
      padding: const EdgeInsets.all(8),
      visualDensity: VisualDensity.compact,
    );

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovering ? hoverColor : baseColor,
          border: Border(
            bottom: BorderSide(color: borderColor, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: _ScrollableTableRow(
          children: [
            _TableDataCell(
              flex: _orderNumberColumnFlex,
              child: Text(
                widget.order.orderNumber,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _orderNameColumnFlex,
              child: Text(
                widget.order.orderName,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withOpacity(0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _totalColumnFlex,
              alignment: Alignment.centerRight,
              child: Text(
                widget.order.formattedTotal,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.error,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _actionsColumnFlex,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: 'View detail',
                    child: OutlinedButton(
                      onPressed: () {},
                      style: actionButtonStyle,
                      child: const Icon(Icons.visibility_outlined),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Tooltip(
                    message: 'View payment',
                    child: OutlinedButton(
                      onPressed: () {},
                      style: actionButtonStyle,
                      child: const Icon(Icons.payment),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

const int _orderNumberColumnFlex = 1;
const int _orderNameColumnFlex = 1;
const int _totalColumnFlex = 1;
const int _actionsColumnFlex = 1;
const double _tableMinimumWidth = 720;

class _ScrollableTableRow extends StatelessWidget {
  const _ScrollableTableRow({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final tableWidth = constraints.maxWidth.isFinite
            ? math.max(constraints.maxWidth, _tableMinimumWidth)
            : _tableMinimumWidth;
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: BoxConstraints(minWidth: tableWidth),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: children,
            ),
          ),
        );
      },
    );
  }
}

class _TableHeaderCell extends StatelessWidget {
  const _TableHeaderCell({
    required this.label,
    required this.flex,
    this.style,
    this.textAlign = TextAlign.left,
  });

  final String label;
  final int flex;
  final TextStyle? style;
  final TextAlign textAlign;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: _alignmentForTextAlign(textAlign),
          child: Text(
            label,
            style: style,
            textAlign: textAlign,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}

class _TableDataCell extends StatelessWidget {
  const _TableDataCell({
    required this.child,
    required this.flex,
    this.alignment = Alignment.centerLeft,
  });

  final Widget child;
  final int flex;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Align(
          alignment: alignment,
          child: child,
        ),
      ),
    );
  }
}

Alignment _alignmentForTextAlign(TextAlign textAlign) {
  switch (textAlign) {
    case TextAlign.center:
      return Alignment.center;
    case TextAlign.right:
      return Alignment.centerRight;
    case TextAlign.left:
    case TextAlign.start:
      return Alignment.centerLeft;
    case TextAlign.end:
      return Alignment.centerRight;
    case TextAlign.justify:
      return Alignment.centerLeft;
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
