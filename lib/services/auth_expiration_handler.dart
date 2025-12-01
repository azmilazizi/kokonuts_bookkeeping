import 'package:flutter/material.dart';

import '../app/app_state_scope.dart';

class AuthExpiredException implements Exception {
  const AuthExpiredException([this.message = 'Your session has expired.']);

  final String message;

  @override
  String toString() => 'AuthExpiredException: $message';
}

class AuthExpirationHandler {
  AuthExpirationHandler._();

  static final AuthExpirationHandler instance = AuthExpirationHandler._();

  GlobalKey<NavigatorState>? navigatorKey;

  bool _isDialogVisible = false;

  Future<void> handleSessionExpired() async {
    final navigator = navigatorKey?.currentState;
    final context = navigator?.overlay?.context ?? navigator?.context;

    if (navigator == null || context == null || _isDialogVisible) {
      return;
    }

    _isDialogVisible = true;
    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Session expired'),
          content: const Text('Your authentication has expired. Please log in again to continue.'),
          actions: [
            TextButton(
              onPressed: () async {
                Navigator.of(dialogContext, rootNavigator: true).pop();
                final appState = AppStateScope.of(context);
                await appState.logout();
              },
              child: const Text('Log in'),
            ),
          ],
        ),
      );
    } finally {
      _isDialogVisible = false;
    }
  }
}
