import 'dart:convert';

import 'package:http/http.dart' as http;

class Bill {
  Bill({
    required this.id,
    required this.billNumber,
    required this.billName,
    required this.total,
    required this.currencySymbol,
    this.vendorId,
    this.vendorName = '',
    this.billDate,
    this.rawBillDate,
    this.dueDate,
    this.rawDueDate,
    this.status,
  });

  final int id;
  final String billNumber;
  final String billName;
  final double total;
  final String currencySymbol;
  final int? vendorId;
  final String vendorName;
  final DateTime? billDate;
  final String? rawBillDate;
  final DateTime? dueDate;
  final String? rawDueDate;
  final int? status;

  factory Bill.fromJson(Map<String, dynamic> json) {
    final currencySymbol = json['currency_symbol']?.toString();
    final currencyName = json['currency_name']?.toString();
    final resolvedCurrency = (currencySymbol == null || currencySymbol.isEmpty)
        ? (currencyName == null || currencyName.isEmpty ? '' : currencyName)
        : currencySymbol;

    String vendorName = '';
    final vendorNameField = json['vendor_name'];
    if (vendorNameField is String && vendorNameField.trim().isNotEmpty) {
      vendorName = vendorNameField.trim();
    } else {
      final vendorField = json['vendor'];
      if (vendorField is Map<String, dynamic>) {
        vendorName = _firstNonEmpty([
              vendorField['vendor_name'],
              vendorField['name'],
              vendorField['company_name'],
              vendorField['display_name'],
            ])
                ?.toString() ??
            '';
      } else if (vendorField is String && vendorField.trim().isNotEmpty) {
        vendorName = vendorField.trim();
      }
    }
    vendorName = vendorName.trim();

    return Bill(
      id: _parseInt(json['id']) ?? 0,
      billNumber: _firstNonEmpty([
            json['bill_number'],
            json['bill_no'],
            json['reference_number'],
            json['bill_ref'],
          ])?.toString() ??
          '',
      billName: _firstNonEmpty([
            json['bill_name'],
            json['vendor_name'],
            json['description'],
            json['title'],
          ])?.toString() ??
          '',
      total: _parseDouble(_firstNonEmpty([
            json['total'],
            json['amount'],
            json['grand_total'],
          ])) ??
          0,
      currencySymbol: resolvedCurrency,
      vendorId: _parseInt(json['vendor_id']),
      vendorName: vendorName,
      billDate: _parseDate(_firstNonEmpty([
        json['bill_date'],
        json['issue_date'],
        json['date'],
        json['created_at'],
      ])),
      rawBillDate: _firstNonEmpty([
        json['bill_date'],
        json['issue_date'],
        json['date'],
        json['created_at'],
      ])
          ?.toString(),
      dueDate: _parseDate(_firstNonEmpty([
        json['due_date'],
        json['payment_due'],
        json['expected_payment_date'],
      ])),
      rawDueDate: _firstNonEmpty([
        json['due_date'],
        json['payment_due'],
        json['expected_payment_date'],
      ])
          ?.toString(),
      status: _parseInt(json['status']),
    );
  }

  String get formattedTotal {
    final formatted = total.toStringAsFixed(2);
    if (currencySymbol.isEmpty) {
      return formatted;
    }
    return '$currencySymbol $formatted';
  }

  String? get dateLabel {
    if (billDate != null) {
      final day = billDate!.day.toString().padLeft(2, '0');
      final month = billDate!.month.toString().padLeft(2, '0');
      final year = billDate!.year.toString();
      return '$day-$month-$year';
    }
    final trimmed = rawBillDate?.trim();
    return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  String? get dueDateLabel {
    if (dueDate != null) {
      final day = dueDate!.day.toString().padLeft(2, '0');
      final month = dueDate!.month.toString().padLeft(2, '0');
      final year = dueDate!.year.toString();
      return '$day-$month-$year';
    }
    final trimmed = rawDueDate?.trim();
    return (trimmed != null && trimmed.isNotEmpty) ? trimmed : null;
  }

  String get statusLabel {
    final value = status;
    if (value == null) {
      return '—';
    }
    switch (value) {
      case 0:
        return 'Unpaid';
      case 1:
        return 'Not Approved';
      case 2:
        return 'Paid';
      default:
        return 'Unknown';
    }
  }

  Bill copyWith({String? vendorName}) {
    return Bill(
      id: id,
      billNumber: billNumber,
      billName: billName,
      total: total,
      currencySymbol: currencySymbol,
      vendorId: vendorId,
      vendorName: (vendorName ?? this.vendorName).trim(),
      billDate: billDate,
      rawBillDate: rawBillDate,
      dueDate: dueDate,
      rawDueDate: rawDueDate,
      status: status,
    );
  }

  static dynamic _firstNonEmpty(List<dynamic> values) {
    for (final value in values) {
      if (value == null) {
        continue;
      }
      if (value is String) {
        if (value.trim().isEmpty) {
          continue;
        }
        return value;
      }
      return value;
    }
    return null;
  }

  static int? _parseInt(dynamic value) {
    if (value is int) {
      return value;
    }
    if (value is String) {
      return int.tryParse(value);
    }
    if (value is double) {
      return value.round();
    }
    return null;
  }

  static double? _parseDouble(dynamic value) {
    if (value is double) {
      return value;
    }
    if (value is int) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value);
    }
    return null;
  }

  static DateTime? _parseDate(dynamic value) {
    if (value is DateTime) {
      return value;
    }
    if (value is String) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return null;
      }
      try {
        return DateTime.parse(trimmed);
      } catch (_) {
        final delimiterMatch = RegExp(r'[-/]').allMatches(trimmed).isNotEmpty;
        final parts = delimiterMatch ? trimmed.split(RegExp(r'[-/]')) : null;
        if (parts != null && parts.length == 3) {
          final first = int.tryParse(parts[0]);
          final second = int.tryParse(parts[1]);
          final third = int.tryParse(parts[2]);
          if (first != null && second != null && third != null) {
            if (parts[0].length == 4) {
              return DateTime(first, second, third);
            }
            return DateTime(third, second, first);
          }
        }
      }
    }
    return null;
  }
}

