import 'dart:convert';

import 'package:http/http.dart' as http;

class VendorsService {
  VendorsService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _vendorsUrl = 'https://crm.kokonuts.my/purchase/api/v1/vendors';

  Future<List<String>> fetchVendorNames({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(Uri.parse(_vendorsUrl), headers: headers);
    } catch (error) {
      throw VendorsServiceException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw VendorsServiceException(
        'Vendor request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw VendorsServiceException('Unable to parse vendor response: $error');
    }

    final results = <String>{};
    _collectVendorNames(decoded, results);
    final sorted = results.where((name) => name.trim().isNotEmpty).toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return sorted;
  }

  void _collectVendorNames(dynamic source, Set<String> results) {
    if (source is Map<String, dynamic>) {
      final candidateKeys = [
        'name',
        'vendor_name',
        'vendorName',
        'company',
        'company_name',
        'companyName',
      ];
      for (final key in candidateKeys) {
        final value = source[key];
        if (value is String && value.trim().isNotEmpty) {
          results.add(value.trim());
          break;
        }
      }
      for (final value in source.values) {
        _collectVendorNames(value, results);
      }
    } else if (source is List) {
      for (final item in source) {
        _collectVendorNames(item, results);
      }
    }
  }
}

class VendorsServiceException implements Exception {
  VendorsServiceException(this.message);

  final String message;

  @override
  String toString() => 'VendorsServiceException: $message';
}
