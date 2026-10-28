import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

/// Camera scanner view with offline overlay and bounding target.
class QrScannerView extends StatefulWidget {
  final Function(String code) onScanned;
  final VoidCallback? onClose;

  const QrScannerView({
    super.key,
    required this.onScanned,
    this.onClose,
  });

  @override
  State<QrScannerView> createState() => _QrScannerViewState();
}

class _QrScannerViewState extends State<QrScannerView> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        MobileScanner(
          controller: _controller,
          onDetect: (capture) {
            if (_hasScanned) return;
            final List<Barcode> barcodes = capture.barcodes;
            for (final barcode in barcodes) {
              final rawValue = barcode.rawValue;
              if (rawValue != null && rawValue.isNotEmpty) {
                _hasScanned = true;
                widget.onScanned(rawValue);
                break;
              }
            }
          },
        ),
        // Scanner reticle overlay
        Center(
          child: Container(
            width: 260,
            height: 260,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.greenAccent, width: 3),
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        // Offline badge at top
        Positioned(
          top: 40,
          left: 20,
          right: 20,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.7),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.wifi_off, color: Colors.white, size: 16),
                    SizedBox(width: 6),
                    Text(
                      'OFFLINE MODE ACTIVE',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.onClose != null)
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white, size: 28),
                  onPressed: widget.onClose,
                ),
            ],
          ),
        ),
        // Bottom instruction
        Positioned(
          bottom: 40,
          left: 20,
          right: 20,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              'Align QR code within the frame to verify proof offline',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ),
      ],
    );
  }
}
