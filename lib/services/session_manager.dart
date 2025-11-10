import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Handles reading and writing authentication state to persistent storage.
class SessionManager {
  static const _authTokenKey = 'auth_token';

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