class BillPage {
  BillPage({required this.bills, this.nextPage});

  final List<Bill> bills;
  final int? nextPage;

  bool get hasMore => nextPage != null;
}

class BillException implements Exception {
  BillException(this.message);

  final String message;

  @override
  String toString() => 'BillException: $message';
}

class BillsService {
  BillsService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://crm.kokonuts.my/accounting/api/v1/bills';
  static const _vendorBaseUrl = 'https://crm.kokonuts.my/api/v1/purchase/vendors';

  final http.Client _client;
  final Map<int, String?> _vendorNameCache = <int, String?>{};

  Future<BillPage> fetchBills({
    Map<String, String>? headers,
    int page = 1,
    int perPage = 20,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(
      queryParameters: {
        'page': '$page',
        'per_page': '$perPage',
      },
    );

    final requestHeaders = <String, String>{
      'Accept': 'application/json',
      ...?headers,
    };

    late http.Response response;
    try {
      response = await _client.get(uri, headers: requestHeaders);
    } catch (_) {
      throw BillException('Unable to reach the server. Please try again later.');
    }

    if (response.statusCode != 200) {
      throw BillException('Failed to load bills (status code ${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    final payload = _extractPayload(decoded);
    final bills = _parseBills(payload.items);
    final enrichedBills = await _attachVendorNames(bills);
    final nextPage = _parseNextPage(
      decoded,
      paginationSource: payload.pagination,
      currentPage: page,
      perPage: perPage,
      itemCount: enrichedBills.length,
    );

    return BillPage(bills: enrichedBills, nextPage: nextPage);
  }

  List<Bill> _parseBills(List<dynamic> items) {
    return items
        .whereType<Map<String, dynamic>>()
        .map(Bill.fromJson)
        .toList(growable: false);
  }

  Future<List<Bill>> _attachVendorNames(List<Bill> bills) async {
    if (bills.isEmpty) {
      return bills;
    }

    final idsToFetch = <int>{};
    for (final bill in bills) {
      final vendorId = bill.vendorId;
      if (vendorId != null && vendorId > 0 && bill.vendorName.trim().isNotEmpty) {
        _vendorNameCache.putIfAbsent(vendorId, () => bill.vendorName.trim());
        continue;
      }
      if (vendorId != null && vendorId > 0 && bill.vendorName.trim().isEmpty) {
        if (!_vendorNameCache.containsKey(vendorId)) {
          idsToFetch.add(vendorId);
        }
      }
    }

    for (final id in idsToFetch) {
      _vendorNameCache[id] = await _fetchVendorName(id);
    }

    return bills
        .map((bill) {
          final vendorId = bill.vendorId;
          if (vendorId != null) {
            final cached = _vendorNameCache[vendorId];
            if (cached != null && cached.isNotEmpty) {
              return bill.copyWith(vendorName: cached.trim());
            }
          }
          return bill;
        })
        .toList(growable: false);
  }

  Future<String?> _fetchVendorName(int vendorId) async {
    final uri = Uri.parse('$_vendorBaseUrl/$vendorId');
    final requestHeaders = <String, String>{
      'Accept': 'application/json',
    };

    try {
      final response = await _client.get(uri, headers: requestHeaders);
      if (response.statusCode != 200) {
        return null;
      }
      final decoded = jsonDecode(response.body);
      final name = _extractVendorName(decoded);
      return name;
    } catch (_) {
      return null;
    }
  }

  String? _extractVendorName(dynamic value) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }
    if (value is Map<String, dynamic>) {
      final directCandidates = [
        value['vendor_name'],
        value['name'],
        value['company_name'],
        value['display_name'],
        value['title'],
      ];
      for (final candidate in directCandidates) {
        final resolved = _extractVendorName(candidate);
        if (resolved != null) {
          return resolved;
        }
      }
      final nestedKeys = ['vendor', 'data', 'result', 'item'];
      for (final key in nestedKeys) {
        final nested = _extractVendorName(value[key]);
        if (nested != null) {
          return nested;
        }
      }
      for (final entry in value.entries) {
        final nested = _extractVendorName(entry.value);
        if (nested != null) {
          return nested;
        }
      }
      return null;
    }
    if (value is List) {
      for (final item in value) {
        final resolved = _extractVendorName(item);
        if (resolved != null) {
          return resolved;
        }
      }
    }
    return null;
  }

  int? _parseNextPage(
    dynamic decoded, {
    Map<String, dynamic>? paginationSource,
    required int currentPage,
    required int perPage,
    required int itemCount,
  }) {
    int? nextPage;
    final pagination = paginationSource ?? _findPaginationMap(decoded);
    if (pagination != null) {
      nextPage ??= _resolveFromMeta(pagination);
    }

    nextPage ??= _resolveFromLinks(decoded);

    if (nextPage != null) {
      return nextPage;
    }

    if (itemCount >= perPage) {
      return currentPage + 1;
    }

    return null;
  }

  _Payload _extractPayload(dynamic decoded) {
    if (decoded is List) {
      return _Payload(items: decoded);
    }

    if (decoded is Map<String, dynamic>) {
      final prioritizedKeys = ['data', 'results', 'items'];

      for (final key in prioritizedKeys) {
        final value = decoded[key];
        if (value is List) {
          return _Payload(
            items: value,
            pagination: _firstPagination([
              _looksLikePagination(decoded) ? decoded : null,
              _extractMetaMap(decoded),
            ]),
          );
        }
        if (value is Map<String, dynamic>) {
          final nested = _extractPayload(value);
          if (nested.items.isNotEmpty || nested.pagination != null) {
            return _Payload(
              items: nested.items,
              pagination: nested.pagination ??
                  _firstPagination([
                    _looksLikePagination(value) ? value : null,
                    _looksLikePagination(decoded) ? decoded : null,
                    _extractMetaMap(decoded),
                  ]),
            );
          }
        }
      }

      for (final entry in decoded.entries) {
        final value = entry.value;
        if (value is List) {
          return _Payload(
            items: value,
            pagination: _firstPagination([
              _looksLikePagination(decoded) ? decoded : null,
              _extractMetaMap(decoded),
            ]),
          );
        }
        if (value is Map<String, dynamic>) {
          final nested = _extractPayload(value);
          if (nested.items.isNotEmpty || nested.pagination != null) {
            return _Payload(
              items: nested.items,
              pagination: nested.pagination ??
                  _firstPagination([
                    _looksLikePagination(value) ? value : null,
                    _looksLikePagination(decoded) ? decoded : null,
                    _extractMetaMap(decoded),
                  ]),
            );
          }
        }
      }

      return _Payload(
        items: const [],
        pagination: _firstPagination([
          _looksLikePagination(decoded) ? decoded : null,
          _extractMetaMap(decoded),
        ]),
      );
    }

    return const _Payload(items: []);
  }

  Map<String, dynamic>? _extractMetaMap(Map<String, dynamic> decoded) {
    final meta = decoded['meta'];
    if (meta is Map<String, dynamic>) {
      return meta;
    }
    return null;
  }

  Map<String, dynamic>? _findPaginationMap(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_looksLikePagination(decoded)) {
        return decoded;
      }

      final meta = decoded['meta'];
      if (meta is Map<String, dynamic> && _looksLikePagination(meta)) {
        return meta;
      }

      for (final value in decoded.values) {
        final candidate = _findPaginationMap(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }
    return null;
  }

  bool _looksLikePagination(Map<String, dynamic> map) {
    return map.containsKey('current_page') ||
        map.containsKey('last_page') ||
        map.containsKey('next_page') ||
        map.containsKey('next_page_url');
  }

  Map<String, dynamic>? _firstPagination(List<Map<String, dynamic>?> candidates) {
    for (final candidate in candidates) {
      if (candidate != null) {
        return candidate;
      }
    }
    return null;
  }

  int? _resolveFromLinks(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final links = decoded['links'];
      if (links is Map<String, dynamic>) {
        final nextUrl = links['next'];
        if (nextUrl is String) {
          return _parsePageFromUrl(nextUrl);
        }
      }
      for (final value in decoded.values) {
        final nested = _resolveFromLinks(value);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  int? _resolveFromMeta(Map<String, dynamic> meta) {
    final current = meta['current_page'];
    final last = meta['last_page'];
    final next = meta['next_page'];

    if (next is int) {
      return next;
    }

    if (current is int && last is int) {
      if (current < last) {
        return current + 1;
      }
      return null;
    }

    if (next is String) {
      return int.tryParse(next);
    }

    final nextUrl = meta['next_page_url'];
    if (nextUrl is String) {
      return _parsePageFromUrl(nextUrl);
    }

    return null;
  }

  int? _parsePageFromUrl(String url) {
    try {
      final uri = Uri.parse(url);
      final page = uri.queryParameters['page'];
      if (page != null) {
        return int.tryParse(page);
      }
    } catch (_) {
      // Ignore parsing errors and treat as no next page.
    }
    return null;
  }
}

class _Payload {
  const _Payload({required this.items, this.pagination});

  final List<dynamic> items;
  final Map<String, dynamic>? pagination;
}
