import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../core/theme/app_theme.dart';

class FaceCaptureResult {
  const FaceCaptureResult({
    required this.faceDetected,
    required this.movementChallengePassed,
  });

  final bool faceDetected;
  final bool movementChallengePassed;
}

enum _FaceChallengeStep { center, turnSide, turnOtherSide, blink, complete }

abstract interface class FaceVerificationService {
  Future<List<Face>> detectFaces(InputImage image);

  Future<void> close();
}

class MlKitFaceVerificationService implements FaceVerificationService {
  MlKitFaceVerificationService()
      : _detector = FaceDetector(
          options: FaceDetectorOptions(
            performanceMode: FaceDetectorMode.fast,
            enableLandmarks: true,
            enableClassification: true,
            minFaceSize: 0.12,
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
  MockFaceVerificationService(this.resultForImage);

  final Future<List<Face>> Function(InputImage image) resultForImage;

  @override
  Future<List<Face>> detectFaces(InputImage image) => resultForImage(image);

  @override
  Future<void> close() async {}
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
  _FaceChallengeStep _challengeStep = _FaceChallengeStep.center;
  int? _firstTurnSign;
  bool _eyesWereOpen = false;
  bool _eyesClosedAfterOpen = false;
  int _faceCount = 0;
  String? _error;

  bool get _canCapture =>
      _camera?.value.isInitialized == true &&
      _faceCount == 1 &&
      _faceCentered &&
      _challengeStep == _FaceChallengeStep.complete &&
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
      final faces = await _faceService.detectFaces(inputImage);
      final centered = faces.length == 1 &&
          _isFaceCentered(
            faces.single.boundingBox,
            image.width,
            image.height,
          );
      if (!mounted) return;
      setState(() {
        _faceCount = faces.length;
        _faceCentered = centered;
        _advanceChallenge(faces.length == 1 ? faces.single : null, centered);
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

  void _advanceChallenge(Face? face, bool centered) {
    if (face == null || !centered) {
      _challengeStep = _FaceChallengeStep.center;
      _firstTurnSign = null;
      _eyesWereOpen = false;
      _eyesClosedAfterOpen = false;
      return;
    }
    switch (_challengeStep) {
      case _FaceChallengeStep.center:
        _challengeStep = _FaceChallengeStep.turnSide;
        break;
      case _FaceChallengeStep.turnSide:
        final yaw = face.headEulerAngleY ?? 0;
        if (yaw.abs() >= 15) {
          _firstTurnSign = yaw.isNegative ? -1 : 1;
          _challengeStep = _FaceChallengeStep.turnOtherSide;
        }
        break;
      case _FaceChallengeStep.turnOtherSide:
        final yaw = face.headEulerAngleY ?? 0;
        if (yaw.abs() >= 15 && yaw.sign != _firstTurnSign) {
          _challengeStep = _FaceChallengeStep.blink;
        }
        break;
      case _FaceChallengeStep.blink:
        final left = face.leftEyeOpenProbability;
        final right = face.rightEyeOpenProbability;
        if (left == null || right == null) break;
        if (left > 0.7 && right > 0.7) _eyesWereOpen = true;
        if (_eyesWereOpen && left < 0.25 && right < 0.25) {
          _eyesClosedAfterOpen = true;
        }
        if (_eyesClosedAfterOpen && left > 0.65 && right > 0.65) {
          _challengeStep = _FaceChallengeStep.complete;
        }
        break;
      case _FaceChallengeStep.complete:
        break;
    }
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
    final rotation = InputImageRotationValue.fromRawValue(
          camera.description.sensorOrientation,
        ) ??
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

  bool _isFaceCentered(Rect box, int imageWidth, int imageHeight) {
    final x = box.center.dx / imageWidth;
    final y = box.center.dy / imageHeight;
    final width = box.width / imageWidth;
    return x >= 0.32 && x <= 0.68 && y >= 0.25 && y <= 0.75 && width >= 0.14;
  }

  String get _guidance {
    if (_error != null) return _error!;
    if (_faceCount == 0) return 'Center your face in the frame';
    if (_faceCount > 1) return 'Only one face can be in the frame';
    if (!_faceCentered) return 'Move your face into the center of the frame';
    return switch (_challengeStep) {
      _FaceChallengeStep.center => 'Center your face in the frame',
      _FaceChallengeStep.turnSide =>
        'Turn your head toward one side of the frame',
      _FaceChallengeStep.turnOtherSide => 'Now turn toward the other side',
      _FaceChallengeStep.blink => 'Look at the camera and blink once',
      _FaceChallengeStep.complete => 'Check complete · good lighting helps',
    };
  }

  Future<void> _capture() async {
    final camera = _camera;
    if (!_canCapture || camera == null) return;
    try {
      await camera.stopImageStream();
      final photo = await camera.takePicture();
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
    }
  }

  Future<void> _retake() async {
    final photo = _capturedImage;
    setState(() {
      _capturedImage = null;
      _faceCount = 0;
      _faceCentered = false;
      _error = null;
    });
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
    await _deletePhoto(photo);
    if (mounted) {
      Navigator.of(context).pop(const FaceCaptureResult(
        faceDetected: true,
        movementChallengePassed: true,
      ));
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
              'Use even lighting and remove anything covering your face. The check asks you to turn toward both sides of the frame and blink. It is not a face identity match and cannot prevent every presentation attack. Images are deleted when you leave.',
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
