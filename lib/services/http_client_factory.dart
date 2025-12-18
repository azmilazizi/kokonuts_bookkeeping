import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const String _corsProxyTemplate =
    String.fromEnvironment('CORS_PROXY_TEMPLATE', defaultValue: 'https://corsproxy.io/?');

http.Client createHttpClient({http.Client? innerClient}) {
  final http.Client resolvedInner = innerClient ?? http.Client();
  if (!kIsWeb) {
    return resolvedInner;
  }

  final String proxyTemplate = _corsProxyTemplate.trim();
  if (proxyTemplate.isEmpty) {
    return resolvedInner;
  }

  return _CorsProxyClient(
    innerClient: resolvedInner,
    proxyTemplate: proxyTemplate,
  );
}

Uri _applyProxy(Uri target, String template) {
  final String encodedTarget = Uri.encodeComponent(target.toString());
  if (template.contains('{url}')) {
    return Uri.parse(template.replaceAll('{url}', encodedTarget));
  }

  if (template.endsWith('?') || template.endsWith('&')) {
    return Uri.parse('$template$encodedTarget');
  }

  if (!template.contains('?')) {
    return Uri.parse('$template?$encodedTarget');
  }

  return Uri.parse('$template$encodedTarget');
}

class _CorsProxyClient extends http.BaseClient {
  _CorsProxyClient({
    required http.Client innerClient,
    required String proxyTemplate,
  })  : _innerClient = innerClient,
        _proxyTemplate = proxyTemplate;

  final http.Client _innerClient;
  final String _proxyTemplate;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final Uri proxiedUri = _applyProxy(request.url, _proxyTemplate);
    final http.StreamedRequest forwardRequest =
        http.StreamedRequest(request.method, proxiedUri)
          ..followRedirects = request.followRedirects
          ..maxRedirects = request.maxRedirects
          ..headers.addAll(request.headers);

    if (request.contentLength != null && request.contentLength >= 0) {
      forwardRequest.contentLength = request.contentLength;
    }

    await forwardRequest.sink.addStream(request.finalize());
    await forwardRequest.sink.close();

    return _innerClient.send(forwardRequest);
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}
