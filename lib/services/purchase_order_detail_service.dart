import 'dart:convert';

import 'package:http/http.dart' as http;

/// Fetches a single purchase order and maps it to strongly typed classes.
class PurchaseOrderDetailService {
  PurchaseOrderDetailService({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  static const _baseUrl =
      'https://crm.kokonuts.my/purchase/api/v1/purchase_order';

  /// Retrieves the purchase order that matches the provided [id].
  Future<PurchaseOrderDetail> fetchPurchaseOrder({
    required String id,
    required Map<String, String> headers,
  }) async {
    final uri = Uri.parse('$_baseUrl/$id');

    http.Response response;
    try {
      response = await _client.get(uri, headers: headers);
    } catch (error) {
      throw PurchaseOrderDetailException('Failed to reach server: $error');
    }

    if (response.statusCode != 200) {
      throw PurchaseOrderDetailException(
        'Request failed with status ${response.statusCode}: ${response.body}',
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(response.body);
    } catch (error) {
      throw PurchaseOrderDetailException('Unable to parse response: $error');
    }

    final orderMap = _extractPurchaseOrderDetail(decoded);
    if (orderMap == null) {
      throw const PurchaseOrderDetailException(
        'Purchase order details were not found in the response.',
      );
    }

    return PurchaseOrderDetail.fromJson(orderMap);
  }

  Map<String, dynamic>? _extractPurchaseOrderDetail(dynamic data) {
    if (data is Map<String, dynamic>) {
      if (_looksLikeNormalizedOrder(data)) {
        return data;
      }

      final normalizedFromWrapper = _extractFromOrderWrapper(data);
      if (normalizedFromWrapper != null) {
        return normalizedFromWrapper;
      }

      for (final value in data.values) {
        final candidate = _extractPurchaseOrderDetail(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    if (data is List) {
      for (final value in data) {
        final candidate = _extractPurchaseOrderDetail(value);
        if (candidate != null) {
          return candidate;
        }
      }
    }

    return null;
  }

  Map<String, dynamic>? _extractFromOrderWrapper(Map<String, dynamic> data) {
    const orderKeys = [
      'order',
      'purchase_order',
      'purchaseOrder',
    ];
    for (final key in orderKeys) {
      final orderValue = data[key];
      if (orderValue is Map<String, dynamic>) {
        final normalized = Map<String, dynamic>.from(orderValue);
        final items = data['items'] ??
            data['order_items'] ??
            data['purchase_order_items'];
        if (items != null) {
          normalized['items'] = items;
        }
        return normalized;
      }
    }
    return null;
  }

  bool _looksLikeNormalizedOrder(Map<String, dynamic> data) {
    if (!data.containsKey('id')) {
      return false;
    }
    final hasNumber = data.containsKey('pur_order_number') ||
        data.containsKey('order_number') ||
        data.containsKey('number');
    final items = data['items'];
    final hasItems = items is List || (items is Map<String, dynamic>);
    return hasNumber || hasItems;
  }
}

/// The parsed representation of a purchase order.
class PurchaseOrderDetail {
  PurchaseOrderDetail({
    required this.id,
    required this.number,
    required this.name,
    required this.deliveryStatusLabel,
    required this.vendorName,
    required this.currencySymbol,
    required this.subtotalLabel,
    required this.totalLabel,
    this.discountLabel,
    this.shippingFeeLabel,
    required this.items,
    required this.payments,
    required this.attachments,
    required this.approvalStatus,
    this.orderDate,
    this.deliveryDate,
    this.reference,
    this.notes,
    this.terms,
    this.deliveryStatusId,
    this.approvalStatusId,
  });

  factory PurchaseOrderDetail.fromJson(Map<String, dynamic> json) {
    final currencyResolution = _resolveCurrencySymbol(json);
    final currencySymbol = currencyResolution.symbol;

    final subtotalValue = json['subtotal'] ?? json['sub_total'];
    final subtotalLabel = _resolveAmountLabel(
      formattedValue: _string(json['subtotal_formatted']) ??
          _string(json['sub_total_formatted']),
      rawValue: subtotalValue,
      currencySymbol: currencySymbol,
      removedSymbol: currencyResolution.removedSymbol,
    );

    final totalValue = json['total'];
    final totalLabel = _resolveAmountLabel(
      formattedValue: _string(json['total_formatted']) ??
          _string(json['grand_total_formatted']),
      rawValue: totalValue,
      currencySymbol: currencySymbol,
      removedSymbol: currencyResolution.removedSymbol,
    );

    final resolvedDiscountLabel = _resolveOptionalAmount(
      currencySymbol,
      rawValue: json['discount_total'] ?? json['discount'],
      formattedValue: _string(json['discount_total_formatted']) ??
          _string(json['discount_formatted']),
      removedSymbol: currencyResolution.removedSymbol,
    );

    final resolvedShippingFeeLabel = _resolveOptionalAmount(
      currencySymbol,
      rawValue: json['shipping_fee'] ?? json['shipping_total'],
      formattedValue: _string(json['shipping_fee_formatted']) ??
          _string(json['shipping_total_formatted']),
      removedSymbol: currencyResolution.removedSymbol,
    );

    final vendorName = _string(json['vendor_name']) ??
        _string(json['supplier_name']) ??
        _parseVendorName(json['vendor']) ??
        _parseVendorName(json['supplier']) ??
        '—';

    final deliveryStatusId = _resolveDeliveryStatusId(json);
    final statusFallbackId = _parseInt(json['status_id']) ??
        _parseNestedId(json['status']) ??
        _parseInt(json['status']);
    final resolvedDeliveryStatusId = deliveryStatusId ?? statusFallbackId;
    final deliveryStatusLabel = _string(json['delivery_status_label']) ??
        _string(json['delivery_status_text']) ??
        _parseNestedName(json['delivery_status']) ??
        (resolvedDeliveryStatusId != null
            ? _deliveryStatusLabelFromId(resolvedDeliveryStatusId)
            : null) ??
        _string(json['status_label']) ??
        _string(json['status_text']) ??
        _parseNestedName(json['status']) ??
        '—';

    final approvalStatusId = _parseInt(json['approve_status']) ??
        _parseInt(json['approval_status']) ??
        _parseInt(json['status_approval']) ??
        _parseInt(json['approval_status_id']);
    final approvalStatusLabelFromId = approvalStatusId != null
        ? _approvalStatusLabelFromId(approvalStatusId)
        : null;
    final approvalStatusLabel =
        approvalStatusLabelFromId ??
            _string(json['approval_status_label']) ??
        _string(json['approval_status_text']) ??
        _parseNestedName(json['approval_status']) ??
        _parseNestedName(json['status_approval']) ??
        '—';

    final items = _extractItems(json['items'])
        .whereType<Map<String, dynamic>>()
        .map((item) => PurchaseOrderItem.fromJson(
              item,
              currencySymbol: currencySymbol,
            ))
        .toList(growable: false);

    final payments = _extractRelatedCollection(json, const [
      'payments',
      'payment_history',
      'paymentHistory',
      'payment_list',
      'paymentList',
      'payment_details',
      'paymentDetails',
      'payment_logs',
      'paymentLogs',
      'payment_records',
      'paymentRecords',
      'payment_history_list',
      'paymentHistoryList',
      'payment_history_data',
      'paymentHistoryData',
      'payment',
    ])
        .whereType<Map<String, dynamic>>()
        .map((payment) => PurchaseOrderPayment.fromJson(
              payment,
              currencySymbol: currencySymbol,
            ))
        .toList(growable: false);

    final attachments = _extractRelatedCollection(json, const [
      'attachments',
      'files',
      'documents',
      'attachment',
      'document',
      'order_attachments',
      'purchase_order_attachments',
      'attachment_files',
      'attachmentFiles',
      'attachment_list',
      'attachmentList',
    ])
        .whereType<Map<String, dynamic>>()
        .map(PurchaseOrderAttachment.fromJson)
        .toList(growable: false);

    return PurchaseOrderDetail(
      id: _string(json['id']) ?? '',
      number: _string(json['pur_order_number']) ??
          _string(json['order_number']) ??
          _string(json['number']) ??
          '—',
      name: _string(json['pur_order_name']) ??
          _string(json['name']) ??
          '—',
      deliveryStatusLabel: deliveryStatusLabel,
      vendorName: vendorName,
      currencySymbol: currencySymbol,
      subtotalLabel: subtotalLabel,
      totalLabel: totalLabel,
      discountLabel: resolvedDiscountLabel,
      shippingFeeLabel: resolvedShippingFeeLabel,
      items: List.unmodifiable(items),
      payments: List.unmodifiable(payments),
      attachments: List.unmodifiable(attachments),
      approvalStatus: approvalStatusLabel,
      orderDate: _parseDate(json['order_date']) ??
          _parseDate(json['created_at']),
      deliveryDate: _parseDate(json['delivery_date']) ??
          _parseDate(json['expected_delivery_date']),
      reference: _string(json['reference_no']) ??
          _string(json['reference']) ??
          _string(json['ref_number']),
      notes: _string(json['notes']) ?? _string(json['note']),
      terms: _string(json['terms']) ?? _string(json['term']),
      deliveryStatusId: resolvedDeliveryStatusId,
      approvalStatusId: approvalStatusId,
    );
  }

  final String id;
  final String number;
  final String name;
  final String deliveryStatusLabel;
  final String vendorName;
  final DateTime? orderDate;
  final DateTime? deliveryDate;
  final String? reference;
  final String currencySymbol;
  final String subtotalLabel;
  final String totalLabel;
  final String? discountLabel;
  final String? shippingFeeLabel;
  final String? notes;
  final String? terms;
  final String approvalStatus;
  final int? deliveryStatusId;
  final int? approvalStatusId;
  final List<PurchaseOrderItem> items;
  final List<PurchaseOrderPayment> payments;
  final List<PurchaseOrderAttachment> attachments;

  String get orderDateLabel => _formatDate(orderDate) ?? '—';

  String get deliveryDateLabel => _formatDate(deliveryDate) ?? '—';

  String? get referenceLabel =>
      reference != null && reference!.trim().isNotEmpty ? reference : null;

  bool get hasNotes => notes != null && notes!.trim().isNotEmpty;

  bool get hasTerms => terms != null && terms!.trim().isNotEmpty;

  bool get hasDiscount =>
      discountLabel != null && discountLabel!.trim().isNotEmpty;

  bool get hasShippingFee =>
      shippingFeeLabel != null && shippingFeeLabel!.trim().isNotEmpty;

  bool get hasPayments => payments.isNotEmpty;

  bool get hasAttachments => attachments.isNotEmpty;
}

const Map<int, String> purchaseOrderDeliveryStatusLabels = {
  0: 'Undelivered',
  1: 'Delivered',
};

const Map<int, String> purchaseOrderApprovalStatusLabels = {
  1: 'Draft',
  2: 'Approved',
  3: 'Rejected',
  4: 'Cancelled',
};

/// Represents a single line item within a purchase order.
class PurchaseOrderItem {
  const PurchaseOrderItem({
    required this.name,
    required this.description,
    required this.quantityLabel,
    required this.rateLabel,
    required this.amountLabel,
  });

  factory PurchaseOrderItem.fromJson(
    Map<String, dynamic> json, {
    required String currencySymbol,
  }) {
    final quantity = json['quantity'] ?? json['qty'] ?? json['ordered_quantity'];
    final quantityUnit = _string(json['unit']) ?? _string(json['unit_name']);
    final quantityLabel = _formatQuantity(quantity, unit: quantityUnit);

    final rateValue = json['rate'] ?? json['price'] ?? json['unit_price'];
    final rateLabel = _string(json['rate_formatted']) ??
        _string(json['price_formatted']) ??
        _string(json['unit_price_formatted']) ??
        _formatCurrency(currencySymbol, rateValue);

    final amountValue = json['amount'] ??
        json['total'] ??
        json['line_total'] ??
        json['subtotal'];
    final amountLabel = _string(json['amount_formatted']) ??
        _string(json['total_formatted']) ??
        _string(json['line_total_formatted']) ??
        _formatCurrency(currencySymbol, amountValue);

    final descriptions = <String>{};
    final descriptionKeys = [
      'description',
      'item_description',
      'long_description',
      'detail',
    ];
    for (final key in descriptionKeys) {
      final value = _string(json[key]);
      if (value != null && value.isNotEmpty) {
        descriptions.add(value);
      }
    }

    final description = descriptions.isEmpty
        ? '—'
        : descriptions.join('\n');

    return PurchaseOrderItem(
      name: _string(json['item_name']) ??
          _string(json['name']) ??
          _string(json['item']) ??
          '—',
      description: description,
      quantityLabel: quantityLabel,
      rateLabel: rateLabel,
      amountLabel: amountLabel,
    );
  }

  final String name;
  final String description;
  final String quantityLabel;
  final String rateLabel;
  final String amountLabel;
}

/// Represents a payment recorded against a purchase order.
class PurchaseOrderPayment {
  const PurchaseOrderPayment({
    required this.reference,
    required this.amountLabel,
    this.date,
    this.method,
    this.status,
    this.note,
    this.recordedBy,
  });

  factory PurchaseOrderPayment.fromJson(
    Map<String, dynamic> json, {
    required String currencySymbol,
  }) {
    final reference = _string(json['reference_no']) ??
        _string(json['reference']) ??
        _string(json['payment_number']) ??
        _string(json['payment_no']) ??
        _string(json['number']) ??
        _string(json['code']) ??
        _string(json['payment_reference']) ??
        _string(json['transaction_reference']) ??
        '—';

    final amountValue = json['amount'] ??
        json['payment_amount'] ??
        json['paid_amount'] ??
        json['total'];

    final amountLabel = _string(json['amount_formatted']) ??
        _string(json['payment_amount_formatted']) ??
        _string(json['paid_amount_formatted']) ??
        _string(json['total_formatted']) ??
        _formatCurrency(currencySymbol, amountValue);

    final date = _parseDate(json['payment_date']) ??
        _parseDate(json['date']) ??
        _parseDate(json['paid_at']) ??
        _parseDate(json['created_at']);

    final method = _string(json['payment_method']) ??
        _string(json['method']) ??
        _string(json['payment_mode']) ??
        _string(json['mode']) ??
        _string(json['payment_type']);

    final status = _parseNestedName(json['status']) ??
        _string(json['status_label']) ??
        _string(json['status_text']);

    final note = _string(json['note']) ??
        _string(json['description']) ??
        _string(json['remarks']) ??
        _string(json['memo']);

    final recordedBy = _string(json['received_by']) ??
        _string(json['paid_by']) ??
        _string(json['created_by']) ??
        _string(json['owner']);

    return PurchaseOrderPayment(
      reference: reference,
      amountLabel: amountLabel,
      date: date,
      method: method,
      status: status,
      note: note,
      recordedBy: recordedBy,
    );
  }

  final String reference;
  final String amountLabel;
  final DateTime? date;
  final String? method;
  final String? status;
  final String? note;
  final String? recordedBy;

  String get dateLabel => _formatDate(date) ?? '—';

  String get methodLabel =>
      method?.trim().isNotEmpty == true ? method!.trim() : '—';

  String get statusLabel =>
      status?.trim().isNotEmpty == true ? status!.trim() : '—';

  bool get hasNote => note != null && note!.trim().isNotEmpty;
}

/// Represents a file attachment associated with the purchase order.
class PurchaseOrderAttachment {
  const PurchaseOrderAttachment({
    required this.fileName,
    this.description,
    this.downloadUrl,
    this.uploadedBy,
    this.uploadedAt,
    this.sizeLabel,
  });

  factory PurchaseOrderAttachment.fromJson(Map<String, dynamic> json) {
    final fileName = _string(json['file_name']) ??
        _string(json['filename']) ??
        _string(json['name']) ??
        _string(json['title']) ??
        'Attachment';

    final description = _string(json['description']) ??
        _string(json['note']) ??
        _string(json['remarks']);

    final downloadUrl = _string(json['download_url']) ??
        _string(json['url']) ??
        _string(json['file_url']) ??
        _string(json['link']) ??
        _string(json['file_path']) ??
        _string(json['path']);

    final uploadedBy = _string(json['uploaded_by']) ??
        _string(json['created_by']) ??
        _string(json['owner']) ??
        _string(json['added_by']) ??
        _string(json['uploadedBy']);

    final uploadedAt = _parseDate(json['uploaded_at']) ??
        _parseDate(json['created_at']) ??
        _parseDate(json['date']);

    final sizeLabel = _string(json['file_size_formatted']) ??
        _string(json['size_formatted']) ??
        _string(json['file_size']) ??
        _string(json['size']);

    return PurchaseOrderAttachment(
      fileName: fileName,
      description: description,
      downloadUrl: downloadUrl,
      uploadedBy: uploadedBy,
      uploadedAt: uploadedAt,
      sizeLabel: sizeLabel,
    );
  }

  final String fileName;
  final String? description;
  final String? downloadUrl;
  final String? uploadedBy;
  final DateTime? uploadedAt;
  final String? sizeLabel;

  String get uploadedAtLabel => _formatDate(uploadedAt) ?? '—';

  bool get hasDescription => description != null && description!.trim().isNotEmpty;

  bool get hasDownloadUrl => downloadUrl != null && downloadUrl!.trim().isNotEmpty;
}

class _CurrencyResolution {
  const _CurrencyResolution({required this.symbol, this.removedSymbol});

  final String symbol;
  final String? removedSymbol;
}

/// Thrown when the purchase order details request fails.
class PurchaseOrderDetailException implements Exception {
  const PurchaseOrderDetailException(this.message);

  final String message;

  @override
  String toString() => 'PurchaseOrderDetailException: $message';
}

List<dynamic> _extractRelatedCollection(
  dynamic source,
  List<String> candidateKeys,
) {
  if (source is Map<String, dynamic>) {
    for (final key in candidateKeys) {
      if (source.containsKey(key)) {
        final extracted = _extractItems(source[key]);
        if (extracted.isNotEmpty) {
          return extracted;
        }
      }
    }

    for (final value in source.values) {
      final extracted = _extractRelatedCollection(value, candidateKeys);
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }
  } else if (source is List) {
    for (final element in source) {
      final extracted = _extractRelatedCollection(element, candidateKeys);
      if (extracted.isNotEmpty) {
        return extracted;
      }
    }
  }

  return const [];
}

List<dynamic> _extractItems(dynamic source) {
  if (source is List) {
    return source;
  }
  if (source is Map<String, dynamic>) {
    if (source.containsKey('data')) {
      return _extractItems(source['data']);
    }
    if (source.containsKey('items')) {
      return _extractItems(source['items']);
    }
    return source.values
        .map(_extractItems)
        .expand((element) => element)
        .toList();
  }
  return const [];
}

int? _resolveDeliveryStatusId(Map<String, dynamic> json) {
  final directCandidates = [
    json['delivery_status'],
    json['delivery_status_id'],
    json['delivery_status_code'],
    json['delivery_status_value'],
  ];

  for (final candidate in directCandidates) {
    final parsed = _parseInt(candidate);
    if (parsed != null) {
      return parsed;
    }
  }

  final nested = _parseNestedId(json['delivery_status']);
  if (nested != null) {
    return nested;
  }

  return null;
}

String? _string(dynamic value) {
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

_CurrencyResolution _resolveCurrencySymbol(Map<String, dynamic> json) {
  const candidateKeys = [
    'currency_symbol',
    'currency',
    'currency_name',
  ];

  String symbol = '';
  String? removedSymbol;

  for (final key in candidateKeys) {
    final candidate = _string(json[key]);
    if (candidate == null) {
      continue;
    }

    if (_looksLikeNumericSymbol(candidate)) {
      removedSymbol ??= candidate.trim();
      continue;
    }

    symbol = candidate;
    break;
  }

  return _CurrencyResolution(symbol: symbol, removedSymbol: removedSymbol);
}

bool _looksLikeNumericSymbol(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return true;
  }

  final normalized = trimmed.replaceAll(RegExp(r'[\s\u00a0,]'), '');
  return double.tryParse(normalized) != null;
}

String _cleanAmountLabel(String value, {String? removedSymbol}) {
  final trimmed = value.trim();
  if (removedSymbol != null && removedSymbol.isNotEmpty) {
    final escaped = RegExp.escape(removedSymbol.trim());
    final pattern = RegExp('^$escaped[\u00a0\s]+');
    final sanitized = trimmed.replaceFirst(pattern, '').trimLeft();
    if (sanitized.isNotEmpty) {
      return sanitized;
    }
  }

  return trimmed;
}

String _formatCurrency(String symbol, dynamic value) {
  final parsed = _parseDouble(value);
  if (parsed == null) {
    final fallback = _string(value);
    if (fallback != null) {
      return fallback;
    }
    return symbol.isEmpty ? '0.00' : '$symbol 0.00';
  }

  final formatted = parsed.toStringAsFixed(2);
  if (symbol.isEmpty) {
    return formatted;
  }
  return '$symbol $formatted';
}

String _formatQuantity(dynamic value, {String? unit}) {
  final parsed = _parseDouble(value);
  if (parsed == null) {
    final fallback = _string(value);
    if (fallback == null) {
      return '—';
    }
    return unit != null && unit.isNotEmpty ? '$fallback $unit' : fallback;
  }

  final hasDecimals = parsed % 1 != 0;
  final formatted = hasDecimals
      ? parsed.toStringAsFixed(2)
      : parsed.toStringAsFixed(0);
  return unit != null && unit.isNotEmpty ? '$formatted $unit' : formatted;
}

String? _parseNestedName(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _string(value['name']) ??
        _string(value['label']) ??
        _string(value['title']);
  }
  return _string(value);
}

int? _parseNestedId(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _parseInt(value['id']) ??
        _parseInt(value['code']) ??
        _parseInt(value['value']) ??
        _parseInt(value['status']);
  }
  return _parseInt(value);
}

String? _parseVendorName(dynamic value) {
  if (value is Map<String, dynamic>) {
    return _string(value['vendor_name']) ??
        _string(value['supplier_name']) ??
        _string(value['name']) ??
        _string(value['label']) ??
        _string(value['title']);
  }
  return _string(value);
}

String? _resolveOptionalAmount(
  String currencySymbol, {
  dynamic rawValue,
  String? formattedValue,
  String? removedSymbol,
}) {
  final shouldDisplay = _shouldDisplayAmount(
    rawValue: rawValue,
    formattedValue: formattedValue,
  );
  if (!shouldDisplay) {
    return null;
  }

  if (formattedValue != null) {
    final sanitized = _cleanAmountLabel(
      formattedValue,
      removedSymbol: removedSymbol,
    );
    if (sanitized.trim().isNotEmpty) {
      return sanitized;
    }
  }

  if (rawValue != null) {
    return _formatCurrency(currencySymbol, rawValue);
  }

  return null;
}

String _resolveAmountLabel({
  String? formattedValue,
  dynamic rawValue,
  required String currencySymbol,
  String? removedSymbol,
}) {
  if (formattedValue != null) {
    final sanitized = _cleanAmountLabel(
      formattedValue,
      removedSymbol: removedSymbol,
    );
    if (sanitized.trim().isNotEmpty) {
      return sanitized;
    }
  }

  return _formatCurrency(currencySymbol, rawValue);
}

double? _parseDouble(dynamic value) {
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return double.tryParse(trimmed.replaceAll(',', ''));
  }
  return null;
}

bool _shouldDisplayAmount({dynamic rawValue, String? formattedValue}) {
  if (rawValue != null && !_isZeroValue(rawValue)) {
    return true;
  }

  if (formattedValue != null && !_isZeroValue(formattedValue)) {
    return true;
  }

  return false;
}

bool _isZeroValue(dynamic value) {
  final parsed = _parseDouble(value);
  if (parsed != null) {
    return parsed == 0;
  }

  final stringValue = _string(value);
  if (stringValue == null) {
    return false;
  }

  final digitsOnly = stringValue.replaceAll(RegExp(r'[^0-9\.-]'), '');
  if (digitsOnly.isEmpty) {
    return false;
  }

  final normalized = double.tryParse(digitsOnly);
  if (normalized != null) {
    return normalized == 0;
  }

  return false;
}

DateTime? _parseDate(dynamic value) {
  final stringValue = _string(value);
  if (stringValue == null) {
    return null;
  }

  final normalized = stringValue.replaceAll('/', '-');
  try {
    return DateTime.parse(normalized);
  } catch (_) {
    final datePart = normalized.split(' ').first;
    final segments = datePart.split('-');
    if (segments.length == 3) {
      int? year;
      int? month;
      int? day;

      if (segments[0].length == 4) {
        year = int.tryParse(segments[0]);
        month = int.tryParse(segments[1]);
        day = int.tryParse(segments[2]);
      } else if (segments[2].length == 4) {
        year = int.tryParse(segments[2]);
        month = int.tryParse(segments[1]);
        day = int.tryParse(segments[0]);
      }

      if (year != null && month != null && day != null) {
        return DateTime(year, month, day);
      }
    }
  }

  return null;
}

int? _parseInt(dynamic value) {
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  if (value is String) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      return null;
    }
    return int.tryParse(trimmed);
  }
  return null;
}

String? _deliveryStatusLabelFromId(int id) => purchaseOrderDeliveryStatusLabels[id];

String? _approvalStatusLabelFromId(int id) =>
    purchaseOrderApprovalStatusLabels[id];

String? _formatDate(DateTime? value) {
  if (value == null) {
    return null;
  }
  final day = value.day.toString().padLeft(2, '0');
  final month = value.month.toString().padLeft(2, '0');
  final year = value.year.toString().padLeft(4, '0');
  return '$day-$month-$year';
}
