import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_speed_dial/flutter_speed_dial.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

import 'accounts_tab.dart';
import 'bills_tab.dart';
import 'expenses_tab.dart';
import 'overview_tab.dart';
import 'purchase_orders_tab.dart';
import 'scan_receipt_screen.dart';

import '../services/bills_service.dart';
import '../services/expenses_service.dart';
import '../services/purchase_orders_service.dart';
import '../widgets/add_expense_dialog.dart';
import '../widgets/add_purchase_order_dialog.dart';
import '../widgets/create_bill_dialog.dart';
import '../widgets/post_dialog.dart';
import '../widgets/app_logo.dart';
import '../widgets/journal_entry_dialog.dart';

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
        icon: Icons.shopping_bag,
        builder: (_, __) => PurchaseOrdersTab(key: _purchaseOrdersTabKey),
      ),
      _HomeTab(
        title: 'Expenses',
        icon: Icons.payments,
        builder: (_, __) => ExpensesTab(key: _expensesTabKey),
      ),
      _HomeTab(
        title: 'Bills',
        icon: Icons.receipt_long,
        builder: (_, __) => BillsTab(key: _billsTabKey),
      ),
      _HomeTab(
        title: 'Accounts',
        icon: Icons.account_balance,
        builder: (_, __) => const AccountsTab(),
      ),
      _HomeTab(
        title: 'Overview',
        icon: Icons.dashboard,
        builder: (_, appState) => OverviewTab(appState: appState),
      ),
    ];
    _controller = TabController(
        length: _tabs.length, vsync: this, initialIndex: _tabs.length - 1)
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

  Future<void> _openJournalEntryDialog(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (context) => const JournalEntryDialog(),
    );
  }

  Future<void> _openScanScreen(BuildContext context, String recordType) async {
    final scanResponse = await Navigator.of(context).push<Map<String, dynamic>>(
      MaterialPageRoute<Map<String, dynamic>>(
        builder: (_) => ScanReceiptScreen(recordType: recordType),
      ),
    );

    if (!mounted || scanResponse == null) return;

    final result = scanResponse['result'] as Map<String, dynamic>?;
    final filePath = scanResponse['filePath'] as String?;
    final fileBytes = scanResponse['fileBytes'] as Uint8List?;
    if (result == null) return;

    if (recordType == 'purchase_order') {
      final createdOrder = await showDialog<PurchaseOrder>(
        context: context,
        barrierDismissible: false,
        builder: (context) => AddPurchaseOrderDialog(
          extracted: result,
          scannedFilePath: filePath,
          scannedFileBytes: fileBytes,
        ),
      );
      if (!mounted) return;
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
    } else if (recordType == 'bill') {
      final createdBill = await showDialog<Bill>(
        context: context,
        builder: (context) => CreateBillDialog(
          extracted: result,
          scannedFilePath: filePath,
          scannedFileBytes: fileBytes,
        ),
      );
      if (!mounted) return;
      if (createdBill != null) {
        _billsTabKey.currentState?.insertCreatedBill(createdBill);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Bill created successfully.')),
        );
      }
    } else {
      final createdExpense = await showDialog<Expense>(
        context: context,
        builder: (context) => AddExpenseDialog(
          extracted: result,
          scannedFilePath: filePath,
          scannedFileBytes: fileBytes,
        ),
      );
      if (!mounted) return;
      if (createdExpense != null) {
        _expensesTabKey.currentState?.insertCreatedExpense(createdExpense);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Expense created successfully.')),
        );
      }
    }
  }

  Widget _buildFab(BuildContext context, _HomeTab currentTab) {
    final index = _controller.index;

    if (index == 0 || index == 1 || index == 2) {
      final recordType = index == 0
          ? 'purchase_order'
          : index == 1
              ? 'expense'
              : 'bill';
      final addLabel = index == 0
          ? 'Add Purchase Order'
          : index == 1
              ? 'Add Expense'
              : 'Add Bill';

      return SpeedDial(
        icon: Icons.add,
        activeIcon: Icons.close,
        spacing: 8,
        spaceBetweenChildren: 8,
        children: [
          SpeedDialChild(
            child: const Icon(Icons.add),
            label: addLabel,
            onTap: () => _openAddModal(context, currentTab.title),
          ),
          SpeedDialChild(
            child: const Icon(Icons.document_scanner),
            label: 'AI Scan',
            onTap: () => _openScanScreen(context, recordType),
          ),
        ],
      );
    }

    return FloatingActionButton(
      tooltip: 'Add ${currentTab.title}',
      onPressed: () => _openAddModal(context, currentTab.title),
      child: const Icon(Icons.add),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final AppState appState = AppStateScope.of(context);

    final AppState scopedAppState = AppStateScope.of(context);

    final bool isOverviewTabSelected = _controller.index == _tabs.length - 1;
    final _HomeTab currentTab = _tabs[_controller.index];
    final isCompact = MediaQuery.sizeOf(context).width < 600;

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
        appBar: AppBar(
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 28),
              const SizedBox(width: 12),
              Flexible(
                child: Text(
                  currentTab.title,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          actions: [
            if (isCompact)
              _HeaderMenuButton(
                appState: appState,
                onOpenJournalEntry: () => _openJournalEntryDialog(context),
              )
            else ...[
              IconButton(
                tooltip: 'Journal entry',
                icon: const Icon(Icons.note_add),
                onPressed: () => _openJournalEntryDialog(context),
              ),
              IconButton(
                tooltip: 'Log out',
                icon: const Icon(Icons.logout),
                onPressed: appState.logout,
              ),
            ],
            const SizedBox(width: 8),
          ],
        ),
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
          child: Theme(
            data: theme.copyWith(splashFactory: InkRipple.splashFactory),
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
        ),
        floatingActionButton: isOverviewTabSelected
            ? null
            : _buildFab(context, currentTab),
      ),
    );
  }
}


class _HeaderMenuButton extends StatelessWidget {
  const _HeaderMenuButton({
    required this.appState,
    required this.onOpenJournalEntry,
  });

  final AppState appState;
  final VoidCallback onOpenJournalEntry;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Menu',
      icon: const Icon(Icons.menu),
      onPressed: () {
        showModalBottomSheet<void>(
          context: context,
          builder: (context) {
            return SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ListTile(
                    leading: const Icon(Icons.note_add),
                    title: const Text('Journal entry'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onOpenJournalEntry();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Log out'),
                    onTap: () {
                      Navigator.of(context).pop();
                      appState.logout();
                    },
                  ),
                ],
              ),
            );
          },
        );
      },
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
