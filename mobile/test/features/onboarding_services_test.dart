import 'dart:math';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/onboarding/data/otp_service.dart';
import 'package:zk_match_id/features/onboarding/domain/face_pose_state_machine.dart';
import 'package:zk_match_id/features/onboarding/domain/mnemonic_backup.dart';

void main() {
  test('MockOtpService accepts demo code, enforces +91 and locks at five', () async {
    var now = DateTime.utc(2026);
    final otp = MockOtpService(now: () => now);
    await expectLater(otp.sendSmsCode('+14155552671'), throwsA(isA<OtpServiceException>()));
    await otp.sendSmsCode('+919876543210');
    expect(await otp.verifySmsCode('+919876543210', '1234'), isTrue);
    final locked = MockOtpService(now: () => now);
    await locked.sendSmsCode('+919876543210');
    for (var i = 0; i < 4; i++) { expect(await locked.verifySmsCode('+919876543210', '0000'), isFalse); }
    await expectLater(locked.verifySmsCode('+919876543210', '0000'), throwsA(isA<OtpServiceException>()));
    now = now.add(const Duration(minutes: 5));
    await locked.sendSmsCode('+919876543210');
    expect(await locked.verifySmsCode('+919876543210', '1234'), isTrue);
  });

  test('pose machine requires FRONT then LEFT then RIGHT', () {
    final machine = FacePoseStateMachine();
    expect(machine.observe(faceCount: 1, yaw: 0), FacePose.left);
    expect(machine.observe(faceCount: 1, yaw: -30), FacePose.left);
    expect(machine.observe(faceCount: 2, yaw: 30), FacePose.left);
    expect(machine.observe(faceCount: 1, yaw: 30), FacePose.right);
    expect(machine.observe(faceCount: 1, yaw: -30), FacePose.complete);
    machine.reset();
    machine.timeout();
    expect(machine.pose, FacePose.failed);
  });

  test('mnemonic confirmation checks requested words and derived key is stable', () {
    final phrase = MnemonicBackup.generate();
    final words = phrase.split(' ');
    final indices = MnemonicBackup.confirmationIndices(random: Random(4));
    expect(MnemonicBackup.confirm(phrase, indices, indices.map((i) => words[i]).toList()), isTrue);
    expect(MnemonicBackup.confirm(phrase, indices, ['wrong', words[indices[1]]]), isFalse);
    expect(MnemonicBackup.deriveWalletKey(phrase), MnemonicBackup.deriveWalletKey(phrase));
    expect(MnemonicBackup.deriveWalletKey(phrase).length, 32);
  });
}
