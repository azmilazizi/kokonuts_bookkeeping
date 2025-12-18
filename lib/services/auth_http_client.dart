import 'package:http/http.dart' as http;

import 'auth_expiration_handler.dart';
import 'http_client_factory.dart';

http.Client createAuthAwareClient({http.Client? innerClient}) {
  return AuthAwareHttpClient(
    innerClient: innerClient,
    onUnauthorized: AuthExpirationHandler.instance.handleSessionExpired,
  );
}

class AuthAwareHttpClient extends http.BaseClient {
  AuthAwareHttpClient({
    http.Client? innerClient,
    Future<void> Function()? onUnauthorized,
    Set<int>? unauthorizedStatusCodes,
  })  : _innerClient = innerClient ?? createHttpClient(),
        _onUnauthorized = onUnauthorized,
        _unauthorizedStatusCodes =
            unauthorizedStatusCodes ?? const {401, 403, 419};

  final http.Client _innerClient;
  final Future<void> Function()? _onUnauthorized;
  final Set<int> _unauthorizedStatusCodes;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _innerClient.send(request);
    if (_unauthorizedStatusCodes.contains(response.statusCode)) {
      await _onUnauthorized?.call();
      throw const AuthExpiredException();
    }
    return response;
  }

  @override
  void close() {
    _innerClient.close();
    super.close();
  }
}
