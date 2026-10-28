import 'dart:math';
import 'dart:convert';
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';

class MnemonicBackup {
  static String generate() => bip39.generateMnemonic(strength: 128);
  static String normalize(String phrase) => phrase
      .toLowerCase()
      .trim()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .join(' ');

  static bool isValid(String phrase) =>
      bip39.validateMnemonic(normalize(phrase));

  /// Stable wallet key material derived from the BIP-39 seed, never from the
  /// display string alone. The phrase is therefore required to restore it.
  static List<int> deriveWalletKey(String phrase) {
    final normalized = normalize(phrase);
    if (normalized.split(' ').length != 12 || !isValid(normalized)) {
      throw const FormatException('Enter a valid 12-word recovery phrase.');
    }
    final seed = bip39.mnemonicToSeed(normalized);
    return Hmac(sha256, seed)
        .convert(utf8.encode('zk-matchid-wallet-key-v1'))
        .bytes;
  }

  static String deriveWalletId(String phrase) =>
      sha256.convert(deriveWalletKey(phrase)).toString().substring(0, 32);

  static List<int> confirmationIndices() {
    final rng = Random.secure();
    final first = rng.nextInt(12);
    var second = rng.nextInt(11);
    if (second >= first) second++;
    final result = [first, second]..sort();
    return result;
  }

  static bool confirm(String phrase, List<int> indices, List<String> entries) {
    final words = normalize(phrase).split(' ');
    return words.length == 12 &&
        indices.length == 2 &&
        entries.length == 2 &&
        indices.asMap().entries.every((e) =>
            e.value >= 0 &&
            e.value < 12 &&
            words[e.value] == normalize(entries[e.key]));
  }
}
