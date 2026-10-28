import 'dart:async';
import 'dart:convert';
import 'dart:io';

abstract interface class OtpService {
  Future<void> sendSmsCode(String phoneNumber);

  Future<bool> verifySmsCode(String phoneNumber, String code);

  Future<void> close();
}

/// Local demo OTP. The code is intentionally fixed and visibly labelled in UI.
/// This is not an authentication service and must be replaced by the backend.
class MockOtpService implements OtpService {
  MockOtpService({DateTime Function()? now}) : _now = now ?? DateTime.now;

  static const demoCode = '1234';
  static const resendDelay = Duration(seconds: 30);
  static const lockDuration = Duration(minutes: 5);
  static const maxAttempts = 5;
  final DateTime Function() _now;
  String? _phone;
  int _attempts = 0;
  DateTime? _lockedUntil;
  DateTime? _lastSent;

  @override
  Future<void> sendSmsCode(String phoneNumber) async {
    if (!RegExp(r'^\+91[6-9]\d{9}$').hasMatch(phoneNumber)) {
      throw const OtpServiceException('Enter a valid +91 mobile number.');
    }
    if (_lockedUntil != null && _now().isBefore(_lockedUntil!)) {
      throw const OtpServiceException('Too many attempts. Try again later.');
    }
    if (_lastSent != null && _now().difference(_lastSent!) < resendDelay) {
      throw const OtpServiceException('Wait 30 seconds before requesting another code.');
    }
    _phone = phoneNumber;
    _attempts = 0;
    _lastSent = _now();
  }

  @override
  Future<bool> verifySmsCode(String phoneNumber, String code) async {
    if (_lockedUntil != null && _now().isBefore(_lockedUntil!)) {
      throw const OtpServiceException('Too many attempts. Try again later.');
    }
    if (phoneNumber == _phone && code == demoCode) return true;
    _attempts++;
    if (_attempts >= maxAttempts) {
      _lockedUntil = _now().add(lockDuration);
      throw const OtpServiceException('Five attempts used. Try again in 5 minutes.');
    }
    return false;
  }

  @override
  Future<void> close() async {}
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
