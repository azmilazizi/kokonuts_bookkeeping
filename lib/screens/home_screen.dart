import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  static const _tabs = [
    _HomeTab(title: 'Purchase Orders', icon: Icons.shopping_bag_outlined),
    _HomeTab(title: 'Payments', icon: Icons.payments_outlined),
    _HomeTab(title: 'Bills', icon: Icons.receipt_long_outlined),
    _HomeTab(title: 'Accounts', icon: Icons.account_balance_outlined),
    _HomeTab(title: 'Overview', icon: Icons.dashboard_outlined),
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
              onPressed: () => appState.logout(),
              icon: const Icon(Icons.logout),
              tooltip: 'Log out',
            ),
          ],
        ),
        body: TabBarView(
          children: _tabs
              .map((tab) => _HomeTabContent(
                    title: tab.title,
                    icon: tab.icon,
                  ))
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
  const _HomeTab({required this.title, required this.icon});

  final String title;
  final IconData icon;
}

class _HomeTabContent extends StatelessWidget {
  const _HomeTabContent({required this.title, required this.icon});

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
