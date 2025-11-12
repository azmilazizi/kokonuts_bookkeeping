import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/purchase_orders_service.dart';
import '../widgets/sortable_header_cell.dart';

enum PurchaseOrderSortColumn {
  number,
  name,
  vendor,
  orderDate,
  paymentProgress,
  total,
}

class PurchaseOrdersTab extends StatefulWidget {
  const PurchaseOrdersTab({super.key});

  @override
  State<PurchaseOrdersTab> createState() => _PurchaseOrdersTabState();
}

class _PurchaseOrdersTabState extends State<PurchaseOrdersTab> {
  final _service = PurchaseOrdersService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _orders = <PurchaseOrder>[];

  PurchaseOrderSortColumn _sortColumn = PurchaseOrderSortColumn.orderDate;
  bool _sortAscending = false;

  static const _perPage = 20;
  static const double _minTableWidth = 900;

  bool _isLoading = false;
  bool _hasMore = true;
  int _nextPage = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _fetchPage(reset: true);
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_handleScroll);
    _scrollController.dispose();
    _horizontalController.dispose();
    super.dispose();
  }

  void _handleScroll() {
    if (!_scrollController.hasClients || _isLoading || !_hasMore) {
      return;
    }
    final position = _scrollController.position;
    if (position.pixels >= position.maxScrollExtent - 200) {
      _fetchPage();
    }
  }

  Future<void> _fetchPage({bool reset = false}) async {
    if (_isLoading) {
      return;
    }

    setState(() {
      _isLoading = true;
      if (reset) {
        _error = null;
        _hasMore = true;
      }
    });

    final appState = AppStateScope.of(context);
    final token = await appState.getValidAuthToken();
    if (!mounted) {
      return;
    }

    if (token == null || token.isEmpty) {
      setState(() {
        _isLoading = false;
        _error = 'You are not logged in.';
      });
      return;
    }

    final rawToken = (appState.rawAuthToken ?? token).trim();
    final sanitizedToken =
        token.replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '').trim();
    final normalizedAuth =
        sanitizedToken.isNotEmpty ? 'Bearer $sanitizedToken' : token.trim();
    final autoTokenValue = rawToken
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();

    final authtokenHeader = autoTokenValue.isNotEmpty ? autoTokenValue : sanitizedToken;

    final pageToLoad = reset ? 1 : _nextPage;

    try {
      final result = await _service.fetchPurchaseOrders(
        page: pageToLoad,
        perPage: _perPage,
        headers: {
          'Accept': 'application/json',
          'authtoken': authtokenHeader,
          'Authorization': normalizedAuth,
        },
      );

      if (!mounted) {
        return;
      }

      setState(() {
        if (reset) {
          _orders
            ..clear()
            ..addAll(result.orders);
        } else {
          _orders.addAll(result.orders);
        }
        _applySorting();
        _error = null;
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });
    } on PurchaseOrdersException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error.message;
        _hasMore = false;
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () => _fetchPage(reset: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final maxWidth =
              constraints.maxWidth.isFinite ? constraints.maxWidth : _minTableWidth;
          final tableWidth = maxWidth < _minTableWidth ? _minTableWidth : maxWidth;

          return Scrollbar(
            controller: _horizontalController,
            thumbVisibility: true,
            notificationPredicate: (notification) =>
                notification.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _horizontalController,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: tableWidth,
                child: ListView.builder(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: _orders.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _PurchaseOrdersHeader(
                        theme: theme,
                        sortColumn: _sortColumn,
                        sortAscending: _sortAscending,
                        onSort: _handleSort,
                      );
                    }

                    final dataIndex = index - 1;
                    if (dataIndex < _orders.length) {
                      final order = _orders[dataIndex];
                      return _PurchaseOrderRow(
                        order: order,
                        theme: theme,
                        showTopBorder: dataIndex == 0,
                      );
                    }

                    return _buildFooter(theme);
                  },
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  void _handleSort(PurchaseOrderSortColumn column) {
    setState(() {
      if (_sortColumn == column) {
        _sortAscending = !_sortAscending;
      } else {
        _sortColumn = column;
        _sortAscending = true;
      }
      _applySorting();
    });
  }

  void _applySorting() {
    _orders.sort(_compareOrders);
  }

  int _compareOrders(PurchaseOrder a, PurchaseOrder b) {
    final primary = _rawCompareOrders(a, b);
    if (primary != 0) {
      return _sortAscending ? primary : -primary;
    }

    final numberCompare = a.number.toLowerCase().compareTo(b.number.toLowerCase());
    if (numberCompare != 0) {
      return _sortAscending ? numberCompare : -numberCompare;
    }

    final idCompare = a.id.toLowerCase().compareTo(b.id.toLowerCase());
    return _sortAscending ? idCompare : -idCompare;
  }

  int _rawCompareOrders(PurchaseOrder a, PurchaseOrder b) {
    switch (_sortColumn) {
      case PurchaseOrderSortColumn.number:
        return a.number.toLowerCase().compareTo(b.number.toLowerCase());
      case PurchaseOrderSortColumn.name:
        return a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case PurchaseOrderSortColumn.vendor:
        return a.vendorName.toLowerCase().compareTo(b.vendorName.toLowerCase());
      case PurchaseOrderSortColumn.orderDate:
        final left = a.orderDate;
        final right = b.orderDate;
        if (left == null && right == null) {
          return 0;
        }
        if (left == null) {
          return -1;
        }
        if (right == null) {
          return 1;
        }
        return left.compareTo(right);
      case PurchaseOrderSortColumn.paymentProgress:
        final left = _paymentProgressValue(a);
        final right = _paymentProgressValue(b);
        if (left == right) {
          return 0;
        }
        return left < right ? -1 : 1;
      case PurchaseOrderSortColumn.total:
        final left = a.totalAmount ?? 0;
        final right = b.totalAmount ?? 0;
        if (left == right) {
          return 0;
        }
        return left < right ? -1 : 1;
    }
  }

  double _paymentProgressValue(PurchaseOrder order) {
    final total = order.totalAmount ?? 0;
    if (total <= 0) {
      return 0;
    }
    const paidAmount = 0.0;
    return paidAmount / total;
  }

  Widget _buildFooter(ThemeData theme) {
    if (_isLoading && _orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Center(
          child: CircularProgressIndicator(color: theme.colorScheme.primary),
        ),
      );
    }

    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          children: [
            Text(
              _error!,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () => _fetchPage(reset: _orders.isEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_orders.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.shopping_bag_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No purchase orders available.',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              'Pull to refresh to check for updates.',
              style: theme.textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasMore) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            'Scroll to load more purchase orders…',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _PurchaseOrdersHeader extends StatelessWidget {
  const _PurchaseOrdersHeader({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final PurchaseOrderSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<PurchaseOrderSortColumn> onSort;

  static const _columnFlex = [3, 4, 3, 3, 3, 2, 2];

  @override
  Widget build(BuildContext context) {
    final surface = theme.colorScheme.surfaceVariant.withOpacity(0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: surface,
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Order Number',
            flex: _columnFlex[0],
            theme: theme,
            isActive: sortColumn == PurchaseOrderSortColumn.number,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.number),
          ),
          const SizedBox(width: 12),
          SortableHeaderCell(
            label: 'Order Name',
            flex: _columnFlex[1],
            theme: theme,
            isActive: sortColumn == PurchaseOrderSortColumn.name,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.name),
          ),
          SortableHeaderCell(
            label: 'Vendor',
            flex: _columnFlex[2],
            theme: theme,
            isActive: sortColumn == PurchaseOrderSortColumn.vendor,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.vendor),
          ),
          SortableHeaderCell(
            label: 'Order Date',
            flex: _columnFlex[3],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == PurchaseOrderSortColumn.orderDate,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.orderDate),
          ),
          SortableHeaderCell(
            label: 'Payment Progress',
            flex: _columnFlex[4],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == PurchaseOrderSortColumn.paymentProgress,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.paymentProgress),
          ),
          SortableHeaderCell(
            label: 'Total',
            flex: _columnFlex[5],
            theme: theme,
            textAlign: TextAlign.end,
            isActive: sortColumn == PurchaseOrderSortColumn.total,
            ascending: sortAscending,
            onTap: () => onSort(PurchaseOrderSortColumn.total),
          ),
          SortableHeaderCell(
            label: 'Actions',
            flex: _columnFlex[6],
            theme: theme,
            textAlign: TextAlign.center,
            ascending: sortAscending,
          ),
        ],
      ),
    );
  }
}

