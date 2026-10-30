import 'dart:convert';

/// Decodes a credential payload from a DigiLocker JSON export or QR value.
/// Signed JWS values are decoded for display/matching only; callers must use an
/// issuer trust registry before treating the issuer signature as authentic.
class PresentedCredential {
  const PresentedCredential({
    required this.credential,
    required this.source,
    this.signedToken,
  });

  final Map<String, dynamic> credential;
  final String source;
  final String? signedToken;

  static PresentedCredential decode(String raw) {
    if (utf8.encode(raw).length > 2 * 1024 * 1024) {
      throw const FormatException('Credential exceeds the 2 MB limit.');
    }
    var value = raw.trim();
    const prefix = 'zkmatchid-credential:v1:';
    if (value.startsWith(prefix)) value = value.substring(prefix.length);

    Map<String, dynamic> root;
    if (value.split('.').length == 3) {
      try {
        final payload = _decodeJsonPart(value.split('.')[1]);
        final nested = payload['vc'] ?? payload['credential'];
        if (nested is Map) {
          root = Map<String, dynamic>.from(nested);
        } else {
          throw const FormatException('Signed QR has no credential object.');
        }
        return PresentedCredential(
            credential: root, source: 'signed QR', signedToken: value);
      } on FormatException {
        // It may be ordinary text with periods, so continue as JSON parsing.
      }
    }

    final decoded = jsonDecode(value);
    final rootValue =
        decoded is List && decoded.length == 1 ? decoded.single : decoded;
    if (rootValue is! Map) {
      throw const FormatException('The file or QR must contain a JSON object.');
    }
    root = Map<String, dynamic>.from(rootValue);
    final credential = _findCredential(root, 0);
    if (credential == null) {
      throw const FormatException(
          'No identity credential fields were found in this JSON.');
    }
    return PresentedCredential(
      credential: credential,
      source: root.containsKey('credentialSubject')
          ? 'credential JSON'
          : 'DigiLocker JSON',
      signedToken: root['token'] is String ? root['token'] as String : null,
    );
  }

  static Map<String, dynamic>? _findCredential(
      Map<String, dynamic> value, int depth) {
    if (depth > 6) return null;
    if (value['credentialSubject'] is Map) return value;
    if (value.containsKey('type') &&
        (value.containsKey('issuer') || value.containsKey('issuerName')) &&
        _hasIdentityFields(value)) {
      return value;
    }
    if (_hasIdentityFields(value)) return value;
    for (final key in const [
      'verifiableCredential',
      'credential',
      'vc',
      'issuedDocument',
      'issuedDocuments',
      'document',
      'certificate',
      'response',
      'data',
      'result',
      'payload',
    ]) {
      final nested = value[key];
      if (nested is Map) {
        final found =
            _findCredential(Map<String, dynamic>.from(nested), depth + 1);
        if (found != null) return found;
      } else if (nested is List) {
        for (final item in nested) {
          if (item is Map) {
            final found =
                _findCredential(Map<String, dynamic>.from(item), depth + 1);
            if (found != null) return found;
          }
        }
      }
    }
    return null;
  }

  static bool _hasIdentityFields(Map<String, dynamic> value) {
    final subject = value['credentialSubject'] ?? value['subject'] ?? value;
    if (subject is! Map) return false;
    final normalized = subject.keys.map(_key);
    return normalized.any((key) =>
        const {
          'name',
          'fullname',
          'holdername',
          'firstname',
          'lastname',
          'applicantname',
          'beneficiaryname',
        }.contains(key) ||
        RegExp(r'aadhaar|aadhar|pan|passport|voter|drivinglicen|documentnumber|identitynumber')
            .hasMatch(key));
  }

  static String _key(Object? value) =>
      value.toString().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  static Map<String, dynamic> _decodeJsonPart(String part) {
    final normalized = base64Url.normalize(part);
    final value = jsonDecode(utf8.decode(base64Url.decode(normalized)));
    if (value is! Map) throw const FormatException('Invalid JWS payload.');
    return Map<String, dynamic>.from(value);
  }
}

class CredentialWalletMatch {
  const CredentialWalletMatch({
    required this.nameMatches,
    required this.maskedIdentifierMatches,
    required this.credentialType,
    required this.maskedIdentifiers,
    required this.walletName,
  });

