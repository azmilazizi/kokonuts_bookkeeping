import 'dart:convert';

import 'package:http/http.dart' as http;

class PurchaseOrdersService {
  PurchaseOrdersService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_orders';

  Future<PurchaseOrdersPage> fetchPurchaseOrders({
    required int page,
    required int perPage,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
    });

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw PurchaseOrdersException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw PurchaseOrdersException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOrdersException('Unable to parse response: $error');
    }

    final ordersList = _extractOrdersList(decoded);
    final orders = ordersList
        .whereType<Map<String, dynamic>>()
        .map(PurchaseOrder.fromJson)
        .toList();

    final pagination =
        _resolvePagination(decoded, currentPage: page, perPage: perPage);

    return PurchaseOrdersPage(
      orders: orders,
      hasMore: pagination.hasMore,
    );
  }

  List<dynamic> _extractOrdersList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      const preferredKeys = ['data', 'orders', 'purchase_orders', 'items'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final list = _extractOrdersList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }

      for (final value in decoded.values) {
        final list = _extractOrdersList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }
    }

    return const [];
  }

  PaginationInfo _resolvePagination(
    dynamic decoded, {
    required int currentPage,
    required int perPage,
  }) {
    if (decoded is Map<String, dynamic>) {
      final meta = _findMap(decoded, const ['meta', 'pagination']);
      if (meta != null) {
        final totalPages = _readInt(meta, ['last_page', 'total_pages']);
        final current = _readInt(meta, ['current_page', 'page']) ?? currentPage;
        if (totalPages != null) {
          return PaginationInfo(hasMore: current < totalPages);
        }
        final nextPage = _readInt(meta, ['next_page']);
        if (nextPage != null) {
          return PaginationInfo(hasMore: nextPage > current);
        }
      }

      final links = _findMap(decoded, const ['links']);
      if (links != null) {
        final nextUrl = _readString(links, ['next', 'next_page_url']);
        if (nextUrl != null && nextUrl.isNotEmpty) {
          return const PaginationInfo(hasMore: true);
        }
      }
    }

    return PaginationInfo(hasMore: _countItems(decoded) >= perPage);
  }

  Map<String, dynamic>? _findMap(
      Map<String, dynamic> source, List<String> keys) {
    for (final key in keys) {
      final value = source[key];
      if (value is Map<String, dynamic>) {
        return value;
      }
    }

    for (final value in source.values) {
      if (value is Map<String, dynamic>) {
        final nested = _findMap(value, keys);
        if (nested != null) {
          return nested;
        }
      }
    }

    return null;
  }

  int _countItems(dynamic decoded) {
    final list = _extractOrdersList(decoded);
    return list.length;
  }

  int? _readInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) {
        continue;
      }
      if (value is int) {
        return value;
      }
      if (value is String) {
        final parsed = int.tryParse(value);
        if (parsed != null) {
          return parsed;
        }
      }
    }
    return null;
  }

  String? _readString(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value is String && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }
}

class PurchaseOrdersPage {
  const PurchaseOrdersPage({required this.orders, required this.hasMore});

  final List<PurchaseOrder> orders;
  final bool hasMore;
}

