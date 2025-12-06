import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_http_client.dart';

class WarehousesService {
  WarehousesService({http.Client? client})
      : _client = client ?? createAuthAwareClient();

  final http.Client _client;

  static const _warehousesUrl =
      'https://crm.kokonuts.my/warehouse/api/v1/warehouses';

  Future<List<Warehouse>> fetchWarehouses({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(
        Uri.parse(_warehousesUrl),
        headers: {'Accept': 'application/json', ...headers},
      );
    } catch (error) {
      throw WarehousesException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw WarehousesException(
        'Warehouses request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw WarehousesException('Unable to parse warehouses response: $error');
    }

    if (decoded is List) {
      return decoded
          .whereType<Map<String, dynamic>>()
          .map(Warehouse.fromJson)
          .toList(growable: false);
    }

    if (decoded is Map<String, dynamic>) {
      final values = decoded.values
          .whereType<List>()
          .expand((value) => value)
          .whereType<Map<String, dynamic>>()
          .map(Warehouse.fromJson)
          .toList(growable: false);
      if (values.isNotEmpty) {
        return values;
      }
    }

    throw WarehousesException('Unexpected warehouses response format.');
  }

  Future<void> createGoodsReceipt({
    required Map<String, String> headers,
    required CreateGoodsReceiptRequest request,
  }) async {
    http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_goodsReceiptsUrl),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(request.toJson()),
      );
    } catch (error) {
      throw WarehousesException('Failed to reach server: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw WarehousesException(
        'Goods receipt request failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  static const _goodsReceiptsUrl =
      'https://crm.kokonuts.my/warehouse/api/v1/goods_receipts';
}

class Warehouse {
  Warehouse({required this.id, required this.code, required this.name});

  factory Warehouse.fromJson(Map<String, dynamic> json) {
    return Warehouse(
      id: json['id']?.toString() ?? '',
      code: json['warehouse_code']?.toString() ??
          json['code']?.toString() ??
          '—',
      name: json['warehouse_name']?.toString() ??
          json['name']?.toString() ??
          '—',
    );
  }

  final String id;
  final String code;
  final String name;
}

class CreateGoodsReceiptRequest {
  CreateGoodsReceiptRequest({
    required this.supplierCode,
    required this.supplierName,
    required this.buyerId,
    required this.purOrderId,
    required this.date,
    required this.goodsReceiptCode,
    required this.warehouseId,
    required this.total,
    required this.addedFrom,
  });

  final String supplierCode;
  final String supplierName;
  final String buyerId;
  final String purOrderId;
  final DateTime date;
  final String goodsReceiptCode;
  final String warehouseId;
  final double total;
  final String addedFrom;

  Map<String, dynamic> toJson() {
    final formattedDate = _formatDate(date);
    return {
      'supplier_code': supplierCode,
      'supplier_name': supplierName,
      'deliver_name': '',
      'buyer_id': buyerId,
      'description': '',
      'pr_order_id': purOrderId,
      'date_c': formattedDate,
      'date_add': formattedDate,
      'goods_receipt_code': goodsReceiptCode,
      'warehouse_id': warehouseId,
      'total_tax_money': '0',
      'total_goods_money': total,
      'value_of_inventory': total,
      'total_money': total,
      'addedfrom': addedFrom,
      'approval': '1',
      'project': '',
      'type': '',
      'department': '0',
      'requester': '0',
      'expiry_date': null,
      'invoice_no': '',
    };
  }
}

class WarehousesException implements Exception {
  WarehousesException(this.message);

  final String message;

  @override
  String toString() => 'WarehousesException: $message';
}

String _formatDate(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  return '$year-$month-$day';
}
