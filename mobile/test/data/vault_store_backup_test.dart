import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/data/secure_key_value_store.dart';
import 'package:zk_match_id/data/vault_backup_service.dart';
import 'package:zk_match_id/main.dart';

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

    await store.createWallet('Primary wallet');
    await store.saveVerifiedPhone('+919876543210');
    await store.add(credential);
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
