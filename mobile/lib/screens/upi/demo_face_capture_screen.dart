import 'dart:async';
import 'dart:typed_data';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../demo/face_template.dart';

/// Result of the demo face capture (image + local template, never uploaded).
class DemoFaceCaptureResult {
  const DemoFaceCaptureResult({
    required this.imageFile,
    required this.template,
    required this.capturedAt,
    required this.faceConfirmedByMlKit,
  });

  final File imageFile;
  final String template;
  final DateTime capturedAt;
  final bool faceConfirmedByMlKit;
}

/// Front-camera face capture with oval guide and L→R→centre scan animation.
///
/// Uses ML Kit to prefer a single centered face before capture; if ML Kit is
/// unavailable the animation still completes and a manual capture is allowed.
class DemoFaceCaptureScreen extends StatefulWidget {
  const DemoFaceCaptureScreen({
    super.key,
    this.requireMlKitFace = true,
  });

  final bool requireMlKitFace;

  @override
  State<DemoFaceCaptureScreen> createState() => _DemoFaceCaptureScreenState();
}

class _DemoFaceCaptureScreenState extends State<DemoFaceCaptureScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  CameraController? _camera;
  FaceDetector? _detector;
  bool _permissionGranted = false;
  bool _initializing = false;
  bool _processing = false;
  bool _faceOk = false;
  bool _mlKitAvailable = true;
  String? _error;
  XFile? _preview;

  late final AnimationController _scanController;
  late final Animation<double> _scanAnim;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _scanController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    );
    _scanAnim = CurvedAnimation(parent: _scanController, curve: Curves.easeInOut);
    _scanController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        // Hold briefly at centre, then allow capture / auto-capture if face ok.
        if (_faceOk || !widget.requireMlKitFace || !_mlKitAvailable) {
          unawaited(_capture());
        } else {
          _scanController.reverse();
        }
      } else if (status == AnimationStatus.dismissed && mounted) {
        // Loop until capture succeeds.
        if (_preview == null) {
          _scanController.forward();
        }
      }
    });
    try {
      _detector = FaceDetector(
        options: FaceDetectorOptions(
          performanceMode: FaceDetectorMode.fast,
          enableLandmarks: true,
          minFaceSize: 0.15,
        ),
      );
    } catch (_) {
      _mlKitAvailable = false;
      _detector = null;
    }
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    await _requestPermissionAndStart();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused) {
      final cam = _camera;
      _camera = null;
      if (cam != null) unawaited(cam.dispose());
      _scanController.stop();
    } else if (state == AppLifecycleState.resumed &&
        _permissionGranted &&
        _preview == null) {
      unawaited(_startCamera());
    }
  }

  Future<void> _requestPermissionAndStart() async {
    setState(() {
      _initializing = true;
      _error = null;
    });
    try {
      var status = await Permission.camera.status;
      if (!status.isGranted) status = await Permission.camera.request();
      if (!mounted) return;
      if (!status.isGranted) {
        setState(() {
          _error = 'Camera permission is required for face capture.';
          _initializing = false;
        });
        return;
      }
      setState(() => _permissionGranted = true);
      await _startCamera();
    } catch (_) {
      if (mounted) {
        setState(() {
          _error = 'Could not request camera access.';
          _initializing = false;
        });
      }
    }
  }

  Future<void> _startCamera() async {
    if (_camera != null) return;
    CameraController? pending;
    try {
      final cameras = await availableCameras();
      final front = cameras.where(
        (c) => c.lensDirection == CameraLensDirection.front,
      );
      if (front.isEmpty) {
        setState(() {
          _error = 'No front camera on this device.';
          _initializing = false;
        });
        return;
      }
      final cam = CameraController(
        front.first,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: Platform.isAndroid
            ? ImageFormatGroup.nv21
            : ImageFormatGroup.bgra8888,
      );
      pending = cam;
      await cam.initialize();
      if (!mounted) {
        await cam.dispose();
        return;
      }
      _camera = cam;
      pending = null;
      await cam.startImageStream(_onFrame);
      _scanController.forward(from: 0);
      if (mounted) {
        setState(() => _initializing = false);
      }
    } catch (_) {
      if (pending != null) await pending.dispose();
      if (mounted) {
        setState(() {
          _error = 'Could not start the camera.';
          _initializing = false;
        });
      }
    }
  }

  Future<void> _onFrame(CameraImage image) async {
    if (_processing || _preview != null || _detector == null) return;
    _processing = true;
    try {
      final input = _toInputImage(image);
      if (input == null) return;
      final faces = await _detector!.processImage(input);
      final ok = faces.length == 1;
      if (mounted && ok != _faceOk) {
        setState(() => _faceOk = ok);
      }
    } catch (_) {
      // ML Kit may fail on some emulators — fall back to animation-only.
      if (_mlKitAvailable && mounted) {
        setState(() => _mlKitAvailable = false);
      }
    } finally {
      _processing = false;
    }
  }

  InputImage? _toInputImage(CameraImage image) {
    final cam = _camera;
    if (cam == null || image.planes.isEmpty) return null;
    final bytesBuilder = BytesBuilder(copy: false);
    for (final plane in image.planes) {
      bytesBuilder.add(plane.bytes);
    }
    final bytes = bytesBuilder.takeBytes();
    final format =
        Platform.isAndroid ? InputImageFormat.nv21 : InputImageFormat.bgra8888;
    final rotation = InputImageRotationValue.fromRawValue(
          cam.description.sensorOrientation,
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

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || _preview != null) return;
    if (widget.requireMlKitFace && _mlKitAvailable && !_faceOk) {
      // Wait for a face; restart animation.
      _scanController.forward(from: 0);
      return;
    }
    try {
      if (cam.value.isStreamingImages) {
        await cam.stopImageStream();
      }
      _scanController.stop();
      final photo = await cam.takePicture();
      if (!mounted) return;
      setState(() => _preview = photo);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Capture failed. Try again.');
      }
      if (cam.value.isInitialized && !cam.value.isStreamingImages) {
        await cam.startImageStream(_onFrame);
        _scanController.forward(from: 0);
      }
    }
  }

  Future<void> _confirm() async {
    final photo = _preview;
    if (photo == null) return;
    final file = File(photo.path);
    String metrics = '';
    if (_detector != null && _mlKitAvailable) {
      try {
        final faces =
            await _detector!.processImage(InputImage.fromFilePath(photo.path));
        if (faces.length == 1) {
          final f = faces.single;
          metrics =
              'box=${f.boundingBox.left.toStringAsFixed(1)},${f.boundingBox.top.toStringAsFixed(1)},'
              '${f.boundingBox.width.toStringAsFixed(1)},${f.boundingBox.height.toStringAsFixed(1)};'
              'yaw=${f.headEulerAngleY?.toStringAsFixed(1)}';
        }
      } catch (_) {
        // keep empty metrics
      }
    }
    final template =
        await FaceTemplateStore.templateFromFile(file, extraMetrics: metrics);
    if (!mounted) return;
    Navigator.of(context).pop(DemoFaceCaptureResult(
      imageFile: file,
      template: template,
      capturedAt: DateTime.now(),
      faceConfirmedByMlKit: _faceOk && _mlKitAvailable,
    ));
  }

  Future<void> _retake() async {
    final photo = _preview;
    setState(() {
      _preview = null;
      _faceOk = false;
      _error = null;
    });
    if (photo != null) {
      try {
        final f = File(photo.path);
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
    final cam = _camera;
    if (cam != null && cam.value.isInitialized) {
      if (!cam.value.isStreamingImages) {
        await cam.startImageStream(_onFrame);
      }
      _scanController.forward(from: 0);
    } else if (_permissionGranted) {
      await _startCamera();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scanController.dispose();
    final cam = _camera;
    _camera = null;
    if (cam != null) unawaited(cam.dispose());
    unawaited(_detector?.close() ?? Future<void>.value());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cam = _camera;
    return Scaffold(
      appBar: AppBar(title: const Text('Face verification (demo)')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                _preview == null
                    ? 'Center your face in the oval'
                    : 'Review capture',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                _preview == null
                    ? (_mlKitAvailable
                        ? (_faceOk
                            ? 'Face detected — scanning bars meet in the centre, then we capture.'
                            : 'Scanning bars slide from left & right. Keep one face centered.')
                        : 'Demo scan animation (ML Kit unavailable on this device). Tap Capture when ready.')
                    : 'Saved only on this device. Nothing is uploaded.',
                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
              ),
              const SizedBox(height: 12),
              Expanded(
                child: AspectRatio(
                  aspectRatio: 0.78,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_preview case final p?)
                          Image.file(File(p.path), fit: BoxFit.cover)
                        else if (cam?.value.isInitialized == true)
                          CameraPreview(cam!)
                        else
                          Container(
                            color: Colors.black12,
                            alignment: Alignment.center,
                            child: _initializing
                                ? const CircularProgressIndicator()
                                : const Icon(Icons.face, size: 56),
                          ),
                        if (_preview == null)
                          IgnorePointer(
                            child: CustomPaint(
                              painter: _OvalGuidePainter(
                                accent: Colors.indigo,
                              ),
                            ),
                          ),
                        if (_preview == null)
                          AnimatedBuilder(
                            animation: _scanAnim,
                            builder: (context, _) => CustomPaint(
                              painter: _ScanBarsPainter(
                                progress: _scanAnim.value,
                                color: Colors.indigoAccent,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
              const SizedBox(height: 12),
              if (!_permissionGranted && !_initializing)
                FilledButton.icon(
                  onPressed: _requestPermissionAndStart,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Allow camera'),
                )
              else if (_preview != null)
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _retake,
                        child: const Text('Retake'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _confirm,
                        child: const Text('Use face'),
                      ),
                    ),
                  ],
                )
              else
                FilledButton.icon(
                  onPressed: cam?.value.isInitialized == true ? _capture : null,
                  icon: const Icon(Icons.camera_alt_outlined),
                  label: const Text('Capture now'),
                ),
              const SizedBox(height: 8),
              Text(
                'Demo only · face matrix = local image hash'
                '${_mlKitAvailable ? ' + landmark metrics' : ''}'
                '. Never uploaded.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OvalGuidePainter extends CustomPainter {
  _OvalGuidePainter({required this.accent});
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final oval = Rect.fromCenter(
      center: Offset(size.width / 2, size.height * 0.48),
      width: size.width * 0.62,
      height: size.height * 0.52,
    );
    final dim = Paint()..color = Colors.black.withValues(alpha: 0.35);
    final path = Path()
      ..addRect(Offset.zero & size)
      ..addOval(oval)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, dim);
    canvas.drawOval(
      oval,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = accent,
    );
  }

  @override
  bool shouldRepaint(covariant _OvalGuidePainter oldDelegate) =>
      oldDelegate.accent != accent;
}

/// Brackets / bars that slide from the left and right edges toward the centre.
class _ScanBarsPainter extends CustomPainter {
  _ScanBarsPainter({required this.progress, required this.color});
  final double progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final midY = size.height * 0.48;
    final halfH = size.height * 0.18;
    final edgePad = size.width * 0.06;
    final centreX = size.width / 2;
    // progress 0 → bars at edges; 1 → bars meet at centre
    final leftX = edgePad + (centreX - edgePad - 12) * progress;
    final rightX = size.width - edgePad - (size.width - edgePad - centreX - 12) * progress;

    // Left bracket [
    canvas.drawLine(Offset(leftX, midY - halfH), Offset(leftX, midY + halfH), paint);
    canvas.drawLine(Offset(leftX, midY - halfH), Offset(leftX + 14, midY - halfH), paint);
    canvas.drawLine(Offset(leftX, midY + halfH), Offset(leftX + 14, midY + halfH), paint);

    // Right bracket ]
    canvas.drawLine(Offset(rightX, midY - halfH), Offset(rightX, midY + halfH), paint);
    canvas.drawLine(Offset(rightX - 14, midY - halfH), Offset(rightX, midY - halfH), paint);
    canvas.drawLine(Offset(rightX - 14, midY + halfH), Offset(rightX, midY + halfH), paint);

    // Horizontal scan line when near centre
    if (progress > 0.85) {
      final glow = Paint()
        ..color = color.withValues(alpha: 0.55)
        ..strokeWidth = 2;
      canvas.drawLine(
        Offset(size.width * 0.22, midY),
        Offset(size.width * 0.78, midY),
        glow,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _ScanBarsPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.color != color;
}
