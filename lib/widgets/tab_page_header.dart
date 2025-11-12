import 'package:flutter/material.dart';

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

    return Padding(
      padding: padding,
      child: Align(
        alignment: Alignment.centerLeft,
        child: Row(
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
      ),
    );
  }
}
