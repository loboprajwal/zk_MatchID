import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/onboarding/presentation/wallet_setup_screen.dart';

void main() {
  testWidgets(
      'device lock preference is persisted only after authentication succeeds',
      (tester) async {
    WalletSetupResult? result;
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        result = await Navigator.of(context)
                            .push<WalletSetupResult>(MaterialPageRoute(
                                builder: (_) => WalletSetupScreen(
                                    auth: _FakeDeviceAuth(
                                        supported: true,
                                        authenticated: true))));
                      },
                      child: const Text('Open setup')),
                ))));
    await tester.tap(find.text('Open setup'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'Personal wallet');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(find.text('Enabled after successful device authentication.'),
        findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(result?.name, 'Personal wallet');
    expect(result?.deviceLockEnabled, isTrue);
  });

  testWidgets('unsupported device authentication leaves the lock disabled',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: WalletSetupScreen(
            auth: _FakeDeviceAuth(supported: false, authenticated: false))));
    await tester.enterText(find.byType(TextField), 'Personal wallet');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Device authentication is not supported. You can continue with the lock disabled.'),
        findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
  });

  testWidgets('authentication cancellation does not enable the device lock',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: WalletSetupScreen(
            auth: _FakeDeviceAuth(supported: true, authenticated: false))));
    await tester.enterText(find.byType(TextField), 'Personal wallet');
    await tester.tap(find.byType(SwitchListTile));
    await tester.pumpAndSettle();
    expect(
        find.text('Authentication was cancelled. The device lock remains off.'),
        findsOneWidget);
    expect(tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
        isFalse);
  });
}

class _FakeDeviceAuth implements DeviceAuthService {
  _FakeDeviceAuth({required this.supported, required this.authenticated});
  final bool supported;
  final bool authenticated;
  @override
  Future<bool> isDeviceSupported() async => supported;
  @override
  Future<bool> authenticate() async => authenticated;
}
