import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class OtpService {
  Future<void> sendSmsCode(String phoneNumber);

  Future<bool> verifySmsCode(String phoneNumber, String code);

  Future<void> close();
}

class OtpServiceException implements Exception {
  const OtpServiceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class HttpOtpService implements OtpService {
  HttpOtpService({required String baseUrl, HttpClient? httpClient})
      : _baseUri = Uri.parse(baseUrl),
        _client = httpClient ?? HttpClient();

  static const configuredBaseUrl = String.fromEnvironment('OTP_API_BASE_URL');

  static HttpOtpService fromDartDefine() =>
      HttpOtpService(baseUrl: configuredBaseUrl);

  final Uri _baseUri;
  final HttpClient _client;

  @override
  Future<void> sendSmsCode(String phoneNumber) async {
    final response = await _post('/v1/otp/send', {'phoneNumber': phoneNumber});
    if (response['sent'] != true) {
      throw const OtpServiceException('Could not send the verification code.');
    }
  }

  @override
  Future<bool> verifySmsCode(String phoneNumber, String code) async {
    final response = await _post(
        '/v1/otp/verify', {'phoneNumber': phoneNumber, 'code': code});
    return response['verified'] == true;
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, String> body,
  ) async {
    if (!_validBaseUri) {
      throw const OtpServiceException(
        'Phone verification is not configured. Set OTP_API_BASE_URL to your HTTPS OTP service.',
      );
    }
    try {
      final request = await _client
          .postUrl(_baseUri.resolve(path))
          .timeout(const Duration(seconds: 12));
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.cacheControlHeader, 'no-store');
      request.add(utf8.encode(jsonEncode(body)));
      final response =
          await request.close().timeout(const Duration(seconds: 12));
      final responseText = await utf8.decoder
          .bind(response)
          .join()
          .timeout(const Duration(seconds: 12));
      final decoded = jsonDecode(responseText);
      if (decoded is! Map<String, dynamic>) {
        throw const OtpServiceException(
            'The phone verification service returned an invalid response.');
      }
      if (response.statusCode == HttpStatus.tooManyRequests) {
        throw const OtpServiceException(
            'Too many attempts. Wait before trying again.');
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded['error'];
        throw OtpServiceException(
          message is String
              ? message
              : 'Phone verification service is unavailable. Please retry.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const OtpServiceException(
          'The request timed out. Check your connection and retry.');
    } on SocketException {
      throw const OtpServiceException(
          'Could not reach the phone verification service. Check your connection.');
    } on FormatException {
      throw const OtpServiceException(
          'The phone verification service returned an invalid response.');
    }
  }

  bool get _validBaseUri {
    if (_baseUri.host.isEmpty || _baseUri.userInfo.isNotEmpty) return false;
    final local = _baseUri.host == 'localhost' ||
        _baseUri.host == '127.0.0.1' ||
        _baseUri.host == '10.0.2.2';
    return _baseUri.scheme == 'https' || (local && _baseUri.scheme == 'http');
  }

  @override
  Future<void> close() async => _client.close(force: true);
}
