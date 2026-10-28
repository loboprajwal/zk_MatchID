import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:zk_match_id/features/onboarding/presentation/face_capture_screen.dart';

void main() {
  testWidgets('camera permission rationale can be cancelled', (tester) async {
    tester.view.physicalSize = const Size(400, 850);
    tester.view.devicePixelRatio = 1;
    final faceService = MockFaceVerificationService((InputImage _) async => []);
    await tester.pumpWidget(
      MaterialApp(home: FaceCaptureScreen(faceService: faceService)),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Allow camera'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Camera access'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump();
    expect(find.text('Allow camera'), findsOneWidget);
    expect(find.text('Camera access'), findsNothing);
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  testWidgets('face detector is closed when capture screen is disposed',
      (tester) async {
    var closed = false;
    final faceService = MockFaceVerificationService(
      (InputImage _) async => [],
      onClose: () async => closed = true,
    );
    await tester.pumpWidget(
        MaterialApp(home: FaceCaptureScreen(faceService: faceService)));
    await tester.pump();
    await tester.pumpWidget(const MaterialApp(home: SizedBox.shrink()));
    await tester.pump();
    expect(closed, isTrue);
  });
}
