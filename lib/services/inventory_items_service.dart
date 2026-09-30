import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_http_client.dart';
import 'api_error.dart';

class InventoryItemsService {
  InventoryItemsService({http.Client? client})
      : _client = client ?? createAuthAwareClient();

  final http.Client _client;

  static final _itemsUri = Uri.parse(
    'https://crm.kokonuts.my/warehouse/api/v1/items'
    '?can_be_inventory=can_be_inventory',
  );

  Future<List<InventoryItem>> fetchItems({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(_itemsUri, headers: headers);
    } catch (error) {
      throw InventoryItemsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw InventoryItemsException(
        apiErrorMessage(response, 'Items request failed with status ${response.statusCode}: ${response.body}'),
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw InventoryItemsException('Unable to parse items response: $error');
    }

    final List<InventoryItem> items = [];
    _collectItems(decoded, items);
    final unique = <String, InventoryItem>{};
    for (final item in items) {
      unique[item.id] = item;
    }
    final deduped = unique.values.toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return deduped;
  }

  void _collectItems(dynamic source, List<InventoryItem> target) {
    if (source is Map<String, dynamic>) {
      final name = _readString(source, const [
        'name',
        'item_name',
        'itemName',
        'title',
        'sku_name',
        'skuName'
      ]);
      final id = _readString(source, const ['id', 'item_id', 'itemId', 'uid']);
      final skuCode = _readString(source, const ['sku_code', 'skuCode', 'sku']);
      final skuName =
          _readString(source, const ['sku_name', 'skuName', 'name']);
      final unitId = _readString(source, const ['unit_id', 'unitId']);
      final unitsPerBatch = double.tryParse(
        _readString(source, const ['units_per_batch', 'unitsPerBatch']) ?? '',
      );
      if (name != null && id != null) {
        target.add(InventoryItem(
          id: id,
          name: name,
          skuCode: skuCode,
          skuName: skuName,
          unitId: unitId,
          unitName: _readString(source, const ['unit', 'unit_name']),
          unitsPerBatch: unitsPerBatch,
        ));
      }
      for (final value in source.values) {
        _collectItems(value, target);
      }
    } else if (source is List) {
      for (final item in source) {
        _collectItems(item, target);
      }
    }
  }

  String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
      } else if (value is num) {
        return value.toString();
      }
    }
    return null;
  }
}

class InventoryItem {
  const InventoryItem({
    required this.id,
    required this.name,
    this.skuCode,
    this.skuName,
    this.unitId,
    this.unitName,
    this.unitsPerBatch,
  });

  final String id;
  final String name;
  final String? skuCode;
  final String? skuName;

  /// tblitems.unit_id — the unit type, not the item id.
  final String? unitId;

  /// Stock unit label, e.g. "gram(s)" or "unit(s)".
  final String? unitName;

  /// Stock units in one purchased batch (pack), used to prefill Units/Batch.
  final double? unitsPerBatch;
}

class InventoryItemsException implements Exception {
  InventoryItemsException(this.message);

  final String message;

  @override
  String toString() => message;
}
