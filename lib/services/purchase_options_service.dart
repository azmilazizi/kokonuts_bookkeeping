import 'dart:convert';

import 'package:http/http.dart' as http;

class PurchaseOptionsService {
  PurchaseOptionsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _optionsUrl = 'https://crm.kokonuts.my/purchase/api/v1/options';

  Future<int?> fetchNextPurchaseOrderNumber({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(Uri.parse(_optionsUrl), headers: headers);
    } catch (error) {
      throw PurchaseOptionsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw PurchaseOptionsException(
        'Options request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOptionsException('Unable to parse options response: $error');
    }

    return _extractNextPurchaseOrderNumber(decoded);
  }

  int? _extractNextPurchaseOrderNumber(dynamic source) {
    if (source is Map<String, dynamic>) {
      for (final entry in source.entries) {
        final key = entry.key.toLowerCase();
        if (key == 'next_po_number' ||
            key == 'nextponumber' ||
            key == 'next_po' ||
            key == 'nextpo') {
          return _asInt(entry.value);
        }
      }
      for (final value in source.values) {
        final result = _extractNextPurchaseOrderNumber(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractNextPurchaseOrderNumber(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }

  int? _asInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is double) {
      return value.round();
    }
    if (value is String) {
      final parsed = int.tryParse(value.trim());
      return parsed;
    }
    return null;
  }
}

class PurchaseOptionsException implements Exception {
  PurchaseOptionsException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOptionsException: $message';
}
