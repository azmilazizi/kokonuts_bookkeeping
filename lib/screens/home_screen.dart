import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

import 'accounts_tab.dart';
import 'bills_tab.dart';
import 'expenses_tab.dart';
import 'purchase_orders_tab.dart';

import '../services/purchase_orders_service.dart';
import '../widgets/add_expense_dialog.dart';
import '../widgets/add_purchase_order_dialog.dart';
import '../widgets/post_dialog.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late final TabController _controller;
  late final List<_HomeTab> _tabs;
  final GlobalKey<PurchaseOrdersTabState> _purchaseOrdersTabKey =
      GlobalKey<PurchaseOrdersTabState>();

  @override
  void initState() {
    super.initState();
    _tabs = [
      _HomeTab(
        title: 'Purchase Orders',
        icon: Icons.shopping_bag_outlined,
        builder: (_, __) => PurchaseOrdersTab(key: _purchaseOrdersTabKey),
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
    _controller = TabController(length: _tabs.length, vsync: this)
      ..addListener(_handleTabSelection);
  }

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

  Future<void> _openAddModal(BuildContext context, String tabTitle) async {
    if (_controller.index == 0) {
      final createdOrder = await showDialog<PurchaseOrder>(
        context: context,
        barrierDismissible: false,
        builder: (context) => const AddPurchaseOrderDialog(),
      );

      if (!mounted) {
        return;
      }

      if (createdOrder != null) {
        _purchaseOrdersTabKey.currentState
            ?.insertCreatedPurchaseOrder(createdOrder);
        final normalizedNumber = createdOrder.number.trim();
        final orderLabel =
            normalizedNumber.isEmpty || normalizedNumber == '—'
                ? createdOrder.name
                : normalizedNumber;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Purchase order $orderLabel created.')),
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    switch (_controller.index) {
      case 1:
        await showDialog<void>(
          context: context,
          builder: (context) => const AddExpenseDialog(),
        );
        break;
      case 2:
        await showDialog<void>(
          context: context,
          builder: (context) => const PostDialog(
            title: 'Create Bill (POST)',
            apiPath: 'https://crm.kokonuts.my/accounting/api/v1/bills',
            description:
                'Submit a POST request to record a new bill. Adjust the sample '
                'payload to match your bill data before sending.',
            samplePayload: {
              'vendor_id': '123',
              'bill_number': 'BILL-001',
              'bill_date': '2024-04-01',
              'due_date': '2024-04-15',
              'status': 'pending',
              'total_amount': 240.75,
              'notes': 'Pay before due date to avoid surcharge',
            },
          ),
        );
        break;
      default:
        await showDialog<void>(
          context: context,
          builder: (context) => PostDialog(
            title: 'Create $tabTitle',
            apiPath: 'https://crm.kokonuts.my',
            description:
                'Add the correct endpoint and payload for this tab when ready.',
            samplePayload: const {
              'example': 'value',
            },
          ),
        );
    }
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
