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

class MoneyOutSummary {
  final Map<String, dynamic> rawData;

  const MoneyOutSummary(this.rawData);

  factory MoneyOutSummary.fromJson(dynamic json) {
    if (json is Map<String, dynamic>) {
      return MoneyOutSummary(json);
    }
    return const MoneyOutSummary({});
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
