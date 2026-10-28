enum FacePose { front, left, right, complete, failed }

/// Pose angles are held as constants and remain visible to the client for UX.
class FacePoseStateMachine {
  static const frontYawLimit = 10.0;
  static const sideYawThreshold = 25.0;
  static const poseTimeout = Duration(seconds: 10);
  FacePose pose = FacePose.front;

  FacePose observe({required int faceCount, required double? yaw}) {
    if (faceCount != 1 || yaw == null) return pose;
    switch (pose) {
      case FacePose.front:
        if (yaw.abs() < frontYawLimit) pose = FacePose.left;
        break;
      case FacePose.left:
        if (yaw > sideYawThreshold) pose = FacePose.right;
        break;
      case FacePose.right:
        if (yaw < -sideYawThreshold) pose = FacePose.complete;
        break;
      case FacePose.complete:
      case FacePose.failed:
        break;
    }
    return pose;
  }

  void timeout() => pose = FacePose.failed;
  void reset() => pose = FacePose.front;
}

abstract interface class FaceEmbedder {
  Future<List<double>> embed(List<int> frameBytes);
}

/// Explicit placeholder; there is no biometric identity matching in Part 1.
class StubFaceEmbedder implements FaceEmbedder {
  @override
  Future<List<double>> embed(List<int> frameBytes) async => const [];
}
