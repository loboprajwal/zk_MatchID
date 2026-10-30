import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/data/secure_key_value_store.dart';
import 'package:zk_match_id/data/vault_backup_service.dart';
import 'package:zk_match_id/main.dart';
import 'package:zk_match_id/features/onboarding/domain/mnemonic_backup.dart';

void main() {
  test('encrypted vault backup restores credentials, profile, and activity',
      () async {
    final deviceStorage = _MemorySecureKeyValueStore();
    final store = VaultStore(storage: deviceStorage);
    final credential = <String, dynamic>{
      'id': 'cred-1',
      'issuer': {'name': 'Example issuer'},
      'credentialSubject': {'ageOver18': true},
    };

    await store.saveVerifiedPhone('+919876543210');
    final phrase = MnemonicBackup.generate();
    await store.createWallet('Primary wallet',
        mnemonicDerivedKey: base64UrlEncode(MnemonicBackup.deriveWalletKey(phrase)));
    await store.add(credential);
    final activeWallet = (await store.readWallets()).single;
    final encryptedVault = await deviceStorage.read(
        key: 'credential_vault_${activeWallet['id']}');
    expect(encryptedVault, contains('matchid-encrypted-vault-v1'));
    expect(encryptedVault, isNot(contains('cred-1')));
    await store.addActivity('Credential imported', 'Stored securely');
    final originalActivity = await store.readActivity();
    final archive = await VaultBackupService().encrypt(
      await store.createBackupSnapshot(),
      'correct horse battery staple',
    );
    final decoded = await VaultBackupService().decrypt(
      archive,
      'correct horse battery staple',
    );

    await store.wipe();
    expect(await store.read(), isEmpty);
    await store.restoreBackupSnapshot(decoded);

    expect(
        await store.readWalletConfig(), containsPair('name', 'Primary wallet'));
    expect(await store.read(), [credential]);
    expect(await store.readActivity(), originalActivity);
    expect(await store.readVerifiedPhone(), '+919876543210');
    expect(await store.isBackupCompleted(), isTrue);
    expect(await store.isBackupSkipped(), isFalse);
  });

  test(
      'mnemonic and encrypted file restore recover equivalent wallet key material',
      () async {
    final phrase = MnemonicBackup.generate();
    final key = base64UrlEncode(MnemonicBackup.deriveWalletKey(phrase));
    final source = VaultStore(storage: _MemorySecureKeyValueStore());
    await source.saveVerifiedPhone('+919876543210');
    await source.createWallet('Fixture wallet',
        mnemonicDerivedKey: key, deviceLockEnabled: false);
    final archive = await VaultBackupService().encrypt(
        await source.createBackupSnapshot(), 'correct horse battery staple');
    final snapshot = await VaultBackupService()
        .decrypt(archive, 'correct horse battery staple');

    final phraseRestore = VaultStore(storage: _MemorySecureKeyValueStore());
    await phraseRestore.saveVerifiedPhone('+919876543210');
    await phraseRestore.createWallet('Fixture wallet',
        mnemonicDerivedKey: base64UrlEncode(
            MnemonicBackup.deriveWalletKey(MnemonicBackup.normalize(phrase))),
        deviceLockEnabled: false);
    final fileRestore = VaultStore(storage: _MemorySecureKeyValueStore());
    await fileRestore.restoreBackupSnapshot(snapshot);

    final phraseConfig = await phraseRestore.readWalletConfig();
    final fileConfig = await fileRestore.readWalletConfig();
    expect(phraseConfig?['name'], fileConfig?['name']);
    expect(
        phraseConfig?['mnemonicDerivedKey'], fileConfig?['mnemonicDerivedKey']);
    expect(phraseConfig?['mnemonicDerivedKey'], key);
    expect(await phraseRestore.read(), await fileRestore.read());
  });

  test('wallets are isolated and legacy vault migrates without losing credentials', () async {
    final storage = _MemorySecureKeyValueStore();
    final firstCredential = {'id': 'legacy-credential', 'name': 'Demo Holder'};
    await storage.write(key: 'wallet_config_v1', value: jsonEncode({
      'name': 'Legacy wallet',
      'mnemonicDerivedKey': base64UrlEncode(List<int>.filled(32, 7)),
      'deviceLockEnabled': false,
      'createdAt': '2025-01-01T00:00:00.000Z',
    }));
    await storage.write(key: 'credential_vault_v1', value: jsonEncode([firstCredential]));
    final store = VaultStore(storage: storage);
    await store.saveVerifiedPhone('+919876543210');
    final secondPhrase = MnemonicBackup.generate();
    await store.createWallet('Travel wallet',
        mnemonicDerivedKey: base64UrlEncode(MnemonicBackup.deriveWalletKey(secondPhrase)),
        deviceLockEnabled: false);
    await store.add({'id': 'second-credential'});

    final wallets = await store.readWallets();
    expect(wallets, hasLength(2));
    expect(wallets.map((wallet) => wallet['nameMasked']), everyElement(isA<String>()));
    expect(await store.read(), [{'id': 'second-credential'}]);
    await expectLater(store.add(firstCredential), throwsStateError);
    final legacy = wallets.singleWhere((wallet) => wallet['nameMasked'] == 'Le•••••');
    await store.selectWallet(legacy['id'] as String);
    expect((await store.readWalletConfig())?['name'], 'Legacy wallet');
    expect(await store.read(), [firstCredential]);
    expect(await storage.read(key: 'credential_vault_v1'), isNull);
    final migrated = await storage.read(key: 'credential_vault_${legacy['id']}');
    expect(migrated, contains('matchid-encrypted-vault-v1'));
    expect(migrated, isNot(contains('legacy-credential')));
  });

  test('credential vault ciphertext cannot be opened with a different mnemonic key', () async {
    final storage = _MemorySecureKeyValueStore();
    final store = VaultStore(storage: storage);
    await store.saveVerifiedPhone('+919876543210');
    final phrase = MnemonicBackup.generate();
    final key = base64UrlEncode(MnemonicBackup.deriveWalletKey(phrase));
    await store.createWallet('Protected wallet',
        mnemonicDerivedKey: key, deviceLockEnabled: false);
    await store.add({'id': 'secret-document'});
    final config = await store.readWalletConfig();
    await storage.write(key: 'wallet_config_${(await store.readWallets()).single['id']}', value: jsonEncode({
      ...config!,
      'mnemonicDerivedKey': base64UrlEncode(List<int>.filled(32, 99)),
    }));
    await expectLater(store.read(), throwsA(anything));
  });
}

class _MemorySecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> _values = {};

  @override
  Future<String?> read({required String key}) async => _values[key];

  @override
  Future<void> write({required String key, required String value}) async {
    _values[key] = value;
  }

  @override
  Future<void> delete({required String key}) async {
    _values.remove(key);
  }
}
