import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';
import 'purchase_orders_tab.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static final _tabs = [
    _HomeTab(
      title: 'Purchase Orders',
      icon: Icons.shopping_bag_outlined,
      builder: (_) => const PurchaseOrdersTab(),
    ),
    const _HomeTab(title: 'Bills', icon: Icons.receipt_long_outlined),
    const _HomeTab(title: 'Accounts', icon: Icons.account_balance_outlined),
    const _HomeTab(title: 'Overview', icon: Icons.dashboard_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);
    final theme = Theme.of(context);

    return DefaultTabController(
      length: _tabs.length,
      child: Scaffold(
        appBar: AppBar(
          title: null,
          automaticallyImplyLeading: false,
          actions: [
            IconButton(
              onPressed: () => appState.toggleThemeMode(),
              icon: Icon(
                appState.themeMode == ThemeMode.dark
                    ? Icons.dark_mode
                    : Icons.light_mode,
              ),
              tooltip: appState.themeMode == ThemeMode.dark
                  ? 'Switch to light mode'
                  : 'Switch to dark mode',
            ),
            IconButton(
              onPressed: () => appState.logout(),
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
            ),
          ],
        ),
        body: TabBarView(
          children: _tabs
              .map(
                (tab) => tab.builder?.call(context) ??
                    _HomeTabPlaceholder(
                      title: tab.title,
                      icon: tab.icon,
                    ),
              )
              .toList(),
        ),
        bottomNavigationBar: Material(
          color: theme.colorScheme.surface,
          child: TabBar(
            labelColor: theme.colorScheme.primary,
            unselectedLabelColor:
                theme.colorScheme.onSurface.withOpacity(0.7),
            indicatorColor: theme.colorScheme.primary,
            tabs: _tabs
                .map(
                  (tab) => Tab(
                    icon: Icon(tab.icon),
                    text: tab.title,
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }
}

class _HomeTab {
  const _HomeTab({required this.title, required this.icon, this.builder});

  final String title;
  final IconData icon;
  final WidgetBuilder? builder;
}

class _HomeTabPlaceholder extends StatelessWidget {
  const _HomeTabPlaceholder({required this.title, required this.icon});

  final String title;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              title,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'Content for the $title tab will appear here.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
