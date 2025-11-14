import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches a single purchase order and maps it to strongly typed classes.
class PurchaseOrderDetailService {
  PurchaseOrderDetailService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_order';

  /// Retrieves the purchase order that matches the provided [id].
  Future<PurchaseOrderDetail> fetchPurchaseOrder({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw PurchaseOrderDetailException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw PurchaseOrderDetailException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOrderDetailException('Unable to parse response: $error');
    }

    final orderMap = _extractOrderMap(decoded);
    if (orderMap == null) {
      throw const PurchaseOrderDetailException(
        'Purchase order details were not found in the response.',
      );
    }

    return PurchaseOrderDetail.fromJson(orderMap);
  }

  Map<String, dynamic>? _extractOrderMap(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (_looksLikeOrder(data)) {
        return data;
      }

      const preferredKeys = [
        'data',
        'purchase_order',
        'purchaseOrder',
        'order',
      ];

      for (final key in preferredKeys) {
        final value = data[key];
        final candidate = _extractOrderMap(value);
        if (candidate != null) {
          return candidate;
        }
      }

      for (final value in data.values) {
        final candidate = _extractOrderMap(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    if (data is List) {
      for (final value in data) {
        final candidate = _extractOrderMap(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    return null;
  }

  bool _looksLikeOrder(Map<String, dynamic> data) {
    if (!data.containsKey('id')) {
      return false;
    }
    final hasNumber = data.containsKey('pur_order_number') ||
        data.containsKey('order_number') ||
        data.containsKey('number');
    final hasItems = data['items'] is List ||
        (data['items'] is Map<String, dynamic>);
    return hasNumber || hasItems;
  }
}

/// The parsed representation of a purchase order.
class PurchaseOrderDetail {
  PurchaseOrderDetail({
    required this.id,
    required this.number,
    required this.name,
    required this.status,
    required this.vendorName,
    required this.currencySymbol,
    required this.subtotalLabel,
    required this.totalLabel,
    required this.items,
    this.orderDate,
    this.deliveryDate,
    this.reference,
    this.notes,
    this.terms,
  });

  factory PurchaseOrderDetail.fromJson(Map<String, dynamic> json) {
    final currencySymbol = _string(json['currency_symbol']) ??
        _string(json['currency']) ??
        _string(json['currency_name']) ??
        '';

    final subtotalValue = json['subtotal'] ?? json['sub_total'];
    final subtotalLabel = _string(json['subtotal_formatted']) ??
        _string(json['sub_total_formatted']) ??
        _formatCurrency(currencySymbol, subtotalValue);

    final totalValue = json['total'];
    final totalLabel = _string(json['total_formatted']) ??
        _string(json['grand_total_formatted']) ??
        _formatCurrency(currencySymbol, totalValue);

    final vendorName = _string(json['vendor_name']) ??
        _string(json['supplier_name']) ??
        _parseNestedName(json['vendor']) ??
        _parseNestedName(json['supplier']) ??
        '—';

    final statusLabel = _string(json['status_label']) ??
        _string(json['status_text']) ??
        _parseNestedName(json['status']) ??
        _string(json['status']) ??
        '—';

    final items = _extractItems(json['items'])
        .whereType<Map<String, dynamic>>()
        .map((item) => PurchaseOrderItem.fromJson(
              item,
              currencySymbol: currencySymbol,
            ))
        .toList();

    return PurchaseOrderDetail(
      id: _string(json['id']) ?? '',
      number: _string(json['pur_order_number']) ??
          _string(json['order_number']) ??
          _string(json['number']) ??
          '—',
      name: _string(json['pur_order_name']) ??
          _string(json['name']) ??
          '—',
      status: statusLabel,
      vendorName: vendorName,
      currencySymbol: currencySymbol,
      subtotalLabel: subtotalLabel,
      totalLabel: totalLabel,
      items: items,
      orderDate: _parseDate(json['order_date']) ??
          _parseDate(json['created_at']),
      deliveryDate: _parseDate(json['delivery_date']) ??
          _parseDate(json['expected_delivery_date']),
      reference: _string(json['reference_no']) ??
          _string(json['reference']) ??
          _string(json['ref_number']),
      notes: _string(json['notes']) ?? _string(json['note']),
      terms: _string(json['terms']) ?? _string(json['term']),
    );
  }

  final String id;
  final String number;
  final String name;
  final String status;
  final String vendorName;
  final DateTime? orderDate;
  final DateTime? deliveryDate;
  final String? reference;
  final String currencySymbol;
  final String subtotalLabel;
  final String totalLabel;
  final String? notes;
  final String? terms;
  final List<PurchaseOrderItem> items;

  String get orderDateLabel => _formatDate(orderDate) ?? '—';

  String get deliveryDateLabel => _formatDate(deliveryDate) ?? '—';

  String? get referenceLabel =>
      reference != null && reference!.trim().isNotEmpty ? reference : null;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get hasTerms => terms != null && terms!.trim().isNotEmpty;
}

/// Represents a single line item within a purchase order.
class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.name,
    required this.description,
    required this.quantityLabel,
    required this.rateLabel,
    required this.amountLabel,
  });

  factory PurchaseOrderItem.fromJson(
    Map<String, dynamic> json, {
    required String currencySymbol,
  }) {
    final quantity = json['quantity'] ?? json['qty'] ?? json['ordered_quantity'];
    final quantityUnit = _string(json['unit']) ?? _string(json['unit_name']);
    final quantityLabel = _formatQuantity(quantity, unit: quantityUnit);

    final rateValue = json['rate'] ?? json['price'] ?? json['unit_price'];
    final rateLabel = _string(json['rate_formatted']) ??
        _string(json['price_formatted']) ??
        _string(json['unit_price_formatted']) ??
        _formatCurrency(currencySymbol, rateValue);

    final amountValue = json['amount'] ??
        json['total'] ??
        json['line_total'] ??
        json['subtotal'];
    final amountLabel = _string(json['amount_formatted']) ??
        _string(json['total_formatted']) ??
        _string(json['line_total_formatted']) ??
        _formatCurrency(currencySymbol, amountValue);

    final descriptions = <String>{};
    final descriptionKeys = [
      'description',
      'item_description',
      'long_description',
      'detail',
    ];
    for (final key in descriptionKeys) {
      final value = _string(json[key]);
      if (value != null && value.isNotEmpty) {
        descriptions.add(value);
      }
    }

    final description = descriptions.isEmpty
        ? '—'
        : descriptions.join('\n');

    return PurchaseOrderItem(
      name: _string(json['item_name']) ??
          _string(json['name']) ??
          _string(json['item']) ??
          '—',
      description: description,
      quantityLabel: quantityLabel,
      rateLabel: rateLabel,
      amountLabel: amountLabel,
    );
  }

  final String name;
  final String description;
  final String quantityLabel;
  final String rateLabel;
  final String amountLabel;
}

/// Thrown when the purchase order details request fails.
class PurchaseOrderDetailException implements Exception {
  const PurchaseOrderDetailException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOrderDetailException: $message';
}

List<dynamic> _extractItems(dynamic source) {
  if (source is List) {
    return source;
  }
  if (source is Map<String, dynamic>) {
    if (source.containsKey('data')) {
      return _extractItems(source['data']);
    }
    if (source.containsKey('items')) {
      return _extractItems(source['items']);
    }
    return source.values
        .map(_extractItems)
        .expand((element) => element)
        .toList();
  }
  return const [];
}

String? _string(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is num || value is bool) {
    return value.toString();
  }
  return value.toString();
}

String _formatCurrency(String symbol, dynamic value) {
  final parsed = _parseDouble(value);
  if (parsed == null) {
    final fallback = _string(value);
    if (fallback != null) {
      return fallback;
    }
    return symbol.isEmpty ? '0.00' : '$symbol 0.00';
  }

  final formatted = parsed.toStringAsFixed(2);
  if (symbol.isEmpty) {
    return formatted;
  }
  return '$symbol $formatted';
}

String _formatQuantity(dynamic value, {String? unit}) {
  final parsed = _parseDouble(value);
  if (parsed == null) {
    final fallback = _string(value);
    if (fallback == null) {
      return '—';
    }
    return unit != null && unit.isNotEmpty ? '$fallback $unit' : fallback;
  }

  final hasDecimals = parsed % 1 != 0;
  final formatted = hasDecimals
      ? parsed.toStringAsFixed(2)
      : parsed.toStringAsFixed(0);
  return unit != null && unit.isNotEmpty ? '$formatted $unit' : formatted;
}

String? _parseNestedName(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _string(value['name']) ??
        _string(value['label']) ??
        _string(value['title']);
  }
  return _string(value);
}

double? _parseDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed.replaceAll(',', ''));
  }
  return null;
}

DateTime? _parseDate(dynamic value) {
  final stringValue = _string(value);
  if (stringValue == null) {
    return null;
  }

  final normalized = stringValue.replaceAll('/', '-');
  try {
    return DateTime.parse(normalized);
  } catch (_) {
    final datePart = normalized.split(' ').first;
    final segments = datePart.split('-');
    if (segments.length == 3) {
      int? year;
      int? month;
      int? day;

      if (segments[0].length == 4) {
        year = int.tryParse(segments[0]);
        month = int.tryParse(segments[1]);
        day = int.tryParse(segments[2]);
      } else if (segments[2].length == 4) {
        year = int.tryParse(segments[2]);
        month = int.tryParse(segments[1]);
        day = int.tryParse(segments[0]);
      }

      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
  }

  return null;
}

String? _formatDate(DateTime? value) {
  if (value == null) {
    return null;
  }
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString().padLeft(4, '0');
  return '$day-$month-$year';
}
