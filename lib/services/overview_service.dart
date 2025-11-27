import 'dart:convert';
import 'package:http/http.dart' as http;

class OverviewService {
  OverviewService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  static const _baseUrl = 'https://crm.kokonuts.my/accounting/api/v1/money_out_summary';

  Future<MoneyOutSummary> fetchMoneyOutSummary({
    required String startDate,
    required String endDate,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'start_date': startDate,
      'end_date': endDate,
    });

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw OverviewException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw OverviewException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw OverviewException('Unable to parse response: $error');
    }

    // Attempt to extract the data payload if wrapped
    dynamic data = decoded;
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('data')) {
        data = decoded['data'];
      } else if (decoded.containsKey('summary')) {
        data = decoded['summary'];
      }
    }

    return MoneyOutSummary.fromJson(data);
  }
}

class TransactionCategorySummary {
  final int count;
  final String total;

  const TransactionCategorySummary({
    required this.count,
    required this.total,
  });

  factory TransactionCategorySummary.empty() {
    return const TransactionCategorySummary(count: 0, total: '0.00');
  }
}

class MoneyOutSummary {
  final Map<String, dynamic> rawData;

  const MoneyOutSummary(this.rawData);

  factory MoneyOutSummary.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return MoneyOutSummary(json);
    }
    return const MoneyOutSummary({});
  }

  String get totalSpent {
    double? val;
    if (rawData.containsKey('grand_total')) {
      val = _parseDouble(rawData['grand_total']);
    } else if (rawData.containsKey('total_spent')) {
      val = _parseDouble(rawData['total_spent']);
    } else if (rawData.containsKey('total')) {
      val = _parseDouble(rawData['total']);
    }

    return val != null ? val.toStringAsFixed(2) : '0.00';
  }

  TransactionCategorySummary get purchaseOrders => _parseCategory(['purchase_orders', 'purchase_order']);
  TransactionCategorySummary get expenses => _parseCategory(['expenses', 'expense']);
  TransactionCategorySummary get bills => _parseCategory(['bills', 'bill']);

  TransactionCategorySummary _parseCategory(List<String> keys) {
    // Check if 'totals' object exists and search inside it first
    Map<String, dynamic>? searchScope;
    if (rawData.containsKey('totals') && rawData['totals'] is Map) {
      searchScope = rawData['totals'] as Map<String, dynamic>;
    } else {
      searchScope = rawData;
    }

    dynamic categoryData;
    for (final key in keys) {
      if (searchScope.containsKey(key)) {
        categoryData = searchScope[key];
        break;
      }
    }

    // If not found in 'totals', fallback to searching in root (backward compatibility)
    if (categoryData == null && searchScope != rawData) {
       for (final key in keys) {
        if (rawData.containsKey(key)) {
          categoryData = rawData[key];
          break;
        }
      }
    }

    if (categoryData is Map<String, dynamic>) {
      final count = _parseInt(categoryData['count']) ?? _parseInt(categoryData['number_of_transaction']) ?? 0;

      double? amount;
      if (categoryData.containsKey('amount')) {
        amount = _parseDouble(categoryData['amount']);
      } else if (categoryData.containsKey('total')) {
        amount = _parseDouble(categoryData['total']);
      } else if (categoryData.containsKey('total_spent')) {
        amount = _parseDouble(categoryData['total_spent']);
      }

      final totalStr = amount != null ? amount.toStringAsFixed(2) : '0.00';

      return TransactionCategorySummary(count: count, total: totalStr);
    }

    return TransactionCategorySummary.empty();
  }

  int? _parseInt(dynamic value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value);
    return null;
  }

  double? _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  /// Returns a list of key-value pairs for display.
  /// This attempts to format keys and values into a readable format.
  List<MapEntry<String, String>> get displayItems {
    final entries = <MapEntry<String, String>>[];
    for (final key in rawData.keys) {
      // format key: replace underscores with spaces, capitalize
      final formattedKey = key.replaceAll('_', ' ').capitalize();
      final value = rawData[key];
      entries.add(MapEntry(formattedKey, value.toString()));
    }
    return entries;
  }
}

extension StringExtension on String {
  String capitalize() {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }
}

class OverviewException implements Exception {
  const OverviewException(this.message);
  final String message;
  @override
  String toString() => 'OverviewException: $message';
}
