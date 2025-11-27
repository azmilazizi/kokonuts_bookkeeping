import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

import 'accounts_tab.dart';
import 'bills_tab.dart';
import 'expenses_tab.dart';
import 'purchase_orders_tab.dart';

import '../services/bills_service.dart';
import '../services/expenses_service.dart';
import '../services/purchase_orders_service.dart';
import '../widgets/add_expense_dialog.dart';
import '../widgets/add_purchase_order_dialog.dart';
import '../widgets/create_bill_dialog.dart';
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
  final GlobalKey<ExpensesTabState> _expensesTabKey =
      GlobalKey<ExpensesTabState>();
  final GlobalKey<BillsTabState> _billsTabKey = GlobalKey<BillsTabState>();

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
        builder: (_, __) => ExpensesTab(key: _expensesTabKey),
      ),
      _HomeTab(
        title: 'Bills',
        icon: Icons.receipt_long_outlined,
        builder: (_, __) => BillsTab(key: _billsTabKey),
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
        final normalizedNumber = createdOrder.number.trim();
        final orderLabel =
            normalizedNumber.isEmpty || normalizedNumber == '—'
                ? createdOrder.name
                : normalizedNumber;
        _purchaseOrdersTabKey.currentState?.insertCreatedPurchaseOrder(
          createdOrder,
          successMessage: orderLabel.trim().isEmpty
              ? 'Purchase order created.'
              : 'Purchase order $orderLabel created.',
        );
      }
      return;
    }

    if (!mounted) {
      return;
    }

    switch (_controller.index) {
      case 1:
        final createdExpense = await showDialog<Expense>(
          context: context,
          builder: (context) => const AddExpenseDialog(),
        );

        if (createdExpense != null && mounted) {
          _expensesTabKey.currentState?.insertCreatedExpense(createdExpense);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Expense created successfully.')),
          );
        }
        break;
      case 2:
        final createdBill = await showDialog<Bill>(
          context: context,
          builder: (context) => const CreateBillDialog(),
        );

        if (createdBill != null && mounted) {
          _billsTabKey.currentState?.insertCreatedBill(createdBill);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Bill created successfully.')),
          );
        }
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

    final overlayStyle = theme.brightness == Brightness.dark
        ? SystemUiOverlayStyle.light.copyWith(
            statusBarColor: theme.colorScheme.surface,
            statusBarBrightness: Brightness.dark,
          )
        : SystemUiOverlayStyle.dark.copyWith(
            statusBarColor: theme.colorScheme.surface,
            statusBarBrightness: Brightness.light,
          );

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: theme.colorScheme.surface,
        body: ColoredBox(
          color: theme.colorScheme.surface,
          child: SafeArea(
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
                    icon: Icon(tab.icon, size: 26),
                    iconMargin: const EdgeInsets.only(bottom: 8),
                    height: 60,
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
