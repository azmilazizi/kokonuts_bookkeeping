import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_state.dart';
import 'app/app_state_scope.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/session_manager.dart';
import 'theme/color_schemes.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final sessionManager = SessionManager();
  final authService = AuthService(sessionManager: sessionManager);
  final appState = AppState(authService: authService, sessionManager: sessionManager);

  runApp(KokonutsBookkeepingApp(appState: appState));
}

class KokonutsBookkeepingApp extends StatefulWidget {
  const KokonutsBookkeepingApp({super.key, required this.appState});

  final AppState appState;

  @override
  State<KokonutsBookkeepingApp> createState() => _KokonutsBookkeepingAppState();
}

class _KokonutsBookkeepingAppState extends State<KokonutsBookkeepingApp> {
  late final AppState _appState = widget.appState;

  @override
  void initState() {
    super.initState();
    unawaited(_appState.initialize());
  }

  @override
  Widget build(BuildContext context) {
    return AppStateScope(
      notifier: _appState,
      child: AnimatedBuilder(
        animation: _appState,
        builder: (context, _) {
          return MaterialApp(
            title: 'Kokonuts Bookkeeping',
            debugShowCheckedModeBanner: false,
            theme: ThemeData(
              colorScheme: lightColorScheme,
              useMaterial3: true,
            ),
            darkTheme: ThemeData(
              colorScheme: darkColorScheme,
              useMaterial3: true,
            ),
            themeMode: _appState.themeMode,
            home: _buildHome(),
          );
        },
      ),
    );
  }

  Widget _buildHome() {
    if (!_appState.isInitialized) {
      return const SplashScreen();
    }

    if (_appState.isLoggedIn) {
      return const HomeScreen();
    }

    return const LoginScreen();
  }
}
