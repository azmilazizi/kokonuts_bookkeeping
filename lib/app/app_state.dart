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

  /// Returns the active auth token, refreshing it from storage if needed.
  Future<String?> getValidAuthToken() async {
    if (_authToken != null && _authToken!.isNotEmpty) {
      return _authToken;
    }

    final storedToken = await _sessionManager.getAuthToken();
    if (storedToken != null && storedToken.isNotEmpty) {
      _authToken = storedToken;
      return _authToken;
    }

    return null;
  }

  /// Builds request headers that include the auth token when available.
  Future<Map<String, String>> buildAuthHeaders({
    Map<String, String>? headers,
    String authorizationScheme = 'Token',
  }) async {
    final resolvedHeaders = <String, String>{...?headers};
    final token = await getValidAuthToken();
    if (token != null && token.isNotEmpty) {
      final scheme = authorizationScheme.trim();
      final value = scheme.isEmpty ? token : '$scheme $token';
      resolvedHeaders.putIfAbsent('Authorization', () => value);
      resolvedHeaders.putIfAbsent('authtoken', () => token);
    }
    return resolvedHeaders;
  }

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
