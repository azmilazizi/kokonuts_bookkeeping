import 'package:http/http.dart' as http;

/// Builds an authorization header value for a given token.
typedef AuthorizationHeaderBuilder = String Function(String token);

/// Represents the pieces of authentication information required to build
/// headers for an outgoing HTTP request.
class AuthTokenPayload {
  const AuthTokenPayload({
    required this.authorizationToken,
    required this.authtoken,
  });

  /// The credential portion that should be passed to the Authorization header
  /// builder (generally the token without its scheme).
  final String authorizationToken;

  /// The value that should be applied to the `authtoken` header.
  final String authtoken;

  bool get hasAuthorizationToken => authorizationToken.trim().isNotEmpty;
  bool get hasAuthtoken => authtoken.trim().isNotEmpty;
}

/// An HTTP client that injects authentication headers into each request.
class AuthenticatedHttpClient extends http.BaseClient {
  AuthenticatedHttpClient({
    required Future<AuthTokenPayload?> Function() tokenProvider,
    http.Client? innerClient,
    AuthorizationHeaderBuilder? authorizationBuilder,
  })  : _tokenProvider = tokenProvider,
        _innerClient = innerClient ?? http.Client(),
        _authorizationBuilder = authorizationBuilder ??
            ((token) => token.isEmpty ? token : 'Token $token');

  final Future<AuthTokenPayload?> Function() _tokenProvider;
  final http.Client _innerClient;
  final AuthorizationHeaderBuilder _authorizationBuilder;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final payload = await _tokenProvider();
    if (payload != null) {
      final token = payload.authorizationToken.trim();
      if (token.isNotEmpty) {
        final authorizationValue = _authorizationBuilder(token).trim();
        if (authorizationValue.isNotEmpty) {
          request.headers['Authorization'] = authorizationValue;
        }
      }

      if (payload.hasAuthtoken) {
        request.headers['authtoken'] = payload.authtoken.trim();
      }
    }
    return _innerClient.send(request);
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}
