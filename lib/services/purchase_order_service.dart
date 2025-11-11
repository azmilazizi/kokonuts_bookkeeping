import 'dart:convert';

import 'package:http/http.dart' as http;

/// Represents a single purchase order entry returned from the API.
class PurchaseOrder {
  PurchaseOrder({
    required this.id,
    required this.orderNumber,
    required this.orderName,
    required this.total,
    required this.currencySymbol,
  });

  final int id;
  final String orderNumber;
  final String orderName;
  final double total;
  final String currencySymbol;

  /// Creates an instance of [PurchaseOrder] from a JSON map.
  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      id: _parseInt(json['id']) ?? 0,
      orderNumber: json['pur_order_number']?.toString() ?? '',
      orderName: json['pur_order_name']?.toString() ?? '',
      total: _parseDouble(json['total']) ?? 0,
      currencySymbol: json['currency_symbol']?.toString() ?? '',
    );
  }

  /// Formats the total amount using the provided currency symbol.
  String get formattedTotal {
    final formatted = total.toStringAsFixed(2);
    if (currencySymbol.isEmpty) {
      return formatted;
    }
    return '$currencySymbol $formatted';
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
}

/// A container for paginated purchase orders.
class PurchaseOrderPage {
  PurchaseOrderPage({required this.orders, this.nextPage});

  final List<PurchaseOrder> orders;
  final int? nextPage;

  bool get hasMore => nextPage != null;
}

/// Thrown when the purchase orders request fails.
class PurchaseOrderException implements Exception {
  PurchaseOrderException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOrderException: $message';
}

/// Handles retrieving purchase orders from the backend service with pagination.
class PurchaseOrderService {
  PurchaseOrderService({http.Client? client}) : _client = client ?? http.Client();

  static const _baseUrl = 'https://crm.kokonuts.my/api/v1/purchase/orders';

  final http.Client _client;

  /// Fetches a page of purchase orders from the API.
  Future<PurchaseOrderPage> fetchPurchaseOrders({
    required Map<String, String> headers,
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
      ...headers,
    };

    late http.Response response;
    try {
      response = await _client.get(uri, headers: requestHeaders);
    } catch (_) {
      throw PurchaseOrderException('Unable to reach the server. Please try again later.');
    }

    if (response.statusCode != 200) {
      throw PurchaseOrderException(
        'Failed to load purchase orders (status code ${response.statusCode}).',
      );
    }

    final decoded = jsonDecode(response.body);
    final orders = _parseOrders(decoded);
    final nextPage = _parseNextPage(decoded, currentPage: page, perPage: perPage, itemCount: orders.length);

    return PurchaseOrderPage(orders: orders, nextPage: nextPage);
  }

  List<PurchaseOrder> _parseOrders(dynamic decoded) {
    final items = _extractList(decoded);
    return items
        .whereType<Map<String, dynamic>>()
        .map(PurchaseOrder.fromJson)
        .toList(growable: false);
  }

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }
    if (decoded is Map<String, dynamic>) {
      final candidates = [
        decoded['data'],
        decoded['results'],
        decoded['items'],
      ];
      for (final candidate in candidates) {
        if (candidate is List) {
          return candidate;
        }
      }
    }
    return const [];
  }

  int? _parseNextPage(
    dynamic decoded, {
    required int currentPage,
    required int perPage,
    required int itemCount,
  }) {
    int? nextPage;
    if (decoded is Map<String, dynamic>) {
      final meta = decoded['meta'];
      if (meta is Map<String, dynamic>) {
        nextPage ??= _resolveFromMeta(meta);
      }
      nextPage ??= _resolveFromMeta(decoded);
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

  int? _resolveFromLinks(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      final links = decoded['links'];
      if (links is Map<String, dynamic>) {
        final nextUrl = links['next'];
        if (nextUrl is String) {
          return _parsePageFromUrl(nextUrl);
        }
      }
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
