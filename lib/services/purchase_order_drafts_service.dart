import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;

import 'auth_http_client.dart';

/// Exception thrown when purchase order draft operations fail.
class PurchaseOrderDraftsException implements Exception {
  PurchaseOrderDraftsException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOrderDraftsException: $message';
}

/// Represents a purchase order draft with associated items, payments, and attachments.
class PurchaseOrderDraft {
  PurchaseOrderDraft({
    required this.id,
    required this.orderName,
    required this.orderNumber,
    required this.orderDate,
    required this.isPaid,
    required this.discountType,
    required this.discountValue,
    required this.shippingFee,
    required this.itemsSubtotal,
    required this.totalDiscount,
    required this.grandTotal,
    required this.createdAt,
    required this.updatedAt,
    this.vendorId,
    this.vendorName,
    this.vendorCode,
    this.pendingDeletionAttachments = const [],
    this.items = const [],
    this.payments = const [],
    this.attachments = const [],
  });

  final String id;
  final String orderName;
  final String orderNumber;
  final DateTime orderDate;
  final bool isPaid;
  final String? vendorId;
  final String? vendorName;
  final String? vendorCode;
  final String? discountType;
  final double discountValue;
  final double shippingFee;
  final double itemsSubtotal;
  final double totalDiscount;
  final double grandTotal;
  final List<dynamic> pendingDeletionAttachments;
  final DateTime createdAt;
  final DateTime updatedAt;
  final List<PurchaseOrderDraftItem> items;
  final List<PurchaseOrderDraftPayment> payments;
  final List<PurchaseOrderDraftAttachment> attachments;

  factory PurchaseOrderDraft.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderDraft(
      id: json['id']?.toString() ?? '',
      vendorId: json['vendor_id']?.toString(),
      vendorName: json['vendor_name']?.toString(),
      vendorCode: json['vendor_code']?.toString(),
      orderName: json['order_name']?.toString() ?? '',
      orderNumber: json['order_number']?.toString() ?? '',
      orderDate: _parseDate(json['order_date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      isPaid: _parseBool(json['is_paid']) ?? false,
      discountType: json['discount_type']?.toString(),
      discountValue: _parseDouble(json['discount_value']) ?? 0,
      shippingFee: _parseDouble(json['shipping_fee']) ?? 0,
      itemsSubtotal: _parseDouble(json['items_subtotal']) ?? 0,
      totalDiscount: _parseDouble(json['total_discount']) ?? 0,
      grandTotal: _parseDouble(json['grand_total']) ?? 0,
      pendingDeletionAttachments: _parseJsonList(json['pending_deletion_attachments']),
      createdAt: _parseDateTime(json['created_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      updatedAt: _parseDateTime(json['updated_at']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      items: _parseDraftItems(json['items']),
      payments: _parseDraftPayments(json['payments']),
      attachments: _parseDraftAttachments(json['attachments']),
    );
  }

  static List<PurchaseOrderDraftItem> _parseDraftItems(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map(PurchaseOrderDraftItem.fromJson)
          .toList(growable: false);
    }
    return const [];
  }

  static List<PurchaseOrderDraftPayment> _parseDraftPayments(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map(PurchaseOrderDraftPayment.fromJson)
          .toList(growable: false);
    }
    return const [];
  }

  static List<PurchaseOrderDraftAttachment> _parseDraftAttachments(dynamic value) {
    if (value is List) {
      return value
          .whereType<Map<String, dynamic>>()
          .map(PurchaseOrderDraftAttachment.fromJson)
          .toList(growable: false);
    }
    return const [];
  }
}

class PurchaseOrderDraftItem {
  PurchaseOrderDraftItem({
    required this.id,
    required this.draftId,
    required this.quantity,
    required this.subtotal,
    required this.discount,
    required this.total,
    this.lineItemId,
    this.inventoryItemId,
    this.inventoryItemName,
    this.description,
  });

  final String id;
  final String draftId;
  final String? lineItemId;
  final String? inventoryItemId;
  final String? inventoryItemName;
  final String? description;
  final double quantity;
  final double subtotal;
  final double discount;
  final double total;

