import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final appState = AppStateScope.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Kokonuts Bookkeeping'),
        actions: [
          IconButton(
            onPressed: () => appState.logout(),
            icon: const Icon(Icons.logout),
            tooltip: 'Log out',
          ),
        ],
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.book, size: 96),
            const SizedBox(height: 16),
            Text(
              'You are logged in!',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            const Text('Press the logout button in the top right to end your session.'),
          ],
        ),
      ),
    );
  }
}
