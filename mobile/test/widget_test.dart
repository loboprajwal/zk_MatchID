import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/main.dart';
import 'package:zk_match_id/data/vault_repository.dart';
import 'package:zk_match_id/features/onboarding/data/otp_service.dart';
import 'package:zk_match_id/features/onboarding/onboarding_dependencies.dart';
import 'package:zk_match_id/features/onboarding/presentation/face_capture_screen.dart';
import 'package:zk_match_id/features/onboarding/presentation/wallet_setup_screen.dart';

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
    await tester.pumpWidget(MatchIdApp(
      vaultRepository: repository,
      onboardingDependencies: OnboardingDependencies(
        otpServiceFactory: MockOtpService.new,
        faceCaptureScreenBuilder: _PassingFaceScreen.new,
        walletSetupScreenBuilder: _TestWalletSetupScreen.new,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Create new wallet'));
    await tester.pumpAndSettle();
    expect(find.text('Demo mode: OTP simulated'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, '9876543210');
    await tester.pump();
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(find.text('Verify your phone number'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(5));
    for (var i = 0; i < 4; i++) {
      await tester.enterText(find.byType(TextField).at(i + 1), '${i + 1}');
    }
    await tester.pump();
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();
    expect(find.text('Phone number verified'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Complete face pose demo'));
    await tester.pumpAndSettle();
    expect(find.text('Face and number verified'), findsOneWidget);
    expect(find.textContaining('no biometric identity match'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use test wallet setup'));
    await tester.pumpAndSettle();

    expect(find.text('Back up your wallet'), findsOneWidget);
    final words = tester.widgetList<Chip>(find.byType(Chip)).map((chip) {
      final text = (chip.label as Text).data!;
      return text.substring(text.indexOf('. ') + 2);
    }).toList();
    expect(words, hasLength(12));
    await tester.tap(find.text('I saved my phrase'));
    await tester.pumpAndSettle();
    final confirmationFields =
        tester.widgetList<TextField>(find.byType(TextField)).toList();
    for (var i = 0; i < confirmationFields.length; i++) {
      final label = confirmationFields[i].decoration!.labelText!;
      final position = int.parse(label.replaceFirst('Word ', '')) - 1;
      await tester.enterText(find.byType(TextField).at(i), words[position]);
    }
    await tester.tap(find.text('Confirm'));
    await tester.pumpAndSettle();

    expect(find.text('Back up your wallet'), findsOneWidget);
    await tester.tap(find.text('Skip for now'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm backup skip'), findsOneWidget);

    await tester.tap(find.text('Skip anyway'));
    await tester.pumpAndSettle();
    expect(repository.skipped, isTrue);
    expect(find.text('Wallet backup skipped'), findsOneWidget);
    expect(repository.createdName, 'Test wallet');
    expect(repository.createdMnemonicKey, isNotEmpty);
  });

  testWidgets(
      'back navigation from phone entry cancels creation without bypassing onboarding',
      (tester) async {
    final repository = _TestVaultRepository(hasWallet: false);
    await tester.pumpWidget(MatchIdApp(vaultRepository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Create new wallet'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Create new wallet'), findsOneWidget);
    expect(repository.createdName, isNull);
  });
}

class _TestVaultRepository implements VaultRepository {
  _TestVaultRepository({bool hasWallet = true}) : _hasWallet = hasWallet;

  bool _hasWallet;
  bool skipped = false;
  String? createdName;
  String? createdMnemonicKey;

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
  Future<void> createWallet(String name,
          {String? mnemonicDerivedKey, bool deviceLockEnabled = true}) async =>
      (() {
        _hasWallet = true;
        createdName = name;
        createdMnemonicKey = mnemonicDerivedKey;
      })();

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

class _PassingFaceScreen extends StatelessWidget {
  const _PassingFaceScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: FilledButton(
                onPressed: () => Navigator.pop(
                    context,
                    const FaceCaptureResult(
                        faceDetected: true, movementChallengePassed: true)),
                child: const Text('Complete face pose demo'))),
      );
}

class _TestWalletSetupScreen extends StatelessWidget {
  const _TestWalletSetupScreen();
  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
            child: FilledButton(
                onPressed: () => Navigator.pop(
                    context,
                    const WalletSetupResult(
                        name: 'Test wallet', deviceLockEnabled: false)),
                child: const Text('Use test wallet setup'))),
      );
}
