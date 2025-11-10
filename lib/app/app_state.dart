import 'package:flutter/foundation.dart';

import '../services/auth_service.dart';
import '../services/session_manager.dart';

/// Stores global application state such as authentication status.
class AppState extends ChangeNotifier {
  AppState({required AuthService authService, required SessionManager sessionManager})
      : _authService = authService,
        _sessionManager = sessionManager;

  final AuthService _authService;
  final SessionManager _sessionManager;

  bool _isInitialized = false;
  bool _isLoggedIn = false;
  String? _authToken;

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _isLoggedIn;
  String? get authToken => _authToken;

  /// Loads persisted session information.
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final storedToken = await _sessionManager.getAuthToken();
    if (storedToken != null && storedToken.isNotEmpty) {
      _authToken = storedToken;
      _isLoggedIn = true;
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Attempts to log the user in using the provided credentials.
  Future<void> login({required String username, required String password}) async {
    final token = await _authService.login(username: username, password: password);
    _authToken = token;
    _isLoggedIn = true;
    notifyListeners();
  }

  /// Logs out the user and clears any persisted session information.
  Future<void> logout() async {
    await _authService.logout();
    _authToken = null;
    _isLoggedIn = false;
    notifyListeners();
  }
}
