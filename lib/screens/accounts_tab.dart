import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/accounts_service.dart';

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  AccountsService? _service;
  final _scrollController = ScrollController();

  final List<Account> _accounts = [];

  bool _isLoading = false;
  bool _hasMore = true;
  int _nextPage = 1;
  String? _errorMessage;
  bool _serviceInitialized = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadMore());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_serviceInitialized) {
      final appState = AppStateScope.of(context);
      _service = AccountsService(client: appState.authenticatedClient);
      _serviceInitialized = true;
    }
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
        _accounts.clear();
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

    final service = _service;
    if (service == null) {
      setState(() {
        _isLoading = false;
      });
      return;
    }

    final appState = AppStateScope.of(context);
    final headers = await appState.buildAuthHeaders();

    try {
      final page = await service.fetchAccounts(
        page: _nextPage,
        headers: headers.isEmpty ? null : headers,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _accounts.addAll(page.accounts);
        _accounts.sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );
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

    if (_accounts.isEmpty && _isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_accounts.isEmpty && _errorMessage != null) {
      return _ErrorState(message: _errorMessage!, onRetry: () => _loadMore(reset: true));
    }

    if (_accounts.isEmpty) {
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
                final account = _accounts[index];
                return _AccountTile(
                  account: account,
                  theme: theme,
                  isFirst: index == 0,
                );
              },
              childCount: _accounts.length,
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
        child: _AccountsColumnHeader(theme: theme),
      ),
    );
  }

  @override
  bool shouldRebuild(covariant _StickyTableHeaderDelegate oldDelegate) {
    return oldDelegate.theme != theme;
  }
}

class _AccountsColumnHeader extends StatelessWidget {
  const _AccountsColumnHeader({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final textStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: _ScrollableTableRow(
        children: [
          _TableHeaderCell(label: 'Name', flex: _nameColumnFlex, style: textStyle),
          _TableHeaderCell(
            label: 'Parent Account',
            flex: _parentAccountColumnFlex,
            style: textStyle,
          ),
          _TableHeaderCell(label: 'Type', flex: _typeColumnFlex, style: textStyle),
          _TableHeaderCell(label: 'Detail Type', flex: _detailTypeColumnFlex, style: textStyle),
          _TableHeaderCell(
            label: 'Primary Balance',
            flex: _balanceColumnFlex,
            style: textStyle,
            textAlign: TextAlign.right,
          ),
        ],
      ),
    );
  }
}

class _AccountTile extends StatefulWidget {
  const _AccountTile({
    required this.account,
    required this.theme,
    required this.isFirst,
  });

  final Account account;
  final ThemeData theme;
  final bool isFirst;

  @override
  State<_AccountTile> createState() => _AccountTileState();
}

class _AccountTileState extends State<_AccountTile> {
  bool _hovering = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final baseColor = Color.lerp(
      theme.colorScheme.surfaceVariant,
      theme.colorScheme.surface,
      0.75,
    )!;
    final hoverColor = Color.alphaBlend(
      theme.colorScheme.primary.withOpacity(0.04),
      baseColor,
    );
    final borderColor = theme.colorScheme.outline.withOpacity(0.6);
    final onSurface = theme.colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovering = true),
      onExit: (_) => setState(() => _hovering = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        decoration: BoxDecoration(
          color: _hovering ? hoverColor : baseColor,
          border: Border(
            top: widget.isFirst
                ? BorderSide(color: borderColor, width: 1)
                : BorderSide.none,
            bottom: BorderSide(color: borderColor, width: 1),
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: _ScrollableTableRow(
          children: [
            _TableDataCell(
              flex: _nameColumnFlex,
              child: Text(
                widget.account.name.isNotEmpty ? widget.account.name : '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _parentAccountColumnFlex,
              child: Text(
                widget.account.parentAccount.isNotEmpty
                    ? widget.account.parentAccount
                    : '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withOpacity(0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _typeColumnFlex,
              child: Text(
                widget.account.type.isNotEmpty ? widget.account.type : '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withOpacity(0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _detailTypeColumnFlex,
              child: Text(
                widget.account.detailType.isNotEmpty ? widget.account.detailType : '—',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: onSurface.withOpacity(0.85),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            _TableDataCell(
              flex: _balanceColumnFlex,
              alignment: Alignment.centerRight,
              child: Text(
                widget.account.formattedBalance,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: onSurface.withOpacity(0.9),
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.account_balance_outlined, size: 64, color: theme.colorScheme.primary),
        const SizedBox(height: 16),
        Text(
          'No accounts found',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(
          'Pull down to refresh and check again.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurface.withOpacity(0.7),
          ),
          textAlign: TextAlign.center,
        ),
      ],
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 64, color: theme.colorScheme.error),
            const SizedBox(height: 16),
            Text(
              'Unable to load accounts',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadMoreError extends StatelessWidget {
  const _LoadMoreError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          Text(
            'Something went wrong while loading more accounts.',
            style: theme.textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('Retry'),
          ),
        ],
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
    default:
      return Alignment.centerLeft;
  }
}

const int _nameColumnFlex = 2;
const int _parentAccountColumnFlex = 2;
const int _typeColumnFlex = 1;
const int _detailTypeColumnFlex = 2;
const int _balanceColumnFlex = 1;
const double _tableMinimumWidth = 720;
const double _tableHeaderHeight = 56;
