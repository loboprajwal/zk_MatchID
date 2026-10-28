import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/onboarding/domain/mnemonic_backup.dart';
import 'package:zk_match_id/features/onboarding/presentation/mnemonic_backup_flow.dart';

void main() {
  testWidgets('restore validates 12 words and returns normalized phrase',
      (tester) async {
    String? restored;
    final phrase = MnemonicBackup.generate();
    await tester.pumpWidget(MaterialApp(
        home: Builder(
            builder: (context) => Scaffold(
                  body: TextButton(
                      onPressed: () async {
                        restored = await Navigator.of(context).push<String>(
                            MaterialPageRoute(
                                builder: (_) => const MnemonicRestoreScreen()));
                      },
                      child: const Text('Open restore')),
                ))));
    await tester.tap(find.text('Open restore'));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.byType(TextField), List.filled(12, 'invalidword').join(' '));
    await tester.tap(find.text('Restore wallet'));
    await tester.pumpAndSettle();
    expect(
        find.text(
            'Enter the original 12-word BIP-39 phrase in the correct order.'),
        findsOneWidget);
    await tester.enterText(find.byType(TextField),
        '  ${phrase.toUpperCase().replaceAll(' ', '   ')}  ');
    await tester.tap(find.text('Restore wallet'));
    await tester.pumpAndSettle();
    expect(restored, phrase);
  });
}
