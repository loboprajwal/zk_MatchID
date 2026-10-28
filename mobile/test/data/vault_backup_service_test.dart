import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/data/vault_backup_service.dart';

void main() {
  const snapshot = <String, dynamic>{
    'format': 'zk-matchid-wallet-state',
    'version': 1,
    'walletConfig': {'name': 'Primary'},
    'credentials': [
      {
        'type': ['VerifiableCredential', 'AgeCredential'],
        'credentialSubject': {'ageOver18': true},
      },
    ],
    'activity': [
      {'title': 'Imported credential', 'detail': 'Accepted'},
    ],
  };

  test('encrypted backup round trips without exposing wallet JSON', () async {
    final service = VaultBackupService();
    const passphrase = 'correct horse battery staple';

    final archive = await service.encrypt(snapshot, passphrase);
    final archiveText = String.fromCharCodes(archive);
    expect(archiveText, contains(VaultBackupService.format));
    expect(archiveText, isNot(contains('AgeCredential')));
    expect(archiveText, isNot(contains('Primary')));
    expect(await service.decrypt(archive, passphrase), snapshot);
  });

  test('wrong passphrase is rejected without returning wallet contents',
      () async {
    final service = VaultBackupService();
    final archive =
        await service.encrypt(snapshot, 'correct horse battery staple');

    await expectLater(
      service.decrypt(archive, 'incorrect horse battery staple'),
      throwsA(isA<FormatException>()),
    );
  });
}
