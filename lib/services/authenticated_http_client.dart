import 'package:http/http.dart' as http;

/// Builds an authorization header value for a given token.
typedef AuthorizationHeaderBuilder = String Function(String token);

/// An HTTP client that injects authentication headers into each request.
class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient({
    required Future<String?> Function() tokenProvider,
    http.Client? innerClient,
    AuthorizationHeaderBuilder? authorizationBuilder,
  })  : _tokenProvider = tokenProvider,
        _innerClient = innerClient ?? http.Client(),
        _authorizationBuilder = authorizationBuilder ??
            ((token) => token.isEmpty ? token : 'Token $token');

  final Future<String?> Function() _tokenProvider;
  final http.Client _innerClient;
  final AuthorizationHeaderBuilder _authorizationBuilder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final token = await _tokenProvider();
    if (token != null && token.isNotEmpty) {
      final authorizationValue = _authorizationBuilder(token).trim();
      if (authorizationValue.isNotEmpty) {
        request.headers['Authorization'] = authorizationValue;
      }
      request.headers['authtoken'] = token;
    }
    return _innerClient.send(request);
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}
