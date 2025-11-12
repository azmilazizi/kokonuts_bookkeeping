import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

import 'accounts_tab.dart';
import 'bills_tab.dart';
import 'purchase_orders_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(length: _tabs.length, vsync: this);

  static final List<_HomeTab> _tabs = [
    _HomeTab(
      title: 'Purchase Orders',
      icon: Icons.shopping_bag_outlined,
      builder: (_, __) => const PurchaseOrdersTab(),
    ),
    const _HomeTab(title: 'Payments', icon: Icons.payments_outlined),
    _HomeTab(
      title: 'Bills',
      icon: Icons.receipt_long_outlined,
      builder: (_, __) => const BillsTab(),
    ),
    _HomeTab(
      title: 'Accounts',
      icon: Icons.account_balance_outlined,
      builder: (_, __) => const AccountsTab(),
    ),
    const _HomeTab(title: 'Overview', icon: Icons.dashboard_outlined),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final appState = AppStateScope.of(context);

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Kokonuts Bookkeeping'),
      ),
      body: TabBarView(
        controller: _controller,
        children: _tabs
            .map(
              (tab) => tab.builder?.call(context, appState) ??
                  _HomeTabPlaceholder(
                    title: tab.title,
                    icon: tab.icon,
                  ),
            )
            .toList(growable: false),
      ),
      bottomNavigationBar: Material(
        color: theme.colorScheme.surface,
        child: TabBar(
          controller: _controller,
          indicatorColor: theme.colorScheme.primary,
          labelColor: theme.colorScheme.primary,
          unselectedLabelColor: theme.colorScheme.onSurface.withOpacity(0.7),
          tabs: _tabs
              .map(
                (tab) => Tab(
                  icon: Icon(tab.icon),
                  iconMargin: const EdgeInsets.only(bottom: 6),
                  height: 48,
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _HomeTab {
  const _HomeTab({required this.title, required this.icon, this.builder});

  final String title;
  final IconData icon;
  final Widget Function(BuildContext context, AppState appState)? builder;
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
