import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/main.dart';
import 'package:zk_match_id/data/vault_repository.dart';

void main() {
  testWidgets('wallet shell starts locked and settings are reachable',
      (tester) async {
    await tester
        .pumpWidget(MatchIdApp(vaultRepository: _TestVaultRepository()));
    await tester.pumpAndSettle();

    expect(find.text('My credentials'), findsOneWidget);
    expect(find.text('Wallet locked'), findsOneWidget);

    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();

    expect(find.text('Manage local security and stored credentials.'),
        findsOneWidget);
    final settingsList = find.ancestor(
      of: find.text('Manage local security and stored credentials.'),
      matching: find.byType(ListView),
    );
    await tester.drag(settingsList, const Offset(0, -700));
    await tester.pumpAndSettle();
    expect(find.text('Wipe wallet data'), findsOneWidget);
  });

  testWidgets('new wallet can skip backup only after confirmation',
      (tester) async {
    final repository = _TestVaultRepository(hasWallet: false);
    await tester.pumpWidget(MatchIdApp(vaultRepository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create new wallet'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'My wallet');
    await tester.tap(find.text('Create wallet'));
    await tester.pumpAndSettle();

    expect(find.text('Back up your wallet'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm backup skip'), findsOneWidget);

    await tester.tap(find.text('Skip anyway'));
    await tester.pumpAndSettle();
    expect(repository.skipped, isTrue);
    expect(find.text('Wallet backup skipped'), findsOneWidget);
  });
}

class _TestVaultRepository implements VaultRepository {
  _TestVaultRepository({bool hasWallet = true}) : _hasWallet = hasWallet;

  bool _hasWallet;
  bool skipped = false;

  @override
  Future<List<Map<String, dynamic>>> read() async => [];

  @override
  Future<List<Map<String, dynamic>>> readActivity() async => [];

  @override
  Future<Map<String, dynamic>?> readWalletConfig() async =>
      _hasWallet ? {'name': 'Test wallet'} : null;

  @override
  Future<String?> readVerifiedPhone() async => null;

  @override
  Future<void> saveVerifiedPhone(String phoneNumber) async {}

  @override
  Future<void> createWallet(String name, {String? mnemonicDerivedKey}) async =>
      _hasWallet = true;

  @override
  Future<void> add(Map<String, dynamic> credential) async {}

  @override
  Future<void> write(List<Map<String, dynamic>> credentials) async {}

  @override
  Future<List<Map<String, dynamic>>> addActivity(
    String title,
    String detail,
  ) async =>
      [];

  @override
  Future<void> wipe() async {}

  @override
  Future<bool> isBackupSkipped() async => skipped;

  @override
  Future<void> setBackupSkipped(bool skipped) async => this.skipped = skipped;

  @override
  Future<bool> isBackupCompleted() async => false;

  @override
  Future<void> setBackupCompleted(bool completed) async {}

  @override
  Future<Map<String, dynamic>> createBackupSnapshot() async => {
        'format': 'zk-matchid-wallet-state',
        'version': 1,
        'walletConfig': {'name': 'Test wallet'},
        'credentials': [],
        'activity': [],
      };

  @override
  Future<void> restoreBackupSnapshot(Map<String, dynamic> snapshot) async {}
}
