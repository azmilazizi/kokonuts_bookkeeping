import 'dart:convert';

import 'package:http/http.dart' as http;

/// The reason the CRM API gave for a failed request, or [fallback] when the
/// response carries none.
///
/// The CRM answers errors as `{"status": false, "message": "...",
/// "errors": {"vendor": "Vendor is required.", ...}}`. Field errors are the
/// most specific, so they win over the generic "Validation failed." message.
String apiErrorMessage(http.Response response, String fallback) {
  dynamic decoded;
  try {
    decoded = jsonDecode(response.body);
  } catch (_) {
    return _withStatus(fallback, response.statusCode);
  }

  if (decoded is Map) {
    final details = <String>[];
    _collect(decoded['errors'], details);
    final unique = details.toSet().toList(growable: false);
    if (unique.isNotEmpty) {
      return unique.join('\n');
    }

    for (final key in const ['message', 'error', 'msg']) {
      final value = decoded[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
  } else if (decoded is String && decoded.trim().isNotEmpty) {
    return decoded.trim();
  }

  return _withStatus(fallback, response.statusCode);
}

void _collect(dynamic value, List<String> out) {
  if (value is String) {
    final text = value.trim();
    if (text.isNotEmpty) {
      out.add(text);
    }
  } else if (value is Map) {
    for (final entry in value.values) {
      _collect(entry, out);
    }
  } else if (value is List) {
    for (final entry in value) {
      _collect(entry, out);
    }
  }
}

String _withStatus(String message, int statusCode) =>
    message.contains('$statusCode') ? message : '$message (HTTP $statusCode)';
