import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import '../services/accounts_service.dart';

class AccountsTab extends StatefulWidget {
  const AccountsTab({super.key});

  @override
  State<AccountsTab> createState() => _AccountsTabState();
}

class _AccountsTabState extends State<AccountsTab> {
  final _service = AccountsService();
  final _scrollController = ScrollController();
  final _horizontalController = ScrollController();
  final _accounts = <Account>[];
  final _accountNamesById = <String, String>{};

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
      final result = await _service.fetchAccounts(
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
          _accounts
            ..clear()
            ..addAll(result.accounts);
          _accountNamesById.clear();
        } else {
          _accounts.addAll(result.accounts);
        }

        _mergeAccountNames(result.namesById);

        final uniqueAccounts = <String, Account>{
          for (final account in _accounts) account.id: account,
        };
        _accounts
          ..clear()
          ..addAll(uniqueAccounts.values)
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );
        _error = null;
        _hasMore = result.hasMore;
        _nextPage = result.hasMore ? pageToLoad + 1 : pageToLoad;
      });
    } on AccountsException catch (error) {
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
          final maxWidth = constraints.maxWidth.isFinite ? constraints.maxWidth : _minTableWidth;
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
                  itemCount: _accounts.length + 2,
                  itemBuilder: (context, index) {
                    if (index == 0) {
                      return _AccountsHeader(theme: theme);
                    }

                    final dataIndex = index - 1;
                    if (dataIndex < _accounts.length) {
                      final account = _accounts[dataIndex];
                      return _AccountsRow(
                        account: account,
                        theme: theme,
                        showTopBorder: dataIndex == 0,
                        parentName: _resolveParentName(account),
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

  String _resolveParentName(Account account) {
    final parentId = account.parentAccountId;
    if (parentId == null) {
      return '—';
    }
    final trimmed = parentId.trim();
    if (trimmed.isEmpty || trimmed == '0') {
      return '—';
    }
    return _accountNamesById[trimmed] ?? '—';
  }

  void _mergeAccountNames(Map<String, String> names) {
    for (final entry in names.entries) {
      final key = entry.key.trim();
      if (key.isEmpty) {
        continue;
      }
      _accountNamesById[key] = entry.value;
    }
  }

  Widget _buildFooter(ThemeData theme) {
    if (_isLoading && _accounts.isEmpty) {
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
              onPressed: () => _fetchPage(reset: _accounts.isEmpty),
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_accounts.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        child: Column(
          children: [
            Icon(Icons.account_balance_outlined,
                size: 48, color: theme.colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'No accounts available.',
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
            'Scroll to load more accounts…',
            style: theme.textTheme.bodySmall,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

class _AccountsHeader extends StatelessWidget {
  const _AccountsHeader({required this.theme});

  final ThemeData theme;

  static const _columnFlex = [4, 3, 3, 3, 2];

  @override
  Widget build(BuildContext context) {
    final surface = theme.colorScheme.surfaceVariant.withOpacity(0.6);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      color: surface,
      child: Row(
        children: [
          _HeaderCell('Name', flex: _columnFlex[0], theme: theme),
          _HeaderCell('Parent Account', flex: _columnFlex[1], theme: theme),
          _HeaderCell('Type', flex: _columnFlex[2], theme: theme),
          _HeaderCell('Detail Type', flex: _columnFlex[3], theme: theme),
          _HeaderCell('Primary Balance', flex: _columnFlex[4], theme: theme, textAlign: TextAlign.end),
        ],
      ),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  const _HeaderCell(this.label, {required this.flex, required this.theme, this.textAlign});

  final String label;
  final int flex;
  final ThemeData theme;
  final TextAlign? textAlign;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        textAlign: textAlign ?? TextAlign.start,
        style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w600),
      ),
    );
  }
}

class _AccountsRow extends StatelessWidget {
  const _AccountsRow({
    required this.account,
    required this.theme,
    required this.showTopBorder,
    required this.parentName,
  });

  final Account account;
  final ThemeData theme;
  final bool showTopBorder;
  final String parentName;

  static const _columnFlex = [4, 3, 3, 3, 2];

  @override
  Widget build(BuildContext context) {
    final borderColor = theme.dividerColor.withOpacity(0.6);
    final background = theme.colorScheme.surfaceVariant.withOpacity(0.3);

    return Container(
      decoration: BoxDecoration(
        color: background,
        border: Border(
          top: showTopBorder ? BorderSide(color: borderColor) : BorderSide.none,
          bottom: BorderSide(color: borderColor),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
      child: Row(
        children: [
          _DataCell(
            account.name,
            flex: _columnFlex[0],
            indent: account.hasParent ? 24 : 0,
          ),
          _DataCell(parentName, flex: _columnFlex[1]),
          _DataCell(account.typeName ?? '—', flex: _columnFlex[2]),
          _DataCell(account.detailTypeName ?? '—', flex: _columnFlex[3]),
          _DataCell(account.balance, flex: _columnFlex[4], textAlign: TextAlign.end),
        ],
      ),
    );
  }
}

class _DataCell extends StatelessWidget {
  const _DataCell(
    this.value, {
    required this.flex,
    this.textAlign,
    this.indent = 0,
  });

  final String value;
  final int flex;
  final TextAlign? textAlign;
  final double indent;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: EdgeInsets.only(left: indent),
        child: Text(
          value,
          textAlign: textAlign ?? TextAlign.start,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
