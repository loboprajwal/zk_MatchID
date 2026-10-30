import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/onboarding/domain/face_pose_state_machine.dart';
import 'package:zk_match_id/features/onboarding/presentation/face_capture_screen.dart';

void main() {
  testWidgets('pose coach explains each required head turn with live guidance',
      (tester) async {
    for (final (pose, expected) in <(FacePose, String)>[
      (FacePose.front, 'Look straight at the camera'),
      (FacePose.left, 'Slowly turn your face LEFT'),
      (FacePose.right, 'Slowly turn your face RIGHT'),
    ]) {
      await tester.pumpWidget(MaterialApp(home: FacePoseCoach(pose: pose)));
      await tester.pumpAndSettle();
      expect(find.text(expected), findsOneWidget);
      expect(
          find.text('Keep your phone still. Turn your head, not the camera.'),
          findsOneWidget);
    }
  });
}
