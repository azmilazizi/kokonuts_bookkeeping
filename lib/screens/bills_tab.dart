import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/bills_service.dart';

class BillsTab extends StatefulWidget {
  const BillsTab({super.key});

  @override
  State<BillsTab> createState() => _BillsTabState();
}

class _BillsTabState extends State<BillsTab> {
  final _service = BillsService();
  final _scrollController = ScrollController();

  final List<Bill> _bills = [];

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
    const threshold = 200;
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
        _bills.clear();
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
      final page = await _service.fetchBills(headers: headers, page: _nextPage);
      if (!mounted) {
        return;
      }
      setState(() {
        _bills.addAll(page.bills);
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

    if (_bills.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_bills.isEmpty && _errorMessage != null) {
      return _ErrorState(message: _errorMessage!, onRetry: () => _loadMore(reset: true));
    }

    if (_bills.isEmpty) {
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
      child: CustomScrollView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPersistentHeader(
            pinned: true,
            delegate: _StickyTableHeaderDelegate(theme: theme),
          ),
          SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                final entry = entries[index];
                switch (entry.type) {
                  case _BillEntryType.dateHeader:
                    return _DateHeader(label: entry.dateLabel!);
                  case _BillEntryType.bill:
                    return _BillTile(
                      bill: entry.bill!,
                      theme: theme,
                      isFirstInSection: entry.isFirstInSection,
                    );
                }
              },
              childCount: entries.length,
            ),
          ),
          if (_showBottomIndicator)
            SliverToBoxAdapter(
              child: _errorMessage != null
                  ? _LoadMoreError(onRetry: _loadMore)
                  : const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: CircularProgressIndicator()),
                    ),
            ),
        ],
      ),
    );
  }

  bool get _showBottomIndicator => _isLoading || _errorMessage != null;

  List<_BillListEntry> _buildEntries() {
    final entries = <_BillListEntry>[];
    String? lastLabel;
    var nextIsFirstInSection = true;

    for (final bill in _bills) {
      final label = bill.dateLabel;
      if (label != null) {
        if (label != lastLabel) {
          entries.add(_BillListEntry.dateHeader(label));
          lastLabel = label;
          nextIsFirstInSection = true;
        }
      } else {
        if (lastLabel != null) {
          lastLabel = null;
          nextIsFirstInSection = true;
        }
      }

      entries.add(
        _BillListEntry.bill(
          bill,
          isFirstInSection: nextIsFirstInSection,
        ),
      );
      nextIsFirstInSection = false;
    }

    return entries;
  }
}

enum _BillEntryType { dateHeader, bill }

class _BillListEntry {
  const _BillListEntry._({
    required this.type,
    this.bill,
    this.dateLabel,
    this.isFirstInSection = false,
  });

  factory _BillListEntry.dateHeader(String label) => _BillListEntry._(
        type: _BillEntryType.dateHeader,
        dateLabel: label,
      );

  factory _BillListEntry.bill(
    Bill bill, {
    required bool isFirstInSection,
  }) =>
      _BillListEntry._(
        type: _BillEntryType.bill,
        bill: bill,
        isFirstInSection: isFirstInSection,
      );

  final _BillEntryType type;
  final Bill? bill;
  final String? dateLabel;
  final bool isFirstInSection;
}

