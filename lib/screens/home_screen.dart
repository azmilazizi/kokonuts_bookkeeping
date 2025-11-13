import 'package:flutter/cupertino.dart';
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

class _HomeScreenState extends State<HomeScreen> {
  late final CupertinoTabController _controller =
      CupertinoTabController(initialIndex: 0);

  static final List<_HomeTab> _tabs = [
    _HomeTab(
      title: 'Purchase Orders',
      icon: CupertinoIcons.shopping_cart,
      builder: (_, __) => const PurchaseOrdersTab(),
    ),
    _HomeTab(
      title: 'Expenses',
      icon: CupertinoIcons.money_dollar_circle,
      builder: (_, __) => const ExpensesTab(),
    ),
    _HomeTab(
      title: 'Bills',
      icon: CupertinoIcons.doc_plaintext,
      builder: (_, __) => const BillsTab(),
    ),
    _HomeTab(
      title: 'Accounts',
      icon: CupertinoIcons.person_2,
      builder: (_, __) => const AccountsTab(),
    ),
    const _HomeTab(
      title: 'Overview',
      icon: CupertinoIcons.square_grid_2x2,
      showAddAction: false,
    ),
  ];

  @override
  void dispose() {
    _controller.removeListener(_handleTabSelection);
    _controller.dispose();
    super.dispose();
  }

  void _openAddModal(BuildContext context, String tabTitle) {
    showCupertinoModalPopup<void>(
      context: context,
      builder: (context) {
        return CupertinoActionSheet(
          title: Text('Add new $tabTitle'),
          message: Text(
            'This is a placeholder for creating a new $tabTitle entry. '
            'Replace this sheet with the appropriate flow when ready.',
          ),
          cancelButton: CupertinoActionSheetAction(
            onPressed: () => Navigator.of(context).pop(),
            isDefaultAction: true,
            child: const Text('Close'),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return CupertinoTabScaffold(
      controller: _controller,
      tabBar: CupertinoTabBar(
        items: _tabs
            .map(
              (tab) => BottomNavigationBarItem(
                icon: Icon(tab.icon),
                label: tab.title,
              ),
            )
            .toList(growable: false),
      ),
      tabBuilder: (context, index) {
        final tab = _tabs[index];
        final scopedAppState = AppStateScope.of(context);
        final child = tab.builder?.call(context, scopedAppState) ??
            _HomeTabPlaceholder(title: tab.title, icon: tab.icon);

        return CupertinoPageScaffold(
          child: Stack(
            children: [
              Positioned.fill(
                child: SafeArea(
                  top: true,
                  bottom: false,
                  child: child,
                ),
              ),
              if (tab.showAddAction)
                Positioned(
                  right: 20,
                  bottom: 20 + MediaQuery.of(context).padding.bottom,
                  child: Tooltip(
                    message: 'Add ${tab.title}',
                    child: _CupertinoAddButton(
                      tabTitle: tab.title,
                      onPressed: () => _openAddModal(context, tab.title),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
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
  const _HomeTab({
    required this.title,
    required this.icon,
    this.builder,
    this.showAddAction = true,
  });

  final String title;
  final IconData icon;
  final Widget Function(BuildContext context, AppState appState)? builder;
  final bool showAddAction;
}

class _CupertinoAddButton extends StatelessWidget {
  const _CupertinoAddButton({required this.onPressed, required this.tabTitle});

  final VoidCallback onPressed;
  final String tabTitle;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Add $tabTitle',
      button: true,
      child: CupertinoButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: CupertinoColors.activeBlue,
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x33000000),
                blurRadius: 12,
                offset: Offset(0, 6),
              ),
            ],
          ),
          child: const SizedBox(
            width: 56,
            height: 56,
            child: Icon(
              CupertinoIcons.add,
              color: CupertinoColors.white,
              size: 28,
            ),
          ),
        ),
      ),
    );
  }
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
