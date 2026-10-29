import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/face_pose_state_machine.dart';
import '../domain/raw_face_frame_processor.dart';

class FaceCaptureResult {
  const FaceCaptureResult({
    required this.faceDetected,
    required this.movementChallengePassed,
  });

  final bool faceDetected;
  final bool movementChallengePassed;
}

abstract interface class FaceVerificationService {
  Future<List<Face>> detectFaces(InputImage image);

  Future<void> close();
}

class MlKitFaceVerificationService implements FaceVerificationService {
  MlKitFaceVerificationService()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            // Accurate mode is more reliable for yaw estimation than fast mode,
            // especially on smaller faces and indoor camera feeds.
            performanceMode: FaceDetectorMode.accurate,
            enableLandmarks: true,
            enableClassification: true,
            minFaceSize: 0.08,
          ),
        );

  final FaceDetector _detector;

  @override
  Future<List<Face>> detectFaces(InputImage image) =>
      _detector.processImage(image);

  @override
  Future<void> close() => _detector.close();
}

class MockFaceVerificationService implements FaceVerificationService {
  MockFaceVerificationService(this.resultForImage, {this.onClose});

  final Future<List<Face>> Function(InputImage image) resultForImage;
  final Future<void> Function()? onClose;

  @override
  Future<List<Face>> detectFaces(InputImage image) => resultForImage(image);

  @override
  Future<void> close() async {
    await onClose?.call();
  }
}

class FaceCaptureScreen extends StatefulWidget {
  const FaceCaptureScreen({super.key, this.faceService});

  final FaceVerificationService? faceService;

  @override
  State<FaceCaptureScreen> createState() => _FaceCaptureScreenState();
}

