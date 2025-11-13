import 'dart:convert';

import 'package:http/http.dart' as http;

class ExpensesService {
  ExpensesService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl = 'https://crm.kokonuts.my/expenses/api/v1/expenses';

  Future<ExpensesPage> fetchExpenses({
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
      throw ExpensesException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw ExpensesException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw ExpensesException('Unable to parse response: $error');
    }

    final expensesList = _extractExpensesList(decoded);
    final expenses = expensesList
        .whereType<Map<String, dynamic>>()
        .map(Expense.fromJson)
        .toList();

    final pagination =
        _resolvePagination(decoded, currentPage: page, perPage: perPage);

    return ExpensesPage(expenses: expenses, hasMore: pagination.hasMore);
  }

  List<dynamic> _extractExpensesList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      const preferredKeys = ['data', 'expenses', 'results', 'items'];
      for (final key in preferredKeys) {
        final value = decoded[key];
        final list = _extractExpensesList(value);
        if (list.isNotEmpty) {
          return list;
        }
      }

      for (final value in decoded.values) {
        final list = _extractExpensesList(value);
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

  int _countItems(dynamic source) {
    if (source is List) {
      return source.length;
    }
    if (source is Map<String, dynamic>) {
      return source.values.fold<int>(0, (count, value) => count + _countItems(value));
    }
    return 0;
  }

  int? _readInt(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
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
      final resolved = Expense._stringValue(value);
      if (resolved != null) {
        return resolved;
      }
    }
    return null;
  }
}

class ExpensesPage {
  const ExpensesPage({required this.expenses, required this.hasMore});

  final List<Expense> expenses;
  final bool hasMore;
}

class Expense {
  const Expense({
    required this.id,
    required this.vendor,
    required this.name,
    required this.amount,
    required this.amountLabel,
    required this.currencySymbol,
    required this.date,
    required this.receipt,
    required this.paymentMode,
  });

  factory Expense.fromJson(Map<String, dynamic> json) {
    final vendorData = json['vendor'];
    String? vendorName;
    if (vendorData is Map<String, dynamic>) {
      vendorName = _stringValue(vendorData['name']) ??
          _stringValue(vendorData['vendor_name']) ??
          _stringValue(vendorData['company_name']);
    }

    final amountValue = json['amount'] ?? json['total'] ?? json['value'];
    final amount = _parseDouble(amountValue);
    final amountLabel = _stringValue(amountValue) ?? amount?.toStringAsFixed(2) ?? '—';

    final receipt = _resolveReceipt(json['receipt']) ??
        _resolveReceipt(json['receipt_url']) ??
        _resolveReceipt(json['receipt_link']) ??
        _resolveReceipt(json['attachments']) ??
        _stringValue(json['receipt']) ??
        _stringValue(json['receipt_url']) ??
        _stringValue(json['receipt_link']);

    final dateString = _stringValue(json['expense_date']) ??
        _stringValue(json['date']) ??
        _stringValue(json['created_at']) ??
        _stringValue(json['updated_at']) ??
        '';

    final paymentMode = _stringValue(json['payment_mode']) ??
        _stringValue(json['paymentMode']) ??
        _stringValue(json['mode']) ??
        _stringValue(json['payment_method']) ??
        '—';

    return Expense(
      id: _stringValue(json['id']) ?? '',
      vendor: vendorName ??
          _stringValue(json['vendor_name']) ??
          _stringValue(json['vendor']) ??
          '—',
      name: _stringValue(json['name']) ??
          _stringValue(json['description']) ??
          _stringValue(json['title']) ??
          '—',
      amount: amount,
      amountLabel: amountLabel,
      currencySymbol: _stringValue(json['currency_symbol']) ??
          _stringValue(json['currency']) ??
          _stringValue(json['currency_code']) ??
          '',
      date: _parseDateString(dateString),
      receipt: receipt,
      paymentMode: paymentMode,
    );
  }

  final String id;
  final String vendor;
  final String name;
  final double? amount;
  final String amountLabel;
  final String currencySymbol;
  final DateTime? date;
  final String? receipt;
  final String paymentMode;

  String get formattedDate {
    final value = date;
    if (value == null) {
      return '—';
    }
    final day = value.day.toString().padLeft(2, '0');
    final month = value.month.toString().padLeft(2, '0');
    final year = value.year.toString().padLeft(4, '0');
    return '$day-$month-$year';
  }

  String get formattedAmount {
    if (amount != null) {
      final formatted = amount!.toStringAsFixed(2);
      if (currencySymbol.isNotEmpty) {
        return '$currencySymbol$formatted';
      }
      return formatted;
    }
    if (currencySymbol.isNotEmpty && amountLabel != '—') {
      return '$currencySymbol$amountLabel';
    }
    return amountLabel;
  }

  String get receiptLabel {
    final receiptValue = receipt;
    if (receiptValue == null || receiptValue.isEmpty) {
      return '—';
    }
    return 'Available';
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

class PaginationInfo {
  const PaginationInfo({required this.hasMore});

  final bool hasMore;
}

class ExpensesException implements Exception {
  const ExpensesException(this.message);

  final String message;

  @override
  String toString() => 'ExpensesException: $message';
}

double? _parseDouble(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final sanitized = value.replaceAll(RegExp(r'[^0-9.,-]'), '');
    final normalized = sanitized.replaceAll(',', '');
    return double.tryParse(normalized);
  }
  return null;
}

DateTime? _parseDateString(String? value) {
  if (value == null) {
    return null;
  }
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

List<int> _parseTimeComponents(String? value) {
  if (value == null || value.isEmpty) {
    return const [0, 0, 0];
  }
  final cleaned = value.trim();
  final timePart = cleaned.split(RegExp(r'\s+')).first;
  final segments = timePart.split(':');
  final hours = segments.isNotEmpty ? int.tryParse(segments[0]) ?? 0 : 0;
  final minutes = segments.length > 1 ? int.tryParse(segments[1]) ?? 0 : 0;
  final seconds = segments.length > 2 ? int.tryParse(segments[2]) ?? 0 : 0;
  return [hours, minutes, seconds];
}

String? _resolveReceipt(dynamic value) {
  if (value == null) {
    return null;
  }
  if (value is String) {
    final trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
  if (value is Map<String, dynamic>) {
    return Expense._stringValue(
          value['url'] ?? value['link'] ?? value['file'] ?? value['path'],
        ) ??
        _resolveReceipt(value['data']);
  }
  if (value is List) {
    for (final item in value) {
      final resolved = _resolveReceipt(item);
      if (resolved != null && resolved.isNotEmpty) {
        return resolved;
      }
    }
  }
  return null;
}
