import 'package:flutter/material.dart';

import '../app/app_state.dart';
import '../app/app_state_scope.dart';

typedef _ThemeModeLabel = ({IconData icon, String tooltip});

/// Displays the application logo next to a page title.
class TabPageHeader extends StatelessWidget {
  const TabPageHeader({
    super.key,
    required this.title,
    this.padding = const EdgeInsets.fromLTRB(24, 24, 24, 12),
    this.logoSize = 36,
  });

  final String title;
  final EdgeInsetsGeometry padding;
  final double logoSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final appState = AppStateScope.of(context);
    final isCompact = MediaQuery.sizeOf(context).width < 600;
    final modeLabel = _themeModeLabel(appState.themeMode);
    final themeTooltip = 'Theme: ${modeLabel.tooltip}';

    return Padding(
      padding: padding,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              FlutterLogo(size: logoSize),
              const SizedBox(width: 12),
              Text(
                title,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const Spacer(),
          if (isCompact)
            _HeaderMenuButton(
              themeLabel: themeTooltip,
              themeIcon: modeLabel.icon,
              onSelectTheme: () => _selectTheme(context, appState),
              onLogout: appState.logout,
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  tooltip: themeTooltip,
                  icon: Icon(modeLabel.icon),
                  onPressed: () => _selectTheme(context, appState),
                ),
                IconButton(
                  tooltip: 'Log out',
                  icon: const Icon(Icons.logout),
                  onPressed: appState.logout,
                ),
              ],
            ),
        ],
      ),
    );
  }
}

_ThemeModeLabel _themeModeLabel(ThemeMode mode) {
  switch (mode) {
    case ThemeMode.dark:
      return (icon: Icons.dark_mode_outlined, tooltip: 'Dark mode');
    case ThemeMode.light:
      return (icon: Icons.light_mode_outlined, tooltip: 'Light mode');
    case ThemeMode.system:
      return (icon: Icons.brightness_auto_outlined, tooltip: 'System theme');
  }
}

Future<void> _selectTheme(BuildContext context, AppState appState) async {
  final selectedMode = await showDialog<ThemeMode>(
    context: context,
    builder: (context) {
      final theme = Theme.of(context);
      final options = const [
        (mode: ThemeMode.light, label: 'Light'),
        (mode: ThemeMode.dark, label: 'Dark'),
        (mode: ThemeMode.system, label: 'System'),
      ];

      return AlertDialog(
        title: const Text('Select theme'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: options
              .map(
                (option) => RadioListTile<ThemeMode>(
                  value: option.mode,
                  groupValue: appState.themeMode,
                  onChanged: (value) => Navigator.of(context).pop(value),
                  title: Text(option.label, style: theme.textTheme.bodyLarge),
                ),
              )
              .toList(),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
        ],
      );
    },
  );

  if (selectedMode != null) {
    appState.updateThemeMode(selectedMode);
  }
}

class _HeaderMenuButton extends StatelessWidget {
  const _HeaderMenuButton({
    required this.themeLabel,
    required this.themeIcon,
    required this.onSelectTheme,
    required this.onLogout,
  });

  final String themeLabel;
  final IconData themeIcon;
  final VoidCallback onSelectTheme;
  final VoidCallback onLogout;

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
                    leading: Icon(themeIcon),
                    title: Text(themeLabel),
                    onTap: () {
                      Navigator.of(context).pop();
                      onSelectTheme();
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.logout),
                    title: const Text('Log out'),
                    onTap: () {
                      Navigator.of(context).pop();
                      onLogout();
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