class _FaceCaptureScreenState extends State<FaceCaptureScreen>
    with WidgetsBindingObserver {
  late final FaceVerificationService _faceService;
  CameraController? _camera;
  XFile? _capturedImage;
  bool _permissionGranted = false;
  bool _requestingPermission = false;
  bool _initializing = false;
  bool _processingFrame = false;
  bool _faceCentered = false;
  bool _lightingLow = false;
  final FacePoseStateMachine _poseMachine = FacePoseStateMachine();
  final FaceEmbedder _embedder = StubFaceEmbedder();
  final RawFaceFrameProcessor _frameProcessor = RawFaceFrameProcessor();
  Timer? _poseTimer;
  int _faceCount = 0;
  String? _error;

  bool get _canCapture =>
      _camera?.value.isInitialized == true &&
      _faceCount == 1 &&
      _faceCentered &&
      _poseMachine.pose == FacePose.complete &&
      _capturedImage == null &&
      !_processingFrame;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _faceService = widget.faceService ?? MlKitFaceVerificationService();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final camera = _camera;
      _camera = null;
      if (camera != null) unawaited(camera.dispose());
    } else if (state == AppLifecycleState.resumed &&
        _permissionGranted &&
        _capturedImage == null) {
      unawaited(_startCamera());
    }
  }

  Future<void> _requestCamera() async {
    if (_requestingPermission || _permissionGranted) return;
    setState(() {
      _requestingPermission = true;
      _error = null;
    });
    try {
      final understood = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Camera access'),
          content: const Text(
            'The front camera is used on this device to detect one centered face. The image is not uploaded or kept after you leave this screen.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (!mounted || understood != true) return;
      var status = await Permission.camera.status;
      if (!status.isGranted) status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        setState(() {
          _error = status.isPermanentlyDenied || status.isRestricted
              ? 'Camera access is blocked. Allow it in system settings to continue.'
              : 'Camera access is needed to capture a face.';
        });
        return;
      }
      setState(() => _permissionGranted = true);
      await _startCamera();
    } catch (_) {
      if (mounted) {
        setState(() =>
            _error = 'Could not request camera access. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _requestingPermission = false);
    }
  }

  Future<void> _openSettings() async {
    await openAppSettings();
  }

  Future<void> _startCamera() async {
    if (_initializing || _camera != null || !mounted) return;
    CameraController? pendingCamera;
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      final cameras = await availableCameras();
      final frontCamera = cameras.where(
        (camera) => camera.lensDirection == CameraLensDirection.front,
      );
      if (frontCamera.isEmpty) {
        throw CameraException(
          'FrontCameraUnavailable',
          'This device has no front-facing camera.',
        );
      }
      final camera = CameraController(
        frontCamera.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      pendingCamera = camera;
      await camera.initialize();
      await camera.lockCaptureOrientation(DeviceOrientation.portraitUp);
      if (!mounted) {
        await camera.dispose();
        return;
      }
      _camera = camera;
      pendingCamera = null;
      _startPoseTimer();
      await camera.startImageStream(_processFrame);
      if (mounted) setState(() {});
    } on CameraException catch (exception) {
      final pending = pendingCamera;
      if (pending != null) await pending.dispose();
      if (mounted) {
        setState(() {
          _error = switch (exception.code) {
            'CameraAccessDenied' ||
            'CameraAccessDeniedWithoutPrompt' =>
              'Camera access was denied. Allow it in system settings to continue.',
            'CameraAccessRestricted' =>
              'Camera access is restricted on this device.',
            'FrontCameraUnavailable' =>
              'This device has no front-facing camera.',
            _ => 'Could not start the camera. Please try again.',
          };
        });
      }
    } catch (_) {
      final pending = pendingCamera;
      if (pending != null) await pending.dispose();
      if (mounted) {
        setState(
            () => _error = 'Could not start the camera. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _initializing = false);
    }
  }

  Future<void> _processFrame(CameraImage image) async {
    if (_processingFrame || _capturedImage != null) return;
    _processingFrame = true;
    try {
      final inputImage = _inputImage(image);
      if (inputImage == null) return;
      final lowLight = _estimateLuma(image) < FaceCaptureTuning.minimumLuma;
      final faces = await _faceService.detectFaces(inputImage);
      final rotated = _rotationDegrees(_camera!) % 180 != 0;
      final frameWidth = rotated ? image.height : image.width;
      final frameHeight = rotated ? image.width : image.height;
      final centered = faces.length == 1 &&
          _isFaceCentered(
            faces.single.boundingBox,
            frameWidth,
            frameHeight,
          );
      if (!mounted) return;
      setState(() {
        _lightingLow = lowLight;
        _faceCount = faces.length;
        _faceCentered = centered;
        final previousPose = _poseMachine.pose;
        if (centered && faces.length == 1) {
          _poseMachine.observe(faceCount: 1, yaw: faces.single.headEulerAngleY);
        }
        if (_poseMachine.pose != previousPose) _startPoseTimer();
        _error = null;
      });
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Face detection failed. Retry the camera check.');
      }
    } finally {
      _processingFrame = false;
    }
  }

  void _startPoseTimer() {
    _poseTimer?.cancel();
    if (_poseMachine.pose == FacePose.complete ||
        _poseMachine.pose == FacePose.failed) {
      return;
    }
    _poseTimer = Timer(FacePoseStateMachine.poseTimeout, () {
      if (!mounted) return;
      setState(() {
        _poseMachine.timeout();
        _error = "Unable to proceed. Face match couldn't be detected.";
      });
    });
  }

  InputImage? _inputImage(CameraImage image) {
    final camera = _camera;
    if (camera == null || image.planes.isEmpty) return null;
    final bytesBuilder = WriteBuffer();
    for (final plane in image.planes) {
      bytesBuilder.putUint8List(plane.bytes);
    }
    final bytes = bytesBuilder.done().buffer.asUint8List();
    final format =
        Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final rotationDegrees = _rotationDegrees(camera);
    final rotation = InputImageRotationValue.fromRawValue(rotationDegrees) ??
        InputImageRotation.rotation0deg;
    return InputImage.fromBytes(
      bytes: bytes,
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: rotation,
        format: format,
        bytesPerRow: image.planes.first.bytesPerRow,
      ),
    );
  }

  int _rotationDegrees(CameraController camera) {
    final rotationCompensation = switch (camera.value.deviceOrientation) {
      DeviceOrientation.portraitUp => 0,
      DeviceOrientation.landscapeLeft => 90,
      DeviceOrientation.portraitDown => 180,
      DeviceOrientation.landscapeRight => 270,
    };
    final sensorOrientation = camera.description.sensorOrientation;
    // Front camera frames rotate in the opposite direction from rear-camera
    // frames for ML Kit's image-coordinate system.
    return camera.description.lensDirection == CameraLensDirection.front
        ? (sensorOrientation + rotationCompensation) % 360
        : (sensorOrientation - rotationCompensation + 360) % 360;
  }

  bool _isFaceCentered(Rect box, int imageWidth, int imageHeight) {
    final x = box.center.dx / imageWidth;
    final y = box.center.dy / imageHeight;
    final width = box.width / imageWidth;
    return x >= FaceCaptureTuning.centerMinX &&
        x <= FaceCaptureTuning.centerMaxX &&
        y >= FaceCaptureTuning.centerMinY &&
        y <= FaceCaptureTuning.centerMaxY &&
        width >= FaceCaptureTuning.minimumFaceWidth;
  }

  double _estimateLuma(CameraImage image) {
    if (image.planes.isEmpty) return 255;
    final bytes = image.planes.first.bytes;
    if (bytes.isEmpty) return 255;
    // Sample at most about 1,000 values to keep per-frame work inexpensive.
    var total = 0;
    var count = 0;
    if (Platform.isIOS && image.format.group == ImageFormatGroup.bgra8888) {
      final pixelStride =
          ((bytes.length ~/ 4) ~/ 1000).clamp(1, bytes.length ~/ 4);
      for (var pixel = 0; pixel < bytes.length ~/ 4; pixel += pixelStride) {
        final offset = pixel * 4;
        final blue = bytes[offset].toDouble();
        final green = bytes[offset + 1].toDouble();
        final red = bytes[offset + 2].toDouble();
        total += (0.114 * blue + 0.587 * green + 0.299 * red).round();
        count++;
      }
    } else {
      // Android NV21 stores luminance in the first width*height bytes; the
      // following chroma bytes must not make a dark frame look well lit.
      final lumaLength = image.format.group == ImageFormatGroup.nv21
          ? (image.width * image.height).clamp(1, bytes.length)
          : bytes.length;
      final stride = (lumaLength ~/ 1000).clamp(1, lumaLength);
      for (var i = 0; i < lumaLength; i += stride) {
        total += bytes[i];
        count++;
      }
    }
    return total / count;
  }

  String get _guidance {
    if (_error != null) return _error!;
    if (_lightingLow) {
      return 'Lighting is too low. Face a bright, even light and avoid a bright window behind you.';
    }
    if (_faceCount == 0) return 'Center your face in the frame';
    if (_faceCount > 1) return 'Only one face can be in the frame';
    if (!_faceCentered) return 'Move your face into the center of the frame';
    return switch (_poseMachine.pose) {
      FacePose.front => 'Pose 3 of 3 · FRONT',
      FacePose.left => 'Pose 1 of 3 · LEFT',
      FacePose.right => 'Pose 2 of 3 · RIGHT',
      FacePose.complete => 'Face poses captured',
      FacePose.failed => "Unable to proceed. Face match couldn't be detected.",
    };
  }

  void _retryPoseSequence() {
    setState(() {
      _poseMachine.reset();
      _faceCount = 0;
      _faceCentered = false;
      _error = null;
    });
    _startPoseTimer();
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (!_canCapture || camera == null) return;
    XFile? photo;
    var retainedForReview = false;
    try {
      await camera.stopImageStream();
      photo = await camera.takePicture();
      final capturedFaces = await _faceService.detectFaces(
        InputImage.fromFilePath(photo.path),
      );
      if (!mounted) {
        await _deletePhoto(photo);
        return;
      }
      if (capturedFaces.length != 1) {
        await _deletePhoto(photo);
        setState(() {
          _faceCount = capturedFaces.length;
          _faceCentered = false;
        });
        await camera.startImageStream(_processFrame);
        return;
      }
      setState(() => _capturedImage = photo);
      retainedForReview = true;
    } catch (_) {
      if (mounted) {
        setState(
            () => _error = 'Could not capture the face. Please try again.');
      }
      final currentCamera = _camera;
      if (currentCamera != null &&
          currentCamera.value.isInitialized &&
          !currentCamera.value.isStreamingImages) {
        await currentCamera.startImageStream(_processFrame);
      }
    } finally {
      if (!retainedForReview && photo != null) await _deletePhoto(photo);
    }
  }

  Future<void> _retake() async {
    final photo = _capturedImage;
    setState(() {
      _capturedImage = null;
      _faceCount = 0;
      _faceCentered = false;
      _error = null;
      _poseMachine.reset();
    });
    _startPoseTimer();
    if (photo != null) await _deletePhoto(photo);
    final camera = _camera;
    if (camera != null && camera.value.isInitialized) {
      await camera.startImageStream(_processFrame);
    } else if (_permissionGranted) {
      await _startCamera();
    }
  }

  Future<void> _confirmCapture() async {
    final photo = _capturedImage;
    if (photo == null) return;
    try {
      // The approved FaceEmbedder remains a stub. An empty result is accepted
      // only as completion of the pose-capture demo, never as an identity match.
      await _frameProcessor.computeAndDelete(photo.path, _embedder);
      if (mounted) {
        Navigator.of(context).pop(const FaceCaptureResult(
          faceDetected: true,
          movementChallengePassed: true,
        ));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Face matching is unavailable in this demo build. Retry the capture.');
      }
    } finally {
      await _deletePhoto(photo);
      if (identical(_capturedImage, photo)) _capturedImage = null;
    }
  }

  Future<void> _deletePhoto(XFile photo) async {
    try {
      final file = File(photo.path);
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Best-effort cleanup; the camera writes captures to its temporary cache.
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poseTimer?.cancel();
    final camera = _camera;
    _camera = null;
    if (camera != null) unawaited(camera.dispose());
    final photo = _capturedImage;
    if (photo != null) unawaited(_deletePhoto(photo));
    unawaited(_faceService.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final camera = _camera;
    if (_poseMachine.pose == FacePose.failed) {
      return Scaffold(
        appBar: AppBar(title: const Text('Face capture failed')),
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.face_retouching_off, size: 56),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                    "Unable to proceed. Face match couldn't be detected.",
                    textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.lg),
                FilledButton.icon(
                    onPressed: _retryPoseSequence,
                    icon: const Icon(Icons.refresh),
                    label: const Text('Retry')),
              ]),
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Face capture')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Text(
              _capturedImage == null
                  ? 'Center your face in the frame'
                  : 'Review your capture',
              style: AppTypography.sectionTitle,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              _capturedImage == null
                  ? _guidance
                  : 'Movement check passed on this device. This does not confirm identity or guarantee liveness.',
              style: AppTypography.bodySmall,
              key: const ValueKey('face-guidance'),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_capturedImage == null && camera?.value.isInitialized == true)
              FacePoseCoach(pose: _poseMachine.pose),
            const SizedBox(height: AppSpacing.md),
            AspectRatio(
              aspectRatio: 0.78,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.large),
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    if (_capturedImage case final photo?)
                      Image.file(File(photo.path), fit: BoxFit.cover)
                    else if (camera?.value.isInitialized == true)
                      CameraPreview(camera!)
                    else
                      Container(
                        color: AppColors.surfaceMuted,
                        alignment: Alignment.center,
                        child: _initializing || _requestingPermission
                            ? const CircularProgressIndicator()
                            : const Icon(Icons.face_retouching_natural,
                                size: 52, color: AppColors.primary),
                      ),
                    if (_capturedImage == null &&
                        camera?.value.isInitialized == true)
                      const IgnorePointer(child: _FaceGuideOverlay()),
                  ],
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            if (_error != null &&
                (_error!.contains('system settings') ||
                    _error!.contains('Allow it')))
              OutlinedButton.icon(
                onPressed: _openSettings,
                icon: const Icon(Icons.settings_outlined),
                label: const Text('Open system settings'),
              )
            else if (camera == null && !_initializing && !_permissionGranted)
              FilledButton.icon(
                onPressed: _requestingPermission ? null : _requestCamera,
                icon: const Icon(Icons.camera_alt_outlined),
                label: Text(_requestingPermission
                    ? 'Requesting access…'
                    : 'Allow camera'),
              )
            else if (_error != null && camera == null)
              FilledButton.icon(
                onPressed: _permissionGranted ? _startCamera : _requestCamera,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              )
            else if (_capturedImage != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _retake,
                      child: const Text('Retake'),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: FilledButton(
                      onPressed: _confirmCapture,
                      child: const Text('Use capture'),
                    ),
                  ),
                ],
              )
            else
              FilledButton.icon(
                onPressed: _canCapture ? _capture : null,
                icon: const Icon(Icons.camera_alt_outlined),
                label: const Text('Capture face'),
              ),
            const SizedBox(height: AppSpacing.md),
            const Text(
              'Follow the LEFT, RIGHT, and FRONT poses in order. FaceEmbedder is a stub in this demo; no identity match is performed. Captured raw frames are deleted after embedding.',
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _FaceGuideOverlay extends StatelessWidget {
  const _FaceGuideOverlay();

  @override
  Widget build(BuildContext context) => Center(
        child: FractionallySizedBox(
          widthFactor: 0.68,
          heightFactor: 0.58,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.primary, width: 3),
              borderRadius: const BorderRadius.all(Radius.elliptical(120, 160)),
            ),
          ),
        ),
      );
}

