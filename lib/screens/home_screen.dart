import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

import 'accounts_tab.dart';
import 'bills_tab.dart';
import 'expenses_tab.dart';
import 'purchase_orders_tab.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(length: _tabs.length, vsync: this)
    ..addListener(_handleTabSelection);

  static final List<_HomeTab> _tabs = [
    _HomeTab(
      title: 'Purchase Orders',
      icon: Icons.shopping_bag_outlined,
      builder: (_, __) => const PurchaseOrdersTab(),
    ),
    _HomeTab(
      title: 'Expenses',
      icon: Icons.payments_outlined,
      builder: (_, __) => const ExpensesTab(),
    ),
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
    _controller.removeListener(_handleTabSelection);
    _controller.dispose();
    super.dispose();
  }

  void _handleTabSelection() {
    if (!_controller.indexIsChanging) {
      setState(() {});
    }
  }

  void _openAddModal(BuildContext context, String tabTitle) {
    showModalBottomSheet<void>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Add new $tabTitle',
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              Text(
                'This is a placeholder for creating a new $tabTitle entry. '
                'Replace this modal with the appropriate form or navigation when ready.',
                style: theme.textTheme.bodyMedium,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.add),
                label: const Text('Close'),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AppState appState = AppStateScope.of(context);
    final username = appState.username;

    final AppState scopedAppState = AppStateScope.of(context);

    final bool isOverviewTabSelected = _controller.index == _tabs.length - 1;
    final _HomeTab currentTab = _tabs[_controller.index];

    return Scaffold(
      body: SafeArea(
        top: true,
        bottom: false,
        child: TabBarView(
          controller: _controller,
          children: _tabs
              .map(
                (tab) => tab.builder?.call(context, scopedAppState) ??
                    _HomeTabPlaceholder(
                      title: tab.title,
                      icon: tab.icon,
                    ),
              )
              .toList(growable: false),
        ),
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
      floatingActionButton: isOverviewTabSelected
          ? null
          : FloatingActionButton(
              tooltip: 'Add ${currentTab.title}',
              onPressed: () => _openAddModal(context, currentTab.title),
              child: const Icon(Icons.add),
            ),
    );
  }
}

class _ThemeModeButton extends StatelessWidget {
  const _ThemeModeButton({required this.appState});

  final AppState appState;

  @override
  Widget build(BuildContext context) {
    final currentMode = appState.themeMode;
    IconData icon;
    String tooltip;

    switch (currentMode) {
      case ThemeMode.dark:
        icon = Icons.dark_mode_outlined;
        tooltip = 'Dark mode';
        break;
      case ThemeMode.light:
        icon = Icons.light_mode_outlined;
        tooltip = 'Light mode';
        break;
      case ThemeMode.system:
        icon = Icons.brightness_auto_outlined;
        tooltip = 'System theme';
        break;
    }

    return PopupMenuButton<ThemeMode>(
      tooltip: 'Theme preferences',
      icon: Icon(icon),
      initialValue: currentMode,
      onSelected: appState.updateThemeMode,
      itemBuilder: (context) => [
        CheckedPopupMenuItem(
          value: ThemeMode.light,
          checked: currentMode == ThemeMode.light,
          child: const Text('Light'),
        ),
        CheckedPopupMenuItem(
          value: ThemeMode.dark,
          checked: currentMode == ThemeMode.dark,
          child: const Text('Dark'),
        ),
        CheckedPopupMenuItem(
          value: ThemeMode.system,
          checked: currentMode == ThemeMode.system,
          child: const Text('System'),
        ),
      ],
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
