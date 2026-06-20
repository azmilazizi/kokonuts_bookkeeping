import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class ReceiptScanService {
  ReceiptScanService({
    required this.baseUrl,
    required Map<String, String> headers,
    http.Client? client,
  })  : _headers = {...headers, 'Accept': 'application/json'},
        _client = client ?? http.Client();

  final String baseUrl;
  final Map<String, String> _headers;
  final http.Client _client;

  Future<Map<String, dynamic>> scan(
    String imagePath, {
    Uint8List? bytes,
    String? recordType,
  }) async {
    final uri = Uri.parse('$baseUrl/api/v1/ai/receipt/scan');
    final filename = imagePath.split('/').last;
    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_headers)
      ..files.add(
        bytes != null
            ? http.MultipartFile.fromBytes('receipt', bytes, filename: filename)
            : await http.MultipartFile.fromPath('receipt', imagePath, filename: filename),
      );
    if (recordType != null && recordType.isNotEmpty) {
      request.fields['record_type'] = recordType;
    }

    http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request);
    } catch (_) {
      throw Exception('Could not connect to server');
    }

    final response = await http.Response.fromStream(streamed);
    final decoded = _tryDecode(response.body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        decoded?['message'] as String? ?? 'Scan failed (${response.statusCode})',
      );
    }

    if (decoded?['status'] != true) {
      throw Exception(decoded?['message'] as String? ?? 'Scan failed');
    }

    final result = decoded?['result'];
    if (result is! Map<String, dynamic>) {
      throw Exception('Unexpected response format');
    }
    return result;
  }

  Future<Map<String, dynamic>> confirm(Map<String, dynamic> body) async {
    final uri = Uri.parse('$baseUrl/api/v1/ai/receipt/confirm');

    http.Response response;
    try {
      response = await _client.post(
        uri,
        headers: {..._headers, 'Content-Type': 'application/json'},
        body: jsonEncode(body),
      );
    } catch (_) {
      throw Exception('Could not connect to server');
    }

    final decoded = _tryDecode(response.body);

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw Exception(
        decoded?['message'] as String? ?? 'Save failed (${response.statusCode})',
      );
    }

    if (decoded?['status'] != true) {
      throw Exception(decoded?['message'] as String? ?? 'Save failed');
    }

    return decoded?['result'] as Map<String, dynamic>? ?? {};
  }

  Map<String, dynamic>? _tryDecode(String body) {
    try {
      return jsonDecode(body) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }
}
