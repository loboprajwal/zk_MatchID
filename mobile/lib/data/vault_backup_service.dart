import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

class VaultBackupService {
  VaultBackupService({AesGcm? cipher})
      : _cipher = cipher ?? AesGcm.with256bits();

  static const format = 'zk-matchid-vault-backup';
  static const version = 1;
  static const maxArchiveBytes = 100 * 1024 * 1024;
  static const _iterations = 310000;
  final AesGcm _cipher;

  Future<List<int>> encrypt(
      Map<String, dynamic> snapshot, String passphrase) async {
    _validatePassphrase(passphrase);
    final cleartext = utf8.encode(jsonEncode(snapshot));
    if (cleartext.length > maxArchiveBytes) {
      throw const FormatException(
          'This vault is too large to export in one backup file.');
    }

    final random = Random.secure();
    final salt = List<int>.generate(16, (_) => random.nextInt(256));
    final key = await _deriveKey(passphrase, salt);
    final box = await _cipher.encrypt(cleartext, secretKey: key);
    final envelope = <String, dynamic>{
      'format': format,
      'version': version,
      'kdf': 'PBKDF2-HMAC-SHA256',
      'iterations': _iterations,
      'salt': base64Encode(salt),
      'nonce': base64Encode(box.nonce),
      'ciphertext': base64Encode(box.cipherText),
      'tag': base64Encode(box.mac.bytes),
    };
    final output = utf8.encode(jsonEncode(envelope));
    if (output.length > maxArchiveBytes) {
      throw const FormatException(
          'This vault is too large to export in one backup file.');
    }
    return output;
  }

  Future<Map<String, dynamic>> decrypt(
      List<int> archive, String passphrase) async {
    _validatePassphrase(passphrase);
    if (archive.isEmpty || archive.length > maxArchiveBytes) {
      throw const FormatException(
          'The backup file is empty or exceeds the supported size.');
    }
    try {
      final decoded = jsonDecode(utf8.decode(archive));
      if (decoded is! Map ||
          decoded['format'] != format ||
          decoded['version'] != version ||
          decoded['kdf'] != 'PBKDF2-HMAC-SHA256' ||
          decoded['iterations'] != _iterations) {
        throw const FormatException(
            'This backup file format is not supported.');
      }
      final salt = base64Decode(_stringField(decoded, 'salt'));
      final nonce = base64Decode(_stringField(decoded, 'nonce'));
      final ciphertext = base64Decode(_stringField(decoded, 'ciphertext'));
      final tag = base64Decode(_stringField(decoded, 'tag'));
      if (salt.length != 16 || nonce.length != 12 || tag.length != 16) {
        throw const FormatException('The backup file is invalid.');
      }
      final key = await _deriveKey(passphrase, salt);
      final cleartext = await _cipher.decrypt(
        SecretBox(ciphertext, nonce: nonce, mac: Mac(tag)),
        secretKey: key,
      );
      final snapshot = jsonDecode(utf8.decode(cleartext));
      if (snapshot is! Map<String, dynamic>) {
        throw const FormatException('The backup data is invalid.');
      }
      return snapshot;
    } on SecretBoxAuthenticationError {
      throw const FormatException(
          'The passphrase is incorrect or the backup file was changed.');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
          'Could not read this backup. Check the passphrase and try again.');
    }
  }

  Future<SecretKey> _deriveKey(String passphrase, List<int> salt) => Pbkdf2(
        macAlgorithm: Hmac.sha256(),
        iterations: _iterations,
        bits: 256,
      ).deriveKey(secretKey: SecretKey(utf8.encode(passphrase)), nonce: salt);

  String _stringField(Map<dynamic, dynamic> data, String key) {
    final value = data[key];
    if (value is! String || value.isEmpty) {
      throw const FormatException('The backup file is invalid.');
    }
    return value;
  }

  void _validatePassphrase(String passphrase) {
    if (passphrase.length < 12) {
      throw const FormatException(
          'Use a backup passphrase with at least 12 characters.');
    }
  }
}