  factory PurchaseOrderDraftItem.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderDraftItem(
      id: json['id']?.toString() ?? '',
      draftId: json['draft_id']?.toString() ?? '',
      lineItemId: json['line_item_id']?.toString(),
      inventoryItemId: json['inventory_item_id']?.toString(),
      inventoryItemName: json['inventory_item_name']?.toString(),
      description: json['description']?.toString(),
      quantity: _parseDouble(json['quantity']) ?? 0,
      subtotal: _parseDouble(json['subtotal']) ?? 0,
      discount: _parseDouble(json['discount']) ?? 0,
      total: _parseDouble(json['total']) ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'draft_id': draftId,
      if (lineItemId != null) 'line_item_id': lineItemId,
      if (inventoryItemId != null) 'inventory_item_id': inventoryItemId,
      if (inventoryItemName != null) 'inventory_item_name': inventoryItemName,
      if (description != null) 'description': description,
      'quantity': quantity,
      'subtotal': subtotal,
      'discount': discount,
    };
  }
}

class PurchaseOrderDraftPayment {
  PurchaseOrderDraftPayment({
    required this.id,
    required this.draftId,
    required this.amount,
    required this.paymentDate,
    this.paymentId,
    this.paymentModeId,
    this.initialPaymentModeLabel,
  });

  final String id;
  final String draftId;
  final String? paymentId;
  final double amount;
  final DateTime paymentDate;
  final String? paymentModeId;
  final String? initialPaymentModeLabel;

  factory PurchaseOrderDraftPayment.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderDraftPayment(
      id: json['id']?.toString() ?? '',
      draftId: json['draft_id']?.toString() ?? '',
      paymentId: json['payment_id']?.toString(),
      amount: _parseDouble(json['amount']) ?? 0,
      paymentDate: _parseDate(json['payment_date']) ?? DateTime.fromMillisecondsSinceEpoch(0),
      paymentModeId: json['payment_mode_id']?.toString(),
      initialPaymentModeLabel: json['initial_payment_mode_label']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'draft_id': draftId,
      if (paymentId != null) 'payment_id': paymentId,
      'amount': amount,
      'payment_date': _formatDate(paymentDate),
      if (paymentModeId != null) 'payment_mode_id': paymentModeId,
      if (initialPaymentModeLabel != null)
        'initial_payment_mode_label': initialPaymentModeLabel,
    };
  }
}

class PurchaseOrderDraftAttachment {
  PurchaseOrderDraftAttachment({
    required this.id,
    required this.draftId,
    required this.fileName,
    this.sizeBytes,
    this.uploadedBy,
    this.isExisting = false,
    this.markedForDeletion = false,
  });

  final String id;
  final String draftId;
  final String fileName;
  final int? sizeBytes;
  final String? uploadedBy;
  final bool isExisting;
  final bool markedForDeletion;

  factory PurchaseOrderDraftAttachment.fromJson(Map<String, dynamic> json) {
    return PurchaseOrderDraftAttachment(
      id: json['id']?.toString() ?? '',
      draftId: json['draft_id']?.toString() ?? '',
      fileName: json['file_name']?.toString() ?? '',
      sizeBytes: _parseInt(json['size_bytes']),
      uploadedBy: json['uploaded_by']?.toString(),
      isExisting: _parseBool(json['is_existing']) ?? false,
      markedForDeletion: _parseBool(json['marked_for_deletion']) ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'draft_id': draftId,
      'file_name': fileName,
      if (sizeBytes != null) 'size_bytes': sizeBytes,
      if (uploadedBy != null) 'uploaded_by': uploadedBy,
      'is_existing': isExisting,
      'marked_for_deletion': markedForDeletion,
    };
  }
}

class PurchaseOrderDraftsPage {
  PurchaseOrderDraftsPage({required this.drafts, this.nextPage});

  final List<PurchaseOrderDraft> drafts;
  final int? nextPage;

  bool get hasMore => nextPage != null;
}

class CreatePurchaseOrderDraftRequest {
  const CreatePurchaseOrderDraftRequest({
    required this.orderName,
    required this.orderNumber,
    required this.orderDate,
    required this.isPaid,
    required this.discountValue,
    required this.shippingFee,
    required this.itemsSubtotal,
    required this.totalDiscount,
    required this.grandTotal,
    this.vendorId,
    this.vendorName,
    this.vendorCode,
    this.discountType,
    this.items = const [],
    this.payments = const [],
  });

  final String? vendorId;
  final String? vendorName;
  final String? vendorCode;
  final String orderName;
  final String orderNumber;
  final DateTime orderDate;
  final bool isPaid;
  final String? discountType;
  final double discountValue;
  final double shippingFee;
  final double itemsSubtotal;
  final double totalDiscount;
  final double grandTotal;
  final List<PurchaseOrderDraftItem> items;
  final List<PurchaseOrderDraftPayment> payments;

