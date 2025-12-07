import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_http_client.dart';

class InventoryOptionsService {
  InventoryOptionsService({http.Client? client})
      : _client = client ?? createAuthAwareClient();

  final http.Client _client;

  static const _optionsUrl = 'https://crm.kokonuts.my/api/v1/options';
  static const _optionUrl = 'https://crm.kokonuts.my/api/v1/option';

  Future<String?> fetchInventoryReceivedPrefix({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(
        Uri.parse(_optionsUrl),
        headers: {'Accept': 'application/json', ...headers},
      );
    } catch (error) {
      throw InventoryOptionsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw InventoryOptionsException(
        'Options request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw InventoryOptionsException('Unable to parse options response: $error');
    }

    return _extractPrefix(decoded);
  }

  Future<LotNumberSettings> fetchLotNumberSettings({
    required Map<String, String> headers,
  }) async {
    final values = await Future.wait([
      _fetchOptionValue(headers: headers, optionKey: 'lot_number_prefix'),
      _fetchOptionValue(headers: headers, optionKey: 'next_lot_number'),
    ]);

    final prefix = values[0];
    final nextLotNumber = int.tryParse(values[1] ?? '');

    if (prefix == null || nextLotNumber == null) {
      throw InventoryOptionsException(
        'Lot number options could not be loaded.',
      );
    }

    return LotNumberSettings(prefix: prefix, nextLotNumber: nextLotNumber);
  }

  Future<String?> _fetchOptionValue({
    required Map<String, String> headers,
    required String optionKey,
  }) async {
    http.Response response;
    try {
      response = await _client.get(
        Uri.parse('$_optionUrl/$optionKey'),
        headers: {'Accept': 'application/json', ...headers},
      );
    } catch (error) {
      throw InventoryOptionsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw InventoryOptionsException(
        'Option $optionKey request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw InventoryOptionsException('Unable to parse option $optionKey: $error');
    }

    if (decoded is Map<String, dynamic>) {
      final value = decoded['value']?.toString();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    return null;
  }

  String? _extractPrefix(dynamic source) {
    if (source is Map<String, dynamic>) {
      final nameValue = source['name']?.toString().toLowerCase();
      if (nameValue == 'inventory_received_number_prefix') {
        return source['value']?.toString();
      }
      for (final value in source.values) {
        final result = _extractPrefix(value);
        if (result != null) {
          return result;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final result = _extractPrefix(item);
        if (result != null) {
          return result;
        }
      }
    }
    return null;
  }
}

class InventoryOptionsException implements Exception {
  InventoryOptionsException(this.message);

  final String message;

  @override
  String toString() => 'InventoryOptionsException: $message';
}

class LotNumberSettings {
  const LotNumberSettings({
    required this.prefix,
    required this.nextLotNumber,
  });

  final String prefix;
  final int nextLotNumber;
}
