import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles reading and writing authentication state to persistent storage.
class SessionManager {
  static const _authTokenKey = 'auth_token';
  static const _usernameKey = 'username';

  static String _themePreferenceKey(String username) =>
      'theme_mode_${username.trim().toLowerCase()}';

  Future<String?> getAuthToken() async {
    final prefs = await _tryGetPreferences();
    return prefs?.getString(_authTokenKey);
  }

  Future<void> saveAuthToken(String token) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.setString(_authTokenKey, token);
  }

  Future<void> clearAuthToken() async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.remove(_authTokenKey);
  }

  Future<void> saveUsername(String username) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.setString(_usernameKey, username.trim());
  }

  Future<String?> getUsername() async {
    final prefs = await _tryGetPreferences();
    return prefs?.getString(_usernameKey);
  }

  Future<void> clearUsername() async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    await prefs.remove(_usernameKey);
  }

  Future<void> saveThemeMode({required String username, required ThemeMode mode}) async {
    final prefs = await _tryGetPreferences();
    if (prefs == null) {
      return;
    }

    final key = _themePreferenceKey(username);
    await prefs.setString(key, mode.name);
  }

  Future<ThemeMode?> getThemeMode(String username) async {
    final prefs = await _tryGetPreferences();
    final storedValue = prefs?.getString(_themePreferenceKey(username));
    if (storedValue == null) {
      return null;
    }

    return ThemeMode.values.firstWhere(
      (mode) => mode.name == storedValue,
      orElse: () => ThemeMode.light,
    );
  }

  Future<SharedPreferences?> _tryGetPreferences() async {
    try {
      return await SharedPreferences.getInstance();
    } on MissingPluginException catch (error, stackTrace) {
      // During hot restart on the web the shared_preferences plugin may not yet
      // be registered. Rather than crashing the app we gracefully fall back to
      // an in-memory session by returning null.
      debugPrint('SharedPreferences unavailable: $error');
      debugPrint('$stackTrace');
      return null;
    }
  }
}
