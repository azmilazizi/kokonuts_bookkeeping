import 'dart:async';

import 'package:flutter/material.dart';

import 'app/app_state.dart';
import 'app/app_state_scope.dart';
import 'screens/home_screen.dart';
import 'screens/login_screen.dart';
import 'screens/splash_screen.dart';
import 'services/auth_service.dart';
import 'services/auth_expiration_handler.dart';
import 'services/session_manager.dart';

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
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  final GlobalKey<ScaffoldMessengerState> _scaffoldMessengerKey =
      GlobalKey<ScaffoldMessengerState>();

  @override
  void initState() {
    super.initState();
    AuthExpirationHandler.instance.navigatorKey = _navigatorKey;
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
            navigatorKey: _navigatorKey,
            scaffoldMessengerKey: _scaffoldMessengerKey,
            theme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: Brightness.light,
              ),
              useMaterial3: true,
              snackBarTheme: const SnackBarThemeData(
                behavior: SnackBarBehavior.fixed,
              ),
            ),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                seedColor: Colors.teal,
                brightness: Brightness.dark,
              ),
              useMaterial3: true,
              snackBarTheme: const SnackBarThemeData(
                behavior: SnackBarBehavior.fixed,
              ),
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
