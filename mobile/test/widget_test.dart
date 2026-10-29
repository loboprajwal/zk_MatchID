import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zk_match_id/main.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('UPI demo home shows three tabs', (tester) async {
    await tester.pumpWidget(const ZkMatchIdApp());
    await tester.pumpAndSettle();

    expect(find.text('Wallets'), findsWidgets);
    expect(find.text('Prove'), findsWidgets);
    expect(find.text('Verify'), findsWidgets);

    // Switch to Prove
    await tester.tap(find.text('Prove').last);
    await tester.pumpAndSettle();
    expect(find.text('Pick a predicate'), findsOneWidget);

    // Switch to Verify
    await tester.tap(find.text('Verify').last);
    await tester.pumpAndSettle();
    expect(find.text('Verifier mode'), findsOneWidget);
  });
}
