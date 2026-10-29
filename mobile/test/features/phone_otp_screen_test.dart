import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/onboarding/data/otp_service.dart';
import 'package:zk_match_id/features/onboarding/presentation/phone_otp_screen.dart';

void main() {
  testWidgets('phone is stored only after the service approves the code',
      (tester) async {
    final otp = _FakeOtpService();
    String? storedPhone;
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push<String>(
                MaterialPageRoute<String>(
                  builder: (_) => PhoneOtpScreen(
                    otpService: otp,
                    onVerified: (phone) async => storedPhone = phone,
                  ),
                ),
              ),
              child: const Text('Open phone verification'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open phone verification'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '+919876543210');
    await tester.pump();
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();

    expect(otp.sentTo, '+919876543210');
    expect(storedPhone, isNull);
    await tester.enterText(find.byType(TextField).last, '123456');
    await tester.pump();
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(otp.verified, isTrue);
    expect(storedPhone, '+919876543210');
    expect(find.text('Phone number verified'), findsOneWidget);
    await tester.tap(find.text('Continue'));
    await tester.pumpAndSettle();
    expect(find.text('Open phone verification'), findsOneWidget);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('invalid code shows an error and never links the number',
      (tester) async {
    final otp = _FakeOtpService(acceptCode: false);
    String? storedPhone;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneOtpScreen(
          otpService: otp,
          onVerified: (phone) async => storedPhone = phone,
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '+919876543210');
    await tester.pump();
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '000000');
    await tester.pump();
    await tester.tap(find.text('Verify code'));
    await tester.pumpAndSettle();

    expect(
        find.text('That code is incorrect or expired. Check it and try again.'),
        findsOneWidget);
    expect(storedPhone, isNull);
    expect(otp.verified, isFalse);
  });

  testWidgets('resend is held for 30 seconds and then sends another code',
      (tester) async {
    final otp = _FakeOtpService();
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    await tester.pumpWidget(
      MaterialApp(
        home: PhoneOtpScreen(
          otpService: otp,
          onVerified: (_) async {},
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).first, '+919876543210');
    await tester.pump();
    await tester.tap(find.text('Send OTP'));
    await tester.pumpAndSettle();
    expect(otp.sendCount, 1);
    expect(find.text('Resend code in 0:30'), findsOneWidget);

    await tester.pump(const Duration(seconds: 30));
    expect(find.text('Resend code'), findsOneWidget);
    await tester.tap(find.text('Resend code'));
    await tester.pumpAndSettle();
    expect(otp.sendCount, 2);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

class _FakeOtpService implements OtpService {
  _FakeOtpService({this.acceptCode = true});

  final bool acceptCode;
  String? sentTo;
  int sendCount = 0;
  bool verified = false;

  @override
  Future<void> sendSmsCode(String phoneNumber) async {
    sendCount++;
    sentTo = phoneNumber;
  }

  @override
  Future<bool> verifySmsCode(String phoneNumber, String code) async {
    verified = acceptCode && phoneNumber == sentTo && code == '123456';
    return verified;
  }

  @override
  Future<void> close() async {}
}