class FaceCaptureTuning {
  const FaceCaptureTuning._();

  static const minimumLuma = 48.0;
  static const centerMinX = 0.22;
  static const centerMaxX = 0.78;
  static const centerMinY = 0.16;
  static const centerMaxY = 0.84;
  static const minimumFaceWidth = 0.08;
}

class FacePoseCoach extends StatelessWidget {
  const FacePoseCoach({required this.pose, super.key});

  final FacePose pose;

  @override
  Widget build(BuildContext context) {
    final (label, dx, icon) = switch (pose) {
      FacePose.front => ('Look straight at the camera', 0.0, Icons.face),
      FacePose.left => ('Slowly turn your face LEFT', -0.42, Icons.turn_left),
      FacePose.right => ('Slowly turn your face RIGHT', 0.42, Icons.turn_right),
      FacePose.complete => ('Pose sequence complete', 0.0, Icons.check_circle),
      FacePose.failed => ('Try the pose sequence again', 0.0, Icons.refresh),
    };

    return Semantics(
      liveRegion: true,
      label: 'Face pose instruction: $label',
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          borderRadius: BorderRadius.circular(AppRadius.card),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 72,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const SizedBox(
                    width: 180,
                    child: Divider(thickness: 2),
                  ),
                  AnimatedAlign(
                    duration: const Duration(milliseconds: 650),
                    curve: Curves.easeInOutCubic,
                    alignment: Alignment(dx, 0),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      child: Icon(icon,
                          key: ValueKey(pose),
                          size: 48,
                          color: AppColors.primary),
                    ),
                  ),
                ],
              ),
            ),
            Text(label, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xs),
            const Text(
              'Keep your phone still. Turn your head, not the camera.',
              textAlign: TextAlign.center,
              style: AppTypography.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