  Map<String, dynamic> toJson() {
    return {
      if (vendorId != null) 'vendor_id': vendorId,
      if (vendorName != null) 'vendor_name': vendorName,
      if (vendorCode != null) 'vendor_code': vendorCode,
      'order_name': orderName,
      'order_number': orderNumber,
      'order_date': _formatDate(orderDate),
      'is_paid': isPaid,
      if (discountType != null) 'discount_type': discountType,
      'discount_value': discountValue,
      'shipping_fee': shippingFee,
      'items_subtotal': itemsSubtotal,
      'total_discount': totalDiscount,
      'grand_total': grandTotal,
      if (items.isNotEmpty) 'items': items.map((item) => item.toJson()).toList(),
      if (payments.isNotEmpty)
        'payments': payments.map((payment) => payment.toJson()).toList(),
    };
  }
}

/// Provides CRUD access to purchase order drafts.
class PurchaseOrderDraftsService {
  PurchaseOrderDraftsService({http.Client? client})
      : _client = client ?? createAuthAwareClient();

  final http.Client _client;

  static const _attachmentFieldName = 'file';

  static const _baseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_order_drafts';
  static const _attachmentsBaseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_order_drafts';

  Future<PurchaseOrderDraftsPage> fetchDrafts({
    required Map<String, String> headers,
    int page = 1,
    int perPage = 20,
  }) async {
    final uri = Uri.parse(_baseUrl).replace(queryParameters: {
      'page': '$page',
      'per_page': '$perPage',
    });

    http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        ...headers,
      });
    } catch (_) {
      throw PurchaseOrderDraftsException(
        'Unable to reach the server. Please check your connection and try again.',
      );
    }

    if (response.statusCode != 200) {
      throw PurchaseOrderDraftsException(
        'We could not load purchase order drafts right now. Please try again shortly.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw PurchaseOrderDraftsException(
        'We could not read the server response. Please try again.',
      );
    }

    final items = _extractList(decoded)
        .whereType<Map<String, dynamic>>()
        .map(PurchaseOrderDraft.fromJson)
        .toList(growable: false);

    final nextPage = _resolveNextPage(
      decoded,
      currentPage: page,
      perPage: perPage,
      itemCount: items.length,
    );

    return PurchaseOrderDraftsPage(drafts: items, nextPage: nextPage);
  }

  Future<PurchaseOrderDraft> fetchDraft({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id');

    http.Response response;
    try {
      response = await _client.get(uri, headers: {
        'Accept': 'application/json',
        ...headers,
      });
    } catch (_) {
      throw PurchaseOrderDraftsException(
        'Unable to reach the server. Please check your connection and try again.',
      );
    }

    if (response.statusCode != 200) {
      throw PurchaseOrderDraftsException(
        'We could not load the purchase order draft. Please try again.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw PurchaseOrderDraftsException(
        'We could not read the server response. Please try again.',
      );
    }

    final draftMap = _extractDraft(decoded);
    if (draftMap == null) {
      throw PurchaseOrderDraftsException(
        'The server response did not include purchase order draft details.',
      );
    }

    return PurchaseOrderDraft.fromJson(draftMap);
  }

  Future<PurchaseOrderDraft> createDraft({
    required Map<String, String> headers,
    required CreatePurchaseOrderDraftRequest request,
  }) async {
    final decoded = await _sendJsonDraft(
      uri: Uri.parse(_baseUrl),
      headers: headers,
      request: request,
      method: 'POST',
    );

    final draftMap = _extractDraft(decoded);
    if (draftMap == null) {
      throw PurchaseOrderDraftsException(
        'The server response was missing draft details. Please try again.',
      );
    }

    return PurchaseOrderDraft.fromJson(draftMap);
  }

  Future<PurchaseOrderDraft> updateDraft({
    required String id,
    required Map<String, String> headers,
    required CreatePurchaseOrderDraftRequest request,
  }) async {
    final decoded = await _sendJsonDraft(
      uri: Uri.parse('$_baseUrl/$id'),
      headers: headers,
      request: request,
      method: 'PUT',
    );

    final draftMap = _extractDraft(decoded);
    if (draftMap == null) {
      throw PurchaseOrderDraftsException(
        'The server response was missing draft details. Please try again.',
      );
    }

    return PurchaseOrderDraft.fromJson(draftMap);
  }

  Future<void> deleteDraft({
    required String id,
    required Map<String, String> headers,
  }) async {
    await deleteAttachments(
      id: id,
      headers: headers,
      deleteAll: true,
    );

    http.Response response;
    try {
      response = await _client.delete(
        Uri.parse('$_baseUrl/$id'),
        headers: {
          'Accept': 'application/json',
          ...headers,
        },
      );
    } catch (_) {
      throw PurchaseOrderDraftsException(
        'We could not reach the server to delete the draft. Please try again.',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw PurchaseOrderDraftsException(
        'The draft could not be deleted right now. Please try again later.',
      );
    }
  }

  Future<void> uploadAttachments({
    required String id,
    required Map<String, String> headers,
    required List<PlatformFile> attachments,
  }) async {
    if (attachments.isEmpty) {
      return;
    }

    final files = await Future.wait(
      attachments.map(_buildAttachmentUploadFile),
      eagerError: false,
    );

    final uploadFiles =
        files.whereType<http.MultipartFile>().toList(growable: false);
    if (uploadFiles.isEmpty) {
      return;
    }

    final request = http.MultipartRequest(
      'POST',
      Uri.parse('$_attachmentsBaseUrl/$id/attachments'),
    )
      ..headers.addAll({
        'Accept': 'application/json',
        ...headers,
      })
      ..files.addAll(uploadFiles);

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (_) {
      throw PurchaseOrderDraftsException(
        'We couldn\'t upload the attachments. Please try again.',
      );
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 &&
        resolved.statusCode != 201 &&
        resolved.statusCode != 204) {
      throw PurchaseOrderDraftsException(
        'The attachments couldn\'t be uploaded right now. Please try again later.',
      );
    }
  }

  Future<void> deleteAttachments({
    required String id,
    required Map<String, String> headers,
    List<String> attachmentIds = const [],
    bool deleteAll = false,
  }) async {
    if (!deleteAll && attachmentIds.isEmpty) {
      return;
    }

    final request = http.Request(
      'DELETE',
      Uri.parse('$_attachmentsBaseUrl/$id/attachments'),
    )..headers.addAll({
        'Accept': 'application/json',
        ...headers,
      });

    if (!deleteAll) {
      request.headers['Content-Type'] = 'application/json';
      request.body = jsonEncode({'ids': attachmentIds});
    }

    http.StreamedResponse response;
    try {
      response = await _client.send(request);
    } catch (_) {
      throw PurchaseOrderDraftsException(
        'We couldn\'t delete the attachments right now. Please try again.',
      );
    }

    final resolved = await http.Response.fromStream(response);
    if (resolved.statusCode != 200 && resolved.statusCode != 204) {
      throw PurchaseOrderDraftsException(
        'The attachments couldn\'t be deleted right now. Please try again later.',
      );
    }
  }

  Future<Map<String, dynamic>> _sendJsonDraft({
    required Uri uri,
    required Map<String, String> headers,
    required CreatePurchaseOrderDraftRequest request,
    required String method,
  }) async {
    http.Response response;
    try {
      if (method.toUpperCase() == 'POST') {
        response = await _client.post(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            ...headers,
          },
          body: jsonEncode(request.toJson()),
        );
      } else {
        response = await _client.put(
          uri,
          headers: {
            'Accept': 'application/json',
            'Content-Type': 'application/json',
            ...headers,
          },
          body: jsonEncode(request.toJson()),
        );
      }
    } catch (_) {
      final actionVerb = method.toUpperCase() == 'POST' ? 'create' : 'update';
      throw PurchaseOrderDraftsException(
        'We could not $actionVerb the draft right now. Please try again.',
      );
    }

    if (response.statusCode != 200 && response.statusCode != 201) {
      final actionVerb = method.toUpperCase() == 'POST' ? 'created' : 'updated';
      throw PurchaseOrderDraftsException(
        'The draft could not be $actionVerb right now. Please try again later.',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (_) {
      throw PurchaseOrderDraftsException(
        'We could not read the server response. Please try again.',
      );
    }

    if (decoded is Map<String, dynamic>) {
      return decoded;
    }

    throw PurchaseOrderDraftsException(
      'The server response did not include purchase order draft details.',
    );
  }


  Future<http.MultipartFile?> _buildAttachmentUploadFile(
      PlatformFile file) async {
    final sanitizedName = file.name.trim();
    if (sanitizedName.isEmpty) {
      return null;
    }

    if (file.readStream != null) {
      return http.MultipartFile(
        _attachmentFieldName,
        file.readStream!,
        file.size,
        filename: sanitizedName,
      );
    }

    if (file.bytes != null) {
      return http.MultipartFile.fromBytes(
        _attachmentFieldName,
        file.bytes!,
        filename: sanitizedName,
      );
    }

    final path = file.path?.trim();
    if (path != null && path.isNotEmpty) {
      return http.MultipartFile.fromPath(
        _attachmentFieldName,
        path,
        filename: sanitizedName,
      );
    }

    return null;
  }

  Map<String, dynamic>? _extractDraft(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_looksLikeDraft(decoded)) {
        return decoded;
      }

      for (final key in ['data', 'draft', 'purchase_order_draft']) {
        final value = decoded[key];
        if (value is Map<String, dynamic>) {
          final nested = _extractDraft(value);
          if (nested != null) {
            return nested;
          }
        }
      }

      for (final value in decoded.values) {
        final nested = _extractDraft(value);
        if (nested != null) {
          return nested;
        }
      }
    }

    if (decoded is List) {
      for (final value in decoded) {
        final nested = _extractDraft(value);
        if (nested != null) {
          return nested;
        }
      }
    }

    return null;
  }

  List<dynamic> _extractList(dynamic decoded) {
    if (decoded is List) {
      return decoded;
    }

    if (decoded is Map<String, dynamic>) {
      for (final key in ['data', 'items', 'results']) {
        final value = decoded[key];
        if (value is List) {
          return value;
        }
      }

      for (final value in decoded.values) {
        final nested = _extractList(value);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }

    return const [];
  }

  bool _looksLikeDraft(Map<String, dynamic> map) {
    return map.containsKey('order_name') && map.containsKey('order_number');
  }

  int? _resolveNextPage(
    dynamic decoded, {
    required int currentPage,
    required int perPage,
    required int itemCount,
  }) {
    final meta = _findPagination(decoded);
    if (meta != null) {
      final next = meta['next_page'] ?? meta['next'];
      if (next is int) {
        return next;
      }
      final current = meta['current_page'];
      final last = meta['last_page'];
      if (current is int && last is int && current < last) {
        return current + 1;
      }
    }

    if (itemCount >= perPage) {
      return currentPage + 1;
    }
    return null;
  }

  Map<String, dynamic>? _findPagination(dynamic decoded) {
    if (decoded is Map<String, dynamic>) {
      if (_looksLikePagination(decoded)) {
        return decoded;
      }

      final meta = decoded['meta'];
      if (meta is Map<String, dynamic> && _looksLikePagination(meta)) {
        return meta;
      }

      for (final value in decoded.values) {
        final nested = _findPagination(value);
        if (nested != null) {
          return nested;
        }
      }
    }
    return null;
  }

  bool _looksLikePagination(Map<String, dynamic> map) {
    return map.containsKey('current_page') ||
        map.containsKey('last_page') ||
        map.containsKey('next_page');
  }
}

double? _parseDouble(dynamic value) {
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

int? _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is double) {
    return value.round();
  }
  if (value is String) {
    return int.tryParse(value);
  }
  return null;
}

bool? _parseBool(dynamic value) {
  if (value is bool) {
    return value;
  }
  if (value is int) {
    return value != 0;
  }
  if (value is String) {
    final lower = value.toLowerCase();
    if (lower == 'true' || lower == '1') {
      return true;
    }
    if (lower == 'false' || lower == '0') {
      return false;
    }
  }
  return null;
}

DateTime? _parseDate(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      // Ignore parsing errors and fall through to null.
    }
  }
  return null;
}

DateTime? _parseDateTime(dynamic value) {
  if (value is DateTime) {
    return value;
  }
  if (value is String && value.trim().isNotEmpty) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      // Ignore parsing errors and fall through to null.
    }
  }
  return null;
}

String _formatDate(DateTime date) {
  final twoDigits = (int value) => value.toString().padLeft(2, '0');
  final year = date.year.toString().padLeft(4, '0');
  final month = twoDigits(date.month);
  final day = twoDigits(date.day);
  return '$year-$month-$day';
}

List<dynamic> _parseJsonList(dynamic value) {
  if (value is List) {
    return value;
  }

  if (value is String) {
    try {
      final decoded = jsonDecode(value);
      if (decoded is List) {
        return decoded;
      }
    } catch (_) {
      return const [];
    }
  }

  return const [];
}
