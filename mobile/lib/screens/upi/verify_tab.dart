import 'package:flutter/material.dart';

import '../../demo/demo_session.dart';
import '../../demo/demo_verifier_service.dart';
import '../../widgets/qr_scanner_view.dart';
import '../../widgets/verification_badge.dart';

class VerifyTab extends StatefulWidget {
  const VerifyTab({super.key});

  @override
  State<VerifyTab> createState() => _VerifyTabState();
}

class _VerifyTabState extends State<VerifyTab> {
  final _verifier = DemoVerifierService.instance;
  bool _scanning = false;
  VerifyResult? _result;
  bool _busy = false;

  Future<void> _runVerify(String encoded) async {
    setState(() {
      _busy = true;
      _scanning = false;
      _result = null;
    });
    final result = await _verifier.verifyEncodedQr(encoded);
    if (!mounted) return;
    setState(() {
      _result = result;
      _busy = false;
    });
  }

  Future<void> _useLastQr() async {
    final encoded = DemoSession.lastEncodedQr;
    if (encoded == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No QR generated yet — open Prove first')),
      );
      return;
    }
    await _runVerify(encoded);
  }

  Future<void> _pasteDialog() async {
    final controller = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Paste QR payload'),
        content: TextField(
          controller: controller,
          maxLines: 6,
          decoration: const InputDecoration(
            hintText: 'Base85-encoded proof payload',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Verify'),
          ),
        ],
      ),
    );
    if (text == null || text.isEmpty) return;
    await _runVerify(text);
  }

  @override
  Widget build(BuildContext context) {
    if (_scanning) {
      return Scaffold(
        body: QrScannerView(
          onScanned: _runVerify,
          onClose: () => setState(() => _scanning = false),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Verify (scan QR)')),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : _result != null
              ? ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    VerificationBadge(
                      isSuccess: _result!.pass,
                      title: _result!.title,
                      message: _result!.reason,
                      details: _result!.details,
                      onReset: () => setState(() => _result = null),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.indigo.shade700, Colors.teal.shade600],
                        ),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Column(
                        children: [
                          Icon(Icons.document_scanner, color: Colors.white, size: 48),
                          SizedBox(height: 12),
                          Text(
                            'Verifier mode',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'Scan a holder QR — like collecting a UPI payment. '
                            'Checks expiry, nonce (single-use), issuer, and Groth16 catalog / signed demo.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton.icon(
                      onPressed: () => setState(() => _scanning = true),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const Text('Scan QR with camera'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(52),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: _useLastQr,
                      icon: const Icon(Icons.phonelink_ring),
                      label: const Text('Use last generated QR (single-device demo)'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton.icon(
                      onPressed: _pasteDialog,
                      icon: const Icon(Icons.paste),
                      label: const Text('Paste payload'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(48),
                      ),
                    ),
                    if (DemoSession.lastEncodedQr != null) ...[
                      const SizedBox(height: 16),
                      Text(
                        'Last QR: ${DemoSession.lastWalletName ?? "?"} · '
                        '${DemoSession.lastPredicateLabel ?? "?"}',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
                      ),
                    ],
                  ],
                ),
    );
  }
}