  final bool nameMatches;
  final bool maskedIdentifierMatches;
  final String credentialType;
  final List<String> maskedIdentifiers;
  final String walletName;

  bool get matches => nameMatches && maskedIdentifierMatches;
}

class CredentialWalletMatcher {
  const CredentialWalletMatcher._();

  static CredentialWalletMatch match({
    required String walletName,
    required Map<String, dynamic> presented,
    required List<Map<String, dynamic>> walletCredentials,
  }) {
    final presentedSubject = _subject(presented);
    final presentedName = _name(presentedSubject);
    final walletNames = <String>{};
    if (_isPersonName(walletName)) walletNames.add(_normalizeName(walletName));
    for (final credential in walletCredentials) {
      final name = _name(_subject(credential));
      if (name.isNotEmpty) walletNames.add(_normalizeName(name));
    }
    final nameMatches = presentedName.isNotEmpty &&
        walletNames.contains(_normalizeName(presentedName));

    final presentedIds = _identifiers(presentedSubject);
    final walletIds = <String, Set<String>>{};
    for (final credential in walletCredentials) {
      _identifiers(_subject(credential)).forEach((key, values) {
        walletIds.putIfAbsent(key, () => <String>{}).addAll(values);
      });
    }
    final matchedIds = <String>[];
    for (final entry in presentedIds.entries) {
      final common =
          entry.value.intersection(walletIds[entry.key] ?? const <String>{});
      if (common.isNotEmpty) {
        matchedIds.addAll(common.map((suffix) => '•••• $suffix'));
      }
    }
    final type = _credentialType(presented);
    return CredentialWalletMatch(
      nameMatches: nameMatches,
      maskedIdentifierMatches: matchedIds.isNotEmpty,
      credentialType: type,
      maskedIdentifiers: matchedIds.toSet().toList(),
      walletName: walletName,
    );
  }

  static Map<String, dynamic> _subject(Map<String, dynamic> credential) {
    final subject = credential['credentialSubject'] ??
        credential['subject'] ??
        credential['document'] ??
        credential['data'];
    return subject is Map ? Map<String, dynamic>.from(subject) : credential;
  }

  static String _name(Map<String, dynamic> subject) {
    for (final key in const [
      'name',
      'fullName',
      'holderName',
      'beneficiaryName',
      'applicantName',
    ]) {
      final value = subject[key];
      if (value is String && value.trim().isNotEmpty) return value.trim();
    }
    final parts = [
      subject['firstName'],
      subject['middleName'],
      subject['lastName']
    ]
        .whereType<String>()
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty);
    return parts.join(' ');
  }

  static Map<String, Set<String>> _identifiers(Map<String, dynamic> subject) {
    final result = <String, Set<String>>{};
    for (final entry in subject.entries) {
      final key = entry.key.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
      var category = '';
      if (RegExp(r'aadhaar|aadhar').hasMatch(key)) {
        category = 'aadhaar';
      } else if (key.contains('pan')) {
        category = 'pan';
      } else if (key.contains('passport')) {
        category = 'passport';
      } else if (key.contains('voter')) {
        category = 'voter';
      } else if (key.contains('drivinglicen')) {
        category = 'driving-license';
      } else if (RegExp(r'documentnumber|identitynumber').hasMatch(key)) {
        category = 'document-number';
      }
      if (category.isEmpty) continue;
      final value = entry.value;
      if (value == null || value is Map || value is List) continue;
      final digits = value.toString().replaceAll(RegExp(r'[^0-9]'), '');
      if (digits.length >= 4) {
        result
            .putIfAbsent(category, () => <String>{})
            .add(digits.substring(digits.length - 4));
      }
    }
    return result;
  }

  static String _normalizeName(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  static bool _isPersonName(String value) =>
      value.trim().isNotEmpty &&
      !const {'my wallet', 'personal wallet', 'wallet'}
          .contains(_normalizeName(value));

  static String _credentialType(Map<String, dynamic> credential) {
    final value = credential['type'] ??
        credential['documentType'] ??
        credential['docType'];
    if (value is List) {
      final types = value
          .whereType<String>()
          .where((item) => item != 'VerifiableCredential');
      return types.isEmpty ? 'Identity credential' : types.first;
    }
    return value is String && value.isNotEmpty ? value : 'Identity credential';
  }
}
