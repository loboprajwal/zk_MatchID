import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class DocumentProvider {
  Future<Map<String, dynamic>> fetchDocument({
    required String type,
    required String verifiedPhone,
  });

  Future<Map<String, dynamic>> fetchIssuerKey();

  Future<void> close();
}

/// HTTP adapter for the loopback-only fictional issuer service. It is disabled
/// unless a valid local or HTTPS endpoint is explicitly configured.
class SimulatedDigiLockerHttpProvider implements DocumentProvider {
  SimulatedDigiLockerHttpProvider({
    required String baseUrl,
    HttpClient? client,
  })  : _baseUri = Uri.tryParse(baseUrl),
        _client = client ?? HttpClient();

  static const configuredBaseUrl =
      String.fromEnvironment('SIMULATED_ISSUER_API_URL');

  factory SimulatedDigiLockerHttpProvider.fromDartDefine() =>
      SimulatedDigiLockerHttpProvider(
        baseUrl: configuredBaseUrl,
      );

  final Uri? _baseUri;
  final HttpClient _client;

  @override
  Future<Map<String, dynamic>> fetchIssuerKey() async {
    final baseUri = _baseUri;
    if (baseUri == null || !_isAllowedUri(baseUri)) {
      throw const HttpException(
        'Simulated DigiLocker is not configured. Set SIMULATED_ISSUER_API_URL.',
      );
    }
    try {
      final request = await _client
          .getUrl(baseUri.resolve('/v1/public-key'))
          .timeout(const Duration(seconds: 10));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final body = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(body);
      if (response.statusCode != HttpStatus.ok ||
          decoded is! Map<String, dynamic> ||
          decoded['demoOnly'] != true ||
          decoded['issuer'] is! String ||
          decoded['id'] is! String ||
          decoded['publicKey'] is! String ||
          decoded['algorithm'] != 'EdDSA') {
        throw const HttpException(
            'The configured issuer did not return a valid demo trust key.');
      }
      return decoded;
    } on TimeoutException {
      throw const HttpException('Demo issuer key request timed out.');
    } on SocketException {
      throw const HttpException('Could not reach the local demo issuer.');
    } on FormatException {
      throw const HttpException('Demo issuer returned invalid key JSON.');
    }
  }

  @override
  Future<Map<String, dynamic>> fetchDocument({
    required String type,
    required String verifiedPhone,
  }) async {
    const allowed = {'aadhaar', 'voter_id', 'passport', 'college'};
    if (!allowed.contains(type)) {
      throw const FormatException(
          'Choose one of the supported demo document types.');
    }
    final baseUri = _baseUri;
    if (baseUri == null || !_isAllowedUri(baseUri)) {
      throw const HttpException(
        'Simulated DigiLocker is not configured. Set SIMULATED_ISSUER_API_URL to a local demo server or HTTPS endpoint.',
      );
    }
    try {
      final request = await _client
          .postUrl(baseUri.resolve('/v1/demo/issue'))
          .timeout(const Duration(seconds: 10));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.add(utf8.encode(jsonEncode({
        'type': type,
        'verifiedPhone': verifiedPhone,
      })));
      final response =
          await request.close().timeout(const Duration(seconds: 10));
      final bodyText = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 10));
      final decoded = jsonDecode(bodyText);
      if (decoded is! Map<String, dynamic>) {
        throw const FormatException('Issuer returned an invalid response.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final error = decoded['error'];
        throw HttpException(
          error is String ? error : 'Could not retrieve the demo credential.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const HttpException('Demo issuer request timed out. Try again.');
    } on SocketException {
      throw const HttpException(
          'Could not reach the local demo issuer. Start the issuer service and retry.');
    } on FormatException {
      throw const HttpException('Demo issuer returned invalid JSON.');
    }
  }

  bool _isAllowedUri(Uri uri) {
    if (uri.host.isEmpty || uri.userInfo.isNotEmpty) return false;
    final local = const {'localhost', '127.0.0.1', '10.0.2.2'}
        .contains(uri.host.toLowerCase());
    return uri.scheme == 'https' || (local && uri.scheme == 'http');
  }

  @override
  Future<void> close() async => _client.close(force: true);
}