class _PurchaseOrderRow extends StatefulWidget {
  const _PurchaseOrderRow({
    required this.order,
    required this.theme,
    required this.showTopBorder,
  });

  final PurchaseOrder order;
  final ThemeData theme;
  final bool showTopBorder;

  @override
  State<_PurchaseOrderRow> createState() => _PurchaseOrderRowState();
}

class _PurchaseOrderRowState extends State<_PurchaseOrderRow> {
  bool _hovering = false;

  static const _columnFlex = [3, 4, 3, 3, 3, 2, 2];

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.theme.dividerColor.withOpacity(0.6);
    final baseBackground = widget.theme.colorScheme.surfaceVariant.withOpacity(0.25);
    final hoverBackground = widget.theme.colorScheme.surfaceVariant.withOpacity(0.45);

    final totalAmount = widget.order.totalAmount;
    final totalLabel = widget.order.totalLabel;
    final paidAmount = 0.0;
    const paidLabel = '0';
    final paymentProgress = '$paidLabel/$totalLabel';
    final isComplete =
        totalAmount != null && totalAmount > 0 && paidAmount >= totalAmount;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovering ? hoverBackground : baseBackground,
          border: Border(
            top: widget.showTopBorder ? BorderSide(color: borderColor) : BorderSide.none,
            bottom: BorderSide(color: borderColor),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            _DataCell(widget.order.number, flex: _columnFlex[0]),
            const SizedBox(width: 12),
            _DataCell(widget.order.name, flex: _columnFlex[1]),
            _DataCell(widget.order.vendorName, flex: _columnFlex[2]),
            _DataCell(
              widget.order.formattedDate,
              flex: _columnFlex[3],
              textAlign: TextAlign.center,
            ),
            _DataCell(
              paymentProgress,
              flex: _columnFlex[4],
              textAlign: TextAlign.center,
              style: isComplete
                  ? widget.theme.textTheme.bodyMedium
                      ?.copyWith(color: widget.theme.colorScheme.error)
                  : null,
            ),
            _DataCell(
              totalLabel,
              flex: _columnFlex[5],
              textAlign: TextAlign.end,
              style: widget.theme.textTheme.bodyMedium?.copyWith(
                color: widget.theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            Expanded(
              flex: _columnFlex[6],
              child: Center(
                child: Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.visibility_outlined),
                      tooltip: 'View details',
                      onPressed: () {},
                    ),
                    IconButton(
                      icon: const Icon(Icons.payments_outlined),
                      tooltip: 'View payments',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell(
    this.value, {
    required this.flex,
    this.textAlign,
    this.style,
  });

  final String value;
  final int flex;
  final TextAlign? textAlign;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        value,
        textAlign: textAlign ?? TextAlign.start,
        overflow: TextOverflow.ellipsis,
        style: style,
      ),
    );
  }
}
