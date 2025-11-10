import 'dart:convert';

import 'package:http/http.dart' as http;

import 'session_manager.dart';

/// Thrown when authentication fails.
class AuthException implements Exception {
  const AuthException(this.message);

  final String message;

  @override
  String toString() => 'AuthException: $message';
}

/// Handles authentication-related network requests.
class AuthService {
  AuthService({http.Client? client, required SessionManager sessionManager})
      : _client = client ?? http.Client(),
        _sessionManager = sessionManager;

  static const _loginUrl = 'https://crm.kokonuts.my/timesheets/api/login';

  final http.Client _client;
  final SessionManager _sessionManager;

  /// Attempts to log the user in and returns the auth token if successful.
  Future<String> login({required String username, required String password}) async {
    late http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_loginUrl),
        headers: const {'Content-Type': 'application/json'},
        body: jsonEncode({'username': username, 'password': password}),
      );
    } catch (_) {
      throw const AuthException('Unable to reach the server. Please try again later.');
    }

    if (response.statusCode == 200) {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
      final token = _extractToken(decoded);
      if (token == null || token.isEmpty) {
        throw const AuthException('The server response did not include a token.');
      }
      await _sessionManager.saveAuthToken(token);
      return token;
    }

    String message = 'Login failed with status code ${response.statusCode}.';
    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>?;
      final serverMessage = decoded?['message'] as String?;
      if (serverMessage != null && serverMessage.isNotEmpty) {
        message = serverMessage;
      }
    } catch (_) {
      // Ignore parsing errors and fall back to default message.
    }
    throw AuthException(message);
  }

  /// Clears persisted authentication state.
  Future<void> logout() async {
    await _sessionManager.clearAuthToken();
  }

  String? _extractToken(Map<String, dynamic>? decoded) {
    if (decoded == null) {
      return null;
    }

    final rawToken = decoded['token'];
    if (rawToken is String && rawToken.isNotEmpty) {
      return rawToken;
    }

    for (final entry in decoded.entries) {
      final value = entry.value;
      if (value is String && value.isNotEmpty && entry.key.toLowerCase() == 'token') {
        return value;
      }
      if (value is Map<String, dynamic>) {
        final nestedToken = _extractToken(value);
        if (nestedToken != null && nestedToken.isNotEmpty) {
          return nestedToken;
        }
      }
      if (value is Iterable) {
        for (final element in value) {
          if (element is Map<String, dynamic>) {
            final nestedToken = _extractToken(element);
            if (nestedToken != null && nestedToken.isNotEmpty) {
              return nestedToken;
            }
          }
        }
      }
    }

    return null;
  }
}