class _BillColumnHeader extends StatelessWidget {
  const _BillColumnHeader({required this.theme});

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
          bottom: BorderSide.none,
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: _ScrollableTableRow(
        children: [
          _TableHeaderCell(
            label: 'Vendor',
            flex: _vendorColumnFlex,
            style: textStyle,
          ),
          _TableHeaderCell(
            label: 'Due Date',
            flex: _dueDateColumnFlex,
            style: textStyle,
          ),
          _TableHeaderCell(
            label: 'Status',
            flex: _statusColumnFlex,
            style: textStyle,
            textAlign: TextAlign.center,
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

class _BillTile extends StatefulWidget {
  const _BillTile({
    required this.bill,
    required this.theme,
    required this.isFirstInSection,
  });

  final Bill bill;
  final ThemeData theme;
  final bool isFirstInSection;

  @override
  State<_BillTile> createState() => _BillTileState();
}

class _BillTileState extends State<_BillTile> {
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
    final statusAppearance = _resolveStatusAppearance(theme);

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovering ? hoverColor : baseColor,
          border: Border(
            top: widget.isFirstInSection
                ? BorderSide(color: borderColor, width: 1)
                : BorderSide.none,
            bottom: BorderSide(color: borderColor, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: _ScrollableTableRow(
          children: [
            _TableDataCell(
              flex: _vendorColumnFlex,
              child: Text(
                widget.bill.vendorName.isNotEmpty
                    ? widget.bill.vendorName
                    : '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _dueDateColumnFlex,
              child: Text(
                widget.bill.dueDateLabel ?? '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withOpacity(0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _statusColumnFlex,
              alignment: Alignment.center,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: statusAppearance.backgroundColor,
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusAppearance.borderColor, width: 1),
                ),
                child: Text(
                  statusAppearance.label,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: statusAppearance.foregroundColor,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            _TableDataCell(
              flex: _totalColumnFlex,
              alignment: Alignment.centerRight,
              child: Text(
                widget.bill.formattedTotal,
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
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  _StatusAppearance _resolveStatusAppearance(ThemeData theme) {
    final status = widget.bill.status;
    final label = widget.bill.statusLabel;

    Color baseColor;
    switch (status) {
      case 0:
        baseColor = theme.colorScheme.error;
        break;
      case 1:
        baseColor = const Color(0xFFF57F17); // Amber 700
        break;
      case 2:
        baseColor = const Color(0xFF2E7D32); // Green 800
        break;
      default:
        baseColor = theme.colorScheme.outline;
        break;
    }

    final isDark = theme.brightness == Brightness.dark;
    final background = baseColor.withOpacity(isDark ? 0.28 : 0.16);
    final border = baseColor.withOpacity(isDark ? 0.7 : 0.35);

    return _StatusAppearance(
      label: label,
      foregroundColor: baseColor,
      backgroundColor: background,
      borderColor: border,
    );
  }
}

class _StatusAppearance {
  const _StatusAppearance({
    required this.label,
    required this.foregroundColor,
    required this.backgroundColor,
    required this.borderColor,
  });

  final String label;
  final Color foregroundColor;
  final Color backgroundColor;
  final Color borderColor;
}

const int _vendorColumnFlex = 2;
const int _dueDateColumnFlex = 1;
const int _statusColumnFlex = 1;
const int _totalColumnFlex = 1;
const int _actionsColumnFlex = 1;
const double _tableMinimumWidth = 760;
const double _tableHeaderHeight = 56;

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
          child: SizedBox(
            width: tableWidth,
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

class _StickyTableHeaderDelegate extends SliverPersistentHeaderDelegate {
  _StickyTableHeaderDelegate({required this.theme});

  final ThemeData theme;

  @override
  double get minExtent => _tableHeaderHeight;

  @override
  double get maxExtent => _tableHeaderHeight;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    final shadowColor = theme.colorScheme.shadow.withOpacity(overlapsContent ? 0.12 : 0.0);
    return SizedBox.expand(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          boxShadow: shadowColor.opacity > 0
              ? [
                  BoxShadow(
                    color: shadowColor,
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : const [],
        ),
        child: _BillColumnHeader(theme: theme),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyTableHeaderDelegate oldDelegate) {
    return oldDelegate.theme != theme;
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
            style: style ?? Theme.of(context).textTheme.labelLarge,
            textAlign: textAlign,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ),
      ),
    );
  }
}

class _TableDataCell extends StatelessWidget {
  const _TableDataCell({
    required this.flex,
    required this.child,
    this.alignment = Alignment.centerLeft,
  });

  final int flex;
  final Widget child;
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
    case TextAlign.end:
      return Alignment.centerRight;
    case TextAlign.left:
    case TextAlign.start:
      return Alignment.centerLeft;
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
            'Unable to load bills.',
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
            'Unable to load more bills.',
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
            'No bills yet',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Pull down to refresh or create a new bill.',
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
