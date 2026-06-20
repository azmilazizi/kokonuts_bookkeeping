import 'dart:convert';

import 'package:http/http.dart' as http;

import 'auth_http_client.dart';

class BillCategory {
  const BillCategory({
    required this.id,
    required this.name,
    this.debitAccount,
    this.creditAccount,
  });

  factory BillCategory.fromJson(Map<String, dynamic> json) {
    return BillCategory(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      debitAccount: _parseInt(json['debit_account']),
      creditAccount: _parseInt(json['credit_account']),
    );
  }

  final String id;
  final String name;
  final int? debitAccount;
  final int? creditAccount;

  static int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class BillCategoryService {
  BillCategoryService({http.Client? client})
      : _client = client ?? createAuthAwareClient();

  final http.Client _client;

  static const _baseUrl =
      'https://crm.kokonuts.my/accounting/api/v1/bill_categories';
  static const _singleUrl =
      'https://crm.kokonuts.my/accounting/api/v1/bill_category';

  Future<List<BillCategory>> fetchCategories({
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.get(Uri.parse(_baseUrl), headers: headers);
    } catch (error) {
      throw BillCategoryException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw BillCategoryException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillCategoryException('Unable to parse response: $error');
    }

    return _extractList(decoded)
        .whereType<Map<String, dynamic>>()
        .map(BillCategory.fromJson)
        .toList();
  }

  Future<BillCategory> createCategory({
    required Map<String, String> headers,
    required String name,
    int? debitAccount,
    int? creditAccount,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      if (debitAccount != null) 'debit_account': debitAccount,
      if (creditAccount != null) 'credit_account': creditAccount,
    };

    http.Response response;
    try {
      response = await _client.post(
        Uri.parse(_baseUrl),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(body),
      );
    } catch (error) {
      throw BillCategoryException('Failed to create category: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw BillCategoryException(
        'Create failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillCategoryException('Unable to parse response: $error');
    }

    final json = _extractSingle(decoded);
    if (json == null) {
      throw BillCategoryException('Response did not include category payload.');
    }

    return BillCategory.fromJson(json);
  }

  Future<BillCategory> updateCategory({
    required String id,
    required Map<String, String> headers,
    String? name,
    int? debitAccount,
    int? creditAccount,
  }) async {
    final body = <String, dynamic>{
      if (name != null) 'name': name,
      if (debitAccount != null) 'debit_account': debitAccount,
      if (creditAccount != null) 'credit_account': creditAccount,
    };

    http.Response response;
    try {
      response = await _client.put(
        Uri.parse('$_singleUrl/$id'),
        headers: {
          'Accept': 'application/json',
          'Content-Type': 'application/json',
          ...headers,
        },
        body: jsonEncode(body),
      );
    } catch (error) {
      throw BillCategoryException('Failed to update category: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw BillCategoryException(
        'Update failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw BillCategoryException('Unable to parse response: $error');
    }

    final json = _extractSingle(decoded);
    if (json == null) {
      throw BillCategoryException('Response did not include category payload.');
    }

    return BillCategory.fromJson(json);
  }

  Future<void> deleteCategory({
    required String id,
    required Map<String, String> headers,
  }) async {
    http.Response response;
    try {
      response = await _client.delete(
        Uri.parse('$_singleUrl/$id'),
        headers: headers,
      );
    } catch (error) {
      throw BillCategoryException('Failed to delete category: $error');
    }

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw BillCategoryException(
        'Delete failed with status ${response.statusCode}: ${response.body}',
      );
    }
  }

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) return decoded;
    if (decoded is Map<String, dynamic>) {
      for (final key in ['data', 'result', 'categories', 'results', 'items']) {
        final value = decoded[key];
        if (value is List) return value;
      }
    }
    return const [];
  }

  Map<String, dynamic>? _extractSingle(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (decoded.containsKey('id')) return decoded;
      for (final key in ['data', 'category', 'result', 'item']) {
        final value = decoded[key];
        if (value is Map<String, dynamic> && value.containsKey('id')) {
          return value;
        }
      }
    }
    return null;
  }
}

class BillCategoryException implements Exception {
  BillCategoryException(this.message);

  final String message;

  @override
  String toString() => 'BillCategoryException: $message';
}
