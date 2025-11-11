import 'dart:convert';

import 'package:http/http.dart' as http;

class BillsService {
  BillsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://crm.kokonuts.my/accounting/api/v1/bills';
  static const _vendorBaseUrl = 'https://crm.kokonuts.my/purchase/api/v1/vendors';

  final Map<String, String?> _vendorCache = {};

  Future<BillsPage> fetchBills({
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
      throw BillsException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw BillsException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse response: $error');
    }

    final billsList = _extractBillsList(decoded);
    final bills = billsList
        .whereType<Map<String, dynamic>>()
        .map(Bill.fromJson)
        .toList();

    final pagination = _resolvePagination(decoded, currentPage: page, perPage: perPage);

    return BillsPage(bills: bills, hasMore: pagination.hasMore);
  }

  Future<String?> resolveVendorName({
    required String vendorId,
    required Map<String, String> headers,
  }) async {
    if (vendorId.isEmpty) {
      return null;
    }

    if (_vendorCache.containsKey(vendorId)) {
      return _vendorCache[vendorId];
    }

    final uri = Uri.parse('$_vendorBaseUrl/$vendorId');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw BillsException('Failed to load vendor: $error');
    }

    if (response.statusCode != 200) {
      throw BillsException(
        'Vendor request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillsException('Unable to parse vendor response: $error');
    }

    String? vendorName;
    if (decoded is Map<String, dynamic>) {
      vendorName = _stringValue(decoded['name']) ??
          _stringValue(decoded['vendor_name']) ??
          _stringValue(decoded['company_name']);
      if (vendorName == null) {
        final candidate = _findMap(decoded, const ['data', 'vendor']);
        if (candidate != null) {
          vendorName = _stringValue(candidate['name']) ??
              _stringValue(candidate['vendor_name']) ??
              _stringValue(candidate['company_name']);
        }
      }
    } else if (decoded is List) {
      for (final item in decoded) {
        if (item is Map<String, dynamic>) {
          vendorName = _stringValue(item['name']) ??
              _stringValue(item['vendor_name']) ??
              _stringValue(item['company_name']);
          if (vendorName != null && vendorName.isNotEmpty) {
            break;
          }
        }
      }
    }

    _vendorCache[vendorId] = vendorName;
    return vendorName;
  }

  List<dynamic> _extractBillsList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      const preferredKeys = ['data', 'bills', 'results', 'items'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final list = _extractBillsList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }

      for (final value in decoded.values) {
        final list = _extractBillsList(value);
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

  Map<String, dynamic>? _findMap(dynamic source, List<String> keys) {
    if (source is Map<String, dynamic>) {
      for (final key in keys) {
        final value = source[key];
        if (value is Map<String, dynamic>) {
          return value;
        }
      }
      for (final value in source.values) {
        final nested = _findMap(value, keys);
        if (nested != null) {
          return nested;
        }
      }
    } else if (source is List) {
      for (final item in source) {
        final nested = _findMap(item, keys);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  int _countItems(dynamic decoded) {
    final list = _extractBillsList(decoded);
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

class BillsPage {
  const BillsPage({required this.bills, required this.hasMore});

  final List<Bill> bills;
  final bool hasMore;
}

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class BillsException implements Exception {
  BillsException(this.message);

  final String message;

  @override
  String toString() => 'BillsException: $message';
}

class Bill {
  const Bill({
    required this.id,
    required this.vendorId,
    required this.dueDate,
    required this.status,
    required this.totalAmount,
    required this.currencySymbol,
  });

  factory Bill.fromJson(Map<String, dynamic> json) {
    final totalValue = json['amount'] ?? json['total'];
    final statusValue = json['status'];
    return Bill(
      id: _stringValue(json['id']) ?? '',
      vendorId: _stringValue(json['vendor_id']) ?? '',
      dueDate: _parseDate(_stringValue(json['due_date'])) ?? _parseDate(_stringValue(json['date'])),
      status: BillStatus.fromCode(_parseInt(statusValue)),
      totalAmount: _parseDouble(totalValue),
      currencySymbol: _stringValue(json['currency_symbol']) ?? _stringValue(json['currency']) ?? '',
    );
  }

  final String id;
  final String vendorId;
  final DateTime? dueDate;
  final BillStatus status;
  final double? totalAmount;
  final String currencySymbol;

  String get formattedDueDate {
    final date = dueDate;
    if (date == null) {
      return '-';
    }
    final day = date.day.toString().padLeft(2, '0');
    final month = date.month.toString().padLeft(2, '0');
    final year = date.year.toString().padLeft(4, '0');
    return '$day-$month-$year';
  }

  String get totalLabel {
    final amount = totalAmount;
    if (amount == null) {
      return '-';
    }
    final formatted = amount.toStringAsFixed(2);
    if (currencySymbol.isNotEmpty && currencySymbol.toLowerCase() != '0') {
      return '$currencySymbol $formatted';
    }
    return formatted;
  }

  static double? _parseDouble(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    if (value is double) {
      return value.toInt();
    }
    return null;
  }

  static DateTime? _parseDate(String? value) {
    if (value == null || value.isEmpty) {
      return null;
    }
    try {
      return DateTime.tryParse(value);
    } catch (_) {
      return null;
    }
  }
}

String? _stringValue(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  return value.toString();
}

class BillStatus {
  const BillStatus._(this.code, this.label);

  final int code;
  final String label;

  static const unpaid = BillStatus._(0, 'Unpaid');
  static const notApproved = BillStatus._(1, 'Not Approved');
  static const paid = BillStatus._(2, 'Paid');

  static const _all = [unpaid, notApproved, paid];

  static BillStatus fromCode(int? code) {
    if (code == null) {
      return unpaid;
    }
    return _all.firstWhere((status) => status.code == code, orElse: () => unpaid);
  }
}
