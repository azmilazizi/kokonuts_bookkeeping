import 'dart:convert';

import 'package:http/http.dart' as http;

class Account {
  Account({
    required this.id,
    required this.name,
    required this.parentAccount,
    required this.type,
    required this.detailType,
    required this.primaryBalance,
    required this.isActive,
  });

  final int id;
  final String name;
  final String parentAccount;
  final String type;
  final String detailType;
  final double? primaryBalance;
  final bool isActive;

  factory Account.fromJson(Map<String, dynamic> json) {
    return Account(
      id: _parseInt(json['id']) ?? 0,
      name: _firstNonEmpty([
            json['name'],
            json['account_name'],
            json['display_name'],
            json['title'],
          ])?.toString() ??
          '',
      parentAccount: _firstNonEmpty([
            json['parent_account_name'],
            json['parent_account'],
            json['parent_name'],
            json['parent'],
          ])?.toString() ??
          '',
      type: _firstNonEmpty([
            json['account_type_name'],
            json['type'],
            json['account_type'],
          ])?.toString() ??
          '',
      detailType: _firstNonEmpty([
            json['detail_type_name'],
            json['detail_type'],
            json['account_detail_type'],
          ])?.toString() ??
          '',
      primaryBalance: _parseDouble(_firstNonEmpty([
        json['balance'],
        json['primary_balance'],
        json['current_balance'],
      ])),
      isActive: _parseBool(_firstNonEmpty([
        json['active'],
        json['is_active'],
        json['status'],
      ])),
    );
  }

  String get formattedBalance {
    final value = primaryBalance;
    if (value == null) {
      return '—';
    }
    return value.toStringAsFixed(2);
  }

  static dynamic _firstNonEmpty(Iterable<dynamic> values) {
    for (final value in values) {
      if (value == null) {
        continue;
      }
      if (value is String) {
        final trimmed = value.trim();
        if (trimmed.isNotEmpty) {
          return trimmed;
        }
        continue;
      }
      if (value is num) {
        return value;
      }
      if (value is bool) {
        return value;
      }
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

  static bool _parseBool(dynamic value) {
    if (value is bool) {
      return value;
    }
    if (value is num) {
      return value != 0;
    }
    if (value is String) {
      final normalized = value.trim().toLowerCase();
      if (normalized.isEmpty) {
        return false;
      }
      return normalized == '1' || normalized == 'true' || normalized == 'active';
    }
    return false;
  }
}

class AccountPage {
  AccountPage({
    required this.accounts,
    required this.nextPage,
  });

  final List<Account> accounts;
  final int? nextPage;

  bool get hasMore => nextPage != null;
}

class AccountsException implements Exception {
  AccountsException(this.message);

  final String message;

  @override
  String toString() => 'AccountsException: $message';
}

class AccountsService {
  AccountsService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://crm.kokonuts.my/accounting/api/v1/accounts';

  final http.Client _client;

  Future<AccountPage> fetchAccounts({
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
      throw AccountsException('Unable to reach the server. Please try again later.');
    }

    if (response.statusCode != 200) {
      throw AccountsException('Failed to load accounts (status code ${response.statusCode}).');
    }

    final decoded = jsonDecode(response.body);
    final payload = _extractPayload(decoded);
    final parsedAccounts = payload.items
        .whereType<Map<String, dynamic>>()
        .map(Account.fromJson)
        .toList(growable: false);

    final activeAccounts = parsedAccounts.where((account) => account.isActive).toList();
    activeAccounts.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final nextPage = _parseNextPage(
      decoded,
      paginationSource: payload.pagination,
      currentPage: page,
      perPage: perPage,
      itemCount: payload.items.length,
    );

    return AccountPage(
      accounts: activeAccounts,
      nextPage: nextPage,
    );
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

  int? _resolveFromLinks(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final links = decoded['links'];
      if (links is Map<String, dynamic>) {
        final next = links['next'];
        if (next is int) {
          return next;
        }
        if (next is String) {
          return _parsePageFromUrl(next);
        }
      }
      for (final value in decoded.values) {
        final candidate = _resolveFromLinks(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }
    return null;
  }

  int? _resolveFromMeta(Map<String, dynamic> meta) {
    final next = meta['next_page'];
    if (next is int) {
      return next;
    }
    if (next is String) {
      final parsed = int.tryParse(next);
      if (parsed != null) {
        return parsed;
      }
    }

    final current = meta['current_page'];
    final last = meta['last_page'];
    if (current is int && last is int) {
      if (current < last) {
        return current + 1;
      }
      return null;
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
      return null;
    }
    return null;
  }

  bool _looksLikePagination(Map<String, dynamic> map) {
    const keys = {'current_page', 'last_page', 'per_page', 'total', 'next_page'};
    return map.keys.any(keys.contains);
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

  Map<String, dynamic>? _firstPagination(Iterable<Map<String, dynamic>?> candidates) {
    for (final candidate in candidates) {
      if (candidate == null) {
        continue;
      }
      if (_looksLikePagination(candidate)) {
        return candidate;
      }
    }
    return null;
  }
}

class _Payload {
  const _Payload({required this.items, this.pagination});

  final List<dynamic> items;
  final Map<String, dynamic>? pagination;
}
