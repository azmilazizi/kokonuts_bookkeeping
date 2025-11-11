import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/auth_service.dart';
import '../services/authenticated_http_client.dart';
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
  String? _rawAuthToken;
  String? _username;
  ThemeMode _themeMode = ThemeMode.system;
  http.Client? _authenticatedClient;
  String _defaultAuthorizationScheme = 'Token';

  bool get isInitialized => _isInitialized;
  bool get isLoggedIn => _isLoggedIn;
  String? get authToken => _rawAuthToken ?? _authToken;
  String? get username => _username;
  ThemeMode get themeMode => _themeMode;

  /// Returns the active auth token, refreshing it from storage if needed.
  Future<String?> getValidAuthToken() async {
    if (_authToken != null && _authToken!.isNotEmpty) {
      return _authToken;
    }

    final storedToken = await _sessionManager.getAuthToken();
    if (storedToken != null && storedToken.isNotEmpty) {
      _applyToken(storedToken);
      return _authToken;
    }

    return null;
  }

  Future<AuthTokenPayload?> _getAuthTokenPayload() async {
    final token = await getValidAuthToken();
    if (token == null || token.isEmpty) {
      return null;
    }

    final rawAuthtoken = (_rawAuthToken != null && _rawAuthToken!.isNotEmpty)
        ? _rawAuthToken!
        : token;
    final authtokenValue = _extractAuthtokenValue(rawAuthtoken);

    return AuthTokenPayload(
      authorizationToken: token,
      authtoken: authtokenValue,
    );
  }

  /// Provides an HTTP client that automatically injects auth headers for requests.
  http.Client get authenticatedClient {
    return _authenticatedClient ??= AuthenticatedHttpClient(
      tokenProvider: _getAuthTokenPayload,
      authorizationBuilder: (token) {
        final scheme = _defaultAuthorizationScheme.trim();
        return scheme.isEmpty ? token : '$scheme $token';
      },
    );
  }

  /// Builds request headers that include the auth token when available.
  Future<Map<String, String>> buildAuthHeaders({
    Map<String, String>? headers,
    String? authorizationScheme,
  }) async {
    final resolvedHeaders = <String, String>{...?headers};
    final payload = await _getAuthTokenPayload();
    if (payload != null) {
      final token = payload.authorizationToken;
      final scheme = (authorizationScheme ?? _defaultAuthorizationScheme).trim();
      final value = scheme.isEmpty ? token : '$scheme $token';
      if (value.trim().isNotEmpty) {
        resolvedHeaders['Authorization'] = value.trim();
      }
      final authtokenValue = payload.authtoken.trim();
      if (authtokenValue.isNotEmpty) {
        resolvedHeaders['authtoken'] = authtokenValue;
      }
    }
    return resolvedHeaders;
  }

  /// Loads persisted session information.
  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    final storedToken = await _sessionManager.getAuthToken();
    final storedUsername = await _sessionManager.getCurrentUsername();

    if (storedToken != null && storedToken.isNotEmpty) {
      _applyToken(storedToken);
      _isLoggedIn = true;
    }

    if (storedUsername != null && storedUsername.isNotEmpty) {
      _username = storedUsername;
      final storedTheme = await _sessionManager.getThemeModeForUser(storedUsername);
      if (storedTheme != null) {
        _themeMode = storedTheme;
      }
    }

    _isInitialized = true;
    notifyListeners();
  }

  /// Attempts to log the user in using the provided credentials.
  Future<void> login({required String username, required String password}) async {
    final token = await _authService.login(username: username, password: password);
    _applyToken(token);
    _username = username.trim();
    if (_username != null && _username!.isNotEmpty) {
      await _sessionManager.saveCurrentUsername(_username!);
      final storedTheme = await _sessionManager.getThemeModeForUser(_username!);
      if (storedTheme != null) {
        _themeMode = storedTheme;
      } else {
        _themeMode = ThemeMode.system;
      }
    }
    _isLoggedIn = true;
    notifyListeners();
  }

  /// Logs out the user and clears any persisted session information.
  Future<void> logout() async {
    await _authService.logout();
    _authToken = null;
    _rawAuthToken = null;
    _isLoggedIn = false;
    _authenticatedClient?.close();
    _authenticatedClient = null;
    if (_username != null) {
      await _sessionManager.clearCurrentUsername();
    }
    _username = null;
    _themeMode = ThemeMode.system;
    _defaultAuthorizationScheme = 'Token';
    notifyListeners();
  }

  /// Updates the preferred theme mode and persists it for the active user.
  Future<void> updateThemeMode(ThemeMode mode) async {
    if (_themeMode == mode) {
      return;
    }

    _themeMode = mode;
    final activeUser = _username;
    if (activeUser != null && activeUser.isNotEmpty) {
      await _sessionManager.saveThemeModeForUser(activeUser, mode);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _authenticatedClient?.close();
    super.dispose();
  }

  void _applyToken(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      _authToken = null;
      _rawAuthToken = null;
      _defaultAuthorizationScheme = 'Token';
      return;
    }

    _rawAuthToken = trimmed;
    final spaceIndex = trimmed.indexOf(' ');
    if (spaceIndex > 0) {
      final scheme = trimmed.substring(0, spaceIndex).trim();
      final credentials = trimmed.substring(spaceIndex + 1).trim();
      if (credentials.isNotEmpty) {
        _defaultAuthorizationScheme = scheme.isEmpty ? 'Token' : scheme;
        _authToken = credentials;
        return;
      }
    }

    _authToken = trimmed;
    _defaultAuthorizationScheme = 'Token';
  }

  String _extractAuthtokenValue(String token) {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      return '';
    }

    final spaceIndex = trimmed.indexOf(' ');
    if (spaceIndex <= 0) {
      return trimmed;
    }

    final scheme = trimmed.substring(0, spaceIndex).trim();
    final credentials = trimmed.substring(spaceIndex + 1).trim();
    if (credentials.isEmpty) {
      return trimmed;
    }

    final expectedScheme = _defaultAuthorizationScheme.trim();
    if (expectedScheme.isEmpty) {
      return credentials;
    }

    if (scheme.toLowerCase() == expectedScheme.toLowerCase()) {
      return credentials;
    }

    return trimmed;
  }
}
