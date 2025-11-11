import 'package:flutter/material.dart';

class AccountsTab extends StatelessWidget {
  const AccountsTab({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_balance_outlined,
                size: 72, color: theme.colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'Accounts data temporarily unavailable',
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'We\'re resetting the connection. Please check back later for updated account information.',
              style: theme.textTheme.bodyMedium,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