class PurchaseOrder {
  const PurchaseOrder({
    required this.id,
    required this.number,
    required this.name,
    required this.vendorName,
    required this.orderDate,
    required this.totalAmount,
    required this.totalLabel,
    required this.currencySymbol,
    required this.deliveryStatus,
  });

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    final totalValue = json['total'];
    final totalAmount = _parseDouble(totalValue);
    final currency = json['currency_symbol'] ?? json['currency'];
    final vendorData = json['vendor'];
    String? resolvedVendor;
    if (vendorData is Map<String, dynamic>) {
      resolvedVendor = _stringValue(vendorData['name']);
    }
    return PurchaseOrder(
      id: _stringValue(json['id']) ?? '',
      number: _stringValue(json['pur_order_number']) ??
          _stringValue(json['number']) ??
          _stringValue(json['order_number']) ??
          '—',
      name: _stringValue(json['pur_order_name']) ??
          _stringValue(json['name']) ??
          '—',
      vendorName: resolvedVendor ??
          _stringValue(json['vendor_name']) ??
          '—',
      orderDate: _parseDateString(
        _stringValue(json['order_date']) ??
            _stringValue(json['created_at']) ??
            '',
      ),
      totalAmount: totalAmount,
      totalLabel:
          totalAmount != null ? totalAmount.toStringAsFixed(2) : _formatAmount(totalValue),
      currencySymbol: _stringValue(currency) ?? '',
      deliveryStatus: _parseDeliveryStatus(json),
    );
  }

  final String id;
  final String number;
  final String name;
  final String vendorName;
  final DateTime? orderDate;
  final double? totalAmount;
  final String totalLabel;
  final String currencySymbol;
  final int deliveryStatus;

  String get formattedDate {
    final date = orderDate;
    if (date == null) {
      return '—';
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day-$month-$year';
  }

  static String? _stringValue(dynamic value) {
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
}

int _parseDeliveryStatus(Map<String, dynamic> json) {
  final directValue = _parseInt(json['delivery_status']) ??
      _parseInt(json['delivery_status_id']) ??
      _parseInt(json['delivery_status_code']) ??
      _parseInt(json['delivery_status_value']);

  if (directValue != null) {
    return directValue;
  }

  final nestedValue = _parseNestedDeliveryStatus(json['delivery_status']);
  if (nestedValue != null) {
    return nestedValue;
  }

  final fallback = _parseInt(json['status']) ?? _parseInt(json['status_id']);
  if (fallback != null) {
    return fallback;
  }

  return 0;
}

int? _parseNestedDeliveryStatus(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _parseInt(value['id']) ??
        _parseInt(value['code']) ??
        _parseInt(value['value']) ??
        _parseInt(value['status']);
  }
  return _parseInt(value);
}

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class PurchaseOrdersException implements Exception {
  const PurchaseOrdersException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOrdersException: $message';
}

DateTime? _parseDateString(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }

  final normalized = trimmed.replaceAll('/', '-');
  final direct = _tryParseDate(normalized);
  if (direct != null) {
    return direct;
  }

  final parts = normalized.split(RegExp(r'\s+'));
  final datePart = parts.first;
  final timePart = parts.length > 1 ? parts.sublist(1).join(' ') : null;

  final segments = datePart.split('-');
  if (segments.length == 3) {
    if (segments[0].length == 4) {
      final isoDate =
          '${segments[0]}-${segments[1].padLeft(2, '0')}-${segments[2].padLeft(2, '0')}';
      final candidate =
          timePart != null && timePart.isNotEmpty ? '$isoDate $timePart' : isoDate;
      final parsed = _tryParseDate(candidate);
      if (parsed != null) {
        return parsed;
      }
    }

    if (segments[2].length == 4) {
      final day = int.tryParse(segments[0]);
      final month = int.tryParse(segments[1]);
      final year = int.tryParse(segments[2]);
      if (day != null && month != null && year != null) {
        final time = _parseTimeComponents(timePart);
        return DateTime(year, month, day, time[0], time[1], time[2]);
      }
    }
  }

  return null;
}

DateTime? _tryParseDate(String value) {
  try {
    return DateTime.parse(value);
  } catch (_) {
    return null;
  }
}

int? _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }
  return null;
}

List<int> _parseTimeComponents(String? value) {
  if (value == null || value.trim().isEmpty) {
    return const [0, 0, 0];
  }
  final segments = value.trim().split(':');
  final result = <int>[];
  for (var i = 0; i < segments.length && i < 3; i++) {
    result.add(int.tryParse(segments[i]) ?? 0);
  }
  while (result.length < 3) {
    result.add(0);
  }
  return result;
}

String _formatAmount(dynamic value) {
  if (value is num) {
    return value.toStringAsFixed(2);
  }
  final stringValue = PurchaseOrder._stringValue(value);
  if (stringValue == null) {
    return '0.00';
  }
  final parsed = double.tryParse(stringValue);
  if (parsed != null) {
    return parsed.toStringAsFixed(2);
  }
  return stringValue;
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
    return double.tryParse(trimmed);
  }
  return null;
}

