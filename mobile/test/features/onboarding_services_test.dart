import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/onboarding/data/otp_service.dart';
import 'package:zk_match_id/features/onboarding/domain/face_pose_state_machine.dart';
import 'package:zk_match_id/features/onboarding/domain/mnemonic_backup.dart';
import 'package:zk_match_id/features/onboarding/domain/raw_face_frame_processor.dart';

void main() {
  test('MockOtpService accepts demo code, enforces +91 and locks at five',
      () async {
    var now = DateTime.utc(2026);
    final otp = MockOtpService(now: () => now);
    await expectLater(
        otp.sendSmsCode('+14155552671'), throwsA(isA<OtpServiceException>()));
    await otp.sendSmsCode('+919876543210');
    expect(await otp.verifySmsCode('+919876543210', '1234'), isTrue);
    final locked = MockOtpService(now: () => now);
    await locked.sendSmsCode('+919876543210');
    for (var i = 0; i < 4; i++) {
      expect(await locked.verifySmsCode('+919876543210', '0000'), isFalse);
    }
    await expectLater(locked.verifySmsCode('+919876543210', '0000'),
        throwsA(isA<OtpServiceException>()));
    await expectLater(locked.verifySmsCode('+919876543210', '1234'),
        throwsA(isA<OtpServiceException>()));
    await expectLater(locked.sendSmsCode('+919876543210'),
        throwsA(isA<OtpServiceException>()));
    now = now.add(const Duration(minutes: 5));
    await locked.sendSmsCode('+919876543210');
    expect(await locked.verifySmsCode('+919876543210', '0000'), isFalse);
    expect(await locked.verifySmsCode('+919876543210', '1234'), isTrue);
  });

  test('pose machine requires LEFT then RIGHT then FRONT', () {
    final machine = FacePoseStateMachine();
    expect(machine.pose, FacePose.left);
    expect(machine.observe(faceCount: 1, yaw: 0), FacePose.left);
    expect(machine.observe(faceCount: 1, yaw: -30), FacePose.left);
    expect(machine.observe(faceCount: 2, yaw: 30), FacePose.left);
    expect(machine.observe(faceCount: 1, yaw: 30), FacePose.right);
    expect(machine.observe(faceCount: 1, yaw: -30), FacePose.front);
    expect(machine.observe(faceCount: 1, yaw: 0), FacePose.complete);
    machine.reset();
    machine.timeout();
    expect(machine.pose, FacePose.failed);
    expect(machine.observe(faceCount: 1, yaw: 30), FacePose.failed);
  });

  test('mnemonic confirmation checks requested words and derived key is stable',
      () {
    final phrase = MnemonicBackup.generate();
    final words = phrase.split(' ');
    expect(words, hasLength(12));
    expect(MnemonicBackup.isValid(phrase), isTrue);
    expect(MnemonicBackup.isValid(List.filled(12, 'invalidword').join(' ')),
        isFalse);
    final indices = MnemonicBackup.confirmationIndices();
    expect(indices[0], isNot(indices[1]));
    expect(
        MnemonicBackup.confirm(
            phrase, indices, indices.map((i) => words[i]).toList()),
        isTrue);
    expect(
        MnemonicBackup.confirm(phrase, indices, ['wrong', words[indices[1]]]),
        isFalse);
    expect(MnemonicBackup.deriveWalletKey(phrase),
        MnemonicBackup.deriveWalletKey(phrase));
    expect(MnemonicBackup.deriveWalletKey(phrase).length, 32);
  });

  test('raw face frame is zeroed and deleted after embedder completion',
      () async {
    final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}face-test-${DateTime.now().microsecondsSinceEpoch}.bin');
    await file.writeAsBytes([7, 8, 9, 10]);
    final embedder = _CaptureEmbedder();
    final result =
        await RawFaceFrameProcessor().computeAndDelete(file.path, embedder);
    expect(result, [0.1, 0.2]);
    expect(embedder.buffer, everyElement(0));
    expect(await file.exists(), isFalse);
  });

  test('raw face frame is deleted even when embedding throws', () async {
    final file = File(
        '${Directory.systemTemp.path}${Platform.pathSeparator}face-fail-${DateTime.now().microsecondsSinceEpoch}.bin');
    await file.writeAsBytes([1, 2, 3]);
    await expectLater(
      RawFaceFrameProcessor().computeAndDelete(file.path, _FailingEmbedder()),
      throwsA(isA<StateError>()),
    );
    expect(await file.exists(), isFalse);
  });
}

class _CaptureEmbedder implements FaceEmbedder {
  List<int>? buffer;
  @override
  Future<List<double>> embed(List<int> frameBytes) async {
    buffer = frameBytes;
    return const [0.1, 0.2];
  }
}

class _FailingEmbedder implements FaceEmbedder {
  @override
  Future<List<double>> embed(List<int> frameBytes) async =>
      throw StateError('failed');
}
