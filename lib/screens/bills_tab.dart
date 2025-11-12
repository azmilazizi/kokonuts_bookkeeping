import 'dart:async';

import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/bills_service.dart';
import '../widgets/sortable_header_cell.dart';

enum BillsSortColumn { vendor, billDate, dueDate, status, total }

class BillsTab extends StatefulWidget {
  const BillsTab({super.key});

  @override
  State<BillsTab> createState() => _BillsTabState();
}

class _BillsTabState extends State<BillsTab> {
  final _service = BillsService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _bills = <Bill>[];
  final _vendorNames = <String, String?>{};

  BillsSortColumn _sortColumn = BillsSortColumn.billDate;
  bool _sortAscending = false;

  static const _perPage = 20;
  static const double _minTableWidth = 720;

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
      final result = await _service.fetchBills(
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
          _bills
            ..clear()
            ..addAll(result.bills);
        } else {
          _bills.addAll(result.bills);
        }
        _applySorting();
        _error = null;
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });

      final vendorHeaders = {
        'Accept': 'application/json',
        'authtoken': authtokenHeader,
        'Authorization': normalizedAuth,
      };
      final vendorIds = result.bills
          .map((bill) => bill.vendorId)
          .where((id) => id.isNotEmpty && !_vendorNames.containsKey(id))
          .toSet();

      for (final vendorId in vendorIds) {
        unawaited(_loadVendorName(vendorId, vendorHeaders));
      }
    } on BillsException catch (error) {
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

  Future<void> _loadVendorName(
      String vendorId, Map<String, String> headers) async {
    try {
      final name = await _service.resolveVendorName(
        vendorId: vendorId,
        headers: headers,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _vendorNames[vendorId] = name ?? 'Unknown vendor';
        if (_sortColumn == BillsSortColumn.vendor) {
          _applySorting();
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _vendorNames[vendorId] = 'Unknown vendor';
        if (_sortColumn == BillsSortColumn.vendor) {
          _applySorting();
        }
      });
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
                  itemCount: _bills.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _BillsHeader(
                        theme: theme,
                        sortColumn: _sortColumn,
                        sortAscending: _sortAscending,
                        onSort: _handleSort,
                      );
                    }

                    final dataIndex = index - 1;
                    if (dataIndex < _bills.length) {
                      final bill = _bills[dataIndex];
                      return _BillRow(
                        bill: bill,
                        vendorName: _vendorLabel(bill),
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

  void _handleSort(BillsSortColumn column) {
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
    _bills.sort(_compareBills);
  }

  int _compareBills(Bill a, Bill b) {
    final primary = _rawCompareBills(a, b);
    if (primary != 0) {
      return _sortAscending ? primary : -primary;
    }

    final idCompare = a.id.toLowerCase().compareTo(b.id.toLowerCase());
    return _sortAscending ? idCompare : -idCompare;
  }

  int _rawCompareBills(Bill a, Bill b) {
    switch (_sortColumn) {
      case BillsSortColumn.vendor:
        return _vendorLabel(a)
            .toLowerCase()
            .compareTo(_vendorLabel(b).toLowerCase());
      case BillsSortColumn.billDate:
        final leftDate = a.billDate;
        final rightDate = b.billDate;
        if (leftDate == null && rightDate == null) {
          return 0;
        }
        if (leftDate == null) {
          return -1;
        }
        if (rightDate == null) {
          return 1;
        }
        return leftDate.compareTo(rightDate);
      case BillsSortColumn.dueDate:
        final left = a.dueDate;
        final right = b.dueDate;
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
      case BillsSortColumn.status:
        return a.status.code.compareTo(b.status.code);
      case BillsSortColumn.total:
        final left = a.totalAmount ?? 0;
        final right = b.totalAmount ?? 0;
        return left.compareTo(right);
    }
  }

  String _vendorLabel(Bill bill) {
    return _vendorNames[bill.vendorId] ?? 'Loading vendor…';
  }

  Widget _buildFooter(ThemeData theme) {
    if (_isLoading && _bills.isEmpty) {
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
              onPressed: () => _fetchPage(reset: _bills.isEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_bills.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.receipt_long_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No bills available.',
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
            'Scroll to load more bills…',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _BillsHeader extends StatelessWidget {
  const _BillsHeader({
    required this.theme,
    required this.sortColumn,
    required this.sortAscending,
    required this.onSort,
  });

  final ThemeData theme;
  final BillsSortColumn sortColumn;
  final bool sortAscending;
  final ValueChanged<BillsSortColumn> onSort;

  static const _columnFlex = [4, 3, 3, 3, 2, 2];

  @override
  Widget build(BuildContext context) {
    final surface = theme.colorScheme.surfaceVariant.withOpacity(0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: surface,
      child: Row(
        children: [
          SortableHeaderCell(
            label: 'Vendor',
            flex: _columnFlex[0],
            theme: theme,
            isActive: sortColumn == BillsSortColumn.vendor,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.vendor),
          ),
          SortableHeaderCell(
            label: 'Date',
            flex: _columnFlex[1],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == BillsSortColumn.billDate,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.billDate),
          ),
          SortableHeaderCell(
            label: 'Due Date',
            flex: _columnFlex[2],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == BillsSortColumn.dueDate,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.dueDate),
          ),
          SortableHeaderCell(
            label: 'Status',
            flex: _columnFlex[3],
            theme: theme,
            textAlign: TextAlign.center,
            isActive: sortColumn == BillsSortColumn.status,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.status),
          ),
          SortableHeaderCell(
            label: 'Total',
            flex: _columnFlex[4],
            theme: theme,
            textAlign: TextAlign.end,
            isActive: sortColumn == BillsSortColumn.total,
            ascending: sortAscending,
            onTap: () => onSort(BillsSortColumn.total),
          ),
          SortableHeaderCell(
            label: 'Actions',
            flex: _columnFlex[5],
            theme: theme,
            textAlign: TextAlign.center,
            ascending: sortAscending,
          ),
        ],
      ),
    );
  }
}

class _BillRow extends StatefulWidget {
  const _BillRow({
    required this.bill,
    required this.vendorName,
    required this.theme,
    required this.showTopBorder,
  });

  final Bill bill;
  final String vendorName;
  final ThemeData theme;
  final bool showTopBorder;

  @override
  State<_BillRow> createState() => _BillRowState();
}

class _BillRowState extends State<_BillRow> {
  bool _hovering = false;

  static const _columnFlex = [4, 3, 3, 3, 2, 2];

  @override
  Widget build(BuildContext context) {
    final borderColor = widget.theme.dividerColor.withOpacity(0.6);
    final baseBackground = widget.theme.colorScheme.surfaceVariant.withOpacity(0.25);
    final hoverBackground = widget.theme.colorScheme.surfaceVariant.withOpacity(0.45);

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
            _DataCell(widget.vendorName, flex: _columnFlex[0]),
            _DataCell(
              widget.bill.formattedDate,
              flex: _columnFlex[1],
              textAlign: TextAlign.center,
            ),
            _DataCell(
              widget.bill.formattedDueDate,
              flex: _columnFlex[2],
              textAlign: TextAlign.center,
            ),
            Expanded(
              flex: _columnFlex[3],
              child: Align(
                alignment: Alignment.center,
                child: _StatusPill(status: widget.bill.status, theme: widget.theme),
              ),
            ),
            _DataCell(
              widget.bill.totalLabel,
              flex: _columnFlex[4],
              textAlign: TextAlign.end,
              style: widget.theme.textTheme.bodyMedium?.copyWith(
                color: widget.theme.colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            Expanded(
              flex: _columnFlex[5],
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

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
