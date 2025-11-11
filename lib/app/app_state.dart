import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

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
  String? _username;
  ThemeMode _themeMode = ThemeMode.light;

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _isLoggedIn;
  String? get authToken => _authToken;
  String? get username => _username;
  ThemeMode get themeMode => _themeMode;

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
      final storedUsername = await _sessionManager.getUsername();
      if (storedUsername != null && storedUsername.isNotEmpty) {
        _username = storedUsername;
        final storedTheme = await _sessionManager.getThemeMode(storedUsername);
        if (storedTheme != null) {
          _themeMode = storedTheme;
        }
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Attempts to log the user in using the provided credentials.
  Future<void> login({required String username, required String password}) async {
    final normalizedUsername = username.trim();
    final token = await _authService.login(username: normalizedUsername, password: password);
    _authToken = token;
    _isLoggedIn = true;
    _username = normalizedUsername;
    await _sessionManager.saveUsername(normalizedUsername);
    final storedTheme = await _sessionManager.getThemeMode(normalizedUsername);
    _themeMode = storedTheme ?? ThemeMode.light;
    notifyListeners();
  }

  /// Logs out the user and clears any persisted session information.
  Future<void> logout() async {
    await _authService.logout();
    _authToken = null;
    _isLoggedIn = false;
    _username = null;
    _themeMode = ThemeMode.light;
    await _sessionManager.clearUsername();
    notifyListeners();
  }

  /// Updates the theme mode for the active user.
  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;
    notifyListeners();

    final activeUsername = _username;
    if (activeUsername != null) {
      await _sessionManager.saveThemeMode(username: activeUsername, mode: mode);
    }
  }

  /// Toggles between light and dark themes.
  Future<void> toggleThemeMode() {
    final nextMode = _themeMode == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
    return updateThemeMode(nextMode);
  }
}
