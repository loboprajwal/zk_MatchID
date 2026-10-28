import 'dart:math';
import 'dart:convert';
import 'package:bip39/bip39.dart' as bip39;
import 'package:crypto/crypto.dart';

class MnemonicBackup {
  static String generate() => bip39.generateMnemonic(strength: 128);
  static bool isValid(String phrase) => bip39.validateMnemonic(phrase.trim());

  /// Stable wallet key material derived from the BIP-39 seed, never from the
  /// display string alone. The phrase is therefore required to restore it.
  static List<int> deriveWalletKey(String phrase) {
    if (!isValid(phrase)) throw const FormatException('Invalid recovery phrase.');
    final seed = bip39.mnemonicToSeed(phrase.trim());
    return Hmac(sha256, seed).convert(utf8.encode('zk-matchid-wallet-key-v1')).bytes;
  }

  static List<int> confirmationIndices({Random? random}) {
    final rng = random ?? Random.secure();
    final first = rng.nextInt(12);
    var second = rng.nextInt(11);
    if (second >= first) second++;
    final result = [first, second]..sort();
    return result;
  }

  static bool confirm(String phrase, List<int> indices, List<String> entries) {
    final words = phrase.trim().split(RegExp(r'\s+'));
    return words.length == 12 && indices.length == 2 && entries.length == 2 &&
        indices.asMap().entries.every((e) => e.value >= 0 && e.value < 12 && words[e.value] == entries[e.key].trim());
  }
}
