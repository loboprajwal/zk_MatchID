import 'package:flutter/material.dart';
import '../core/blockchain_service.dart';
import '../core/native_bridge.dart';
import '../core/nonce_manager.dart';
import '../core/qr_codec.dart';
import '../models/proof_payload.dart';
import '../models/verification_policy.dart';
import '../widgets/qr_display.dart';
import '../widgets/qr_scanner_view.dart';
import '../widgets/verification_badge.dart';

class VerifierScreen extends StatefulWidget {
  const VerifierScreen({super.key});

  @override
  State<VerifierScreen> createState() => _VerifierScreenState();
}

class _VerifierScreenState extends State<VerifierScreen> {
  final NativeBridge _bridge = NativeBridge();
  final NonceManager _nonceManager = NonceManager();
  final BlockchainService _blockchain = BlockchainService();

  VerificationPolicy _selectedPolicy = kVerificationPolicies.first;
  String _currentSessionNonce = '';
  bool _isScanning = false;
  bool _isVerifying = false;
  bool? _verificationSuccess;
  String _resultTitle = '';
  String _resultMessage = '';
  Map<String, String>? _resultDetails;

  @override
  void initState() {
    super.initState();
    _refreshSessionNonce();
  }

  void _refreshSessionNonce() {
    setState(() {
      _currentSessionNonce = _nonceManager.generateNonce();
      _verificationSuccess = null;
      _resultTitle = '';
      _resultMessage = '';
      _resultDetails = null;
    });
  }

  /// Extracts the circuit predicate mode label from the public inputs, when
  /// the payload was produced by the generic multi-predicate engine.
  String? _predicateModeLabel(ProofPayload payload) {
    if (payload.publicInputs.length < 2) return null;
    // Public Groth16 outputs precede inputs: index 0 is nullifier, index 1 mode.
    final mode = int.tryParse(payload.publicInputs[1]);
    switch (mode) {
      case 1:
        return 'Mode 1 · Threshold / Range';
      case 2:
        return 'Mode 2 · Set Membership';
      case 3:
        return 'Mode 3 · Derived (Age)';
      default:
        return null;
    }
  }

  Future<void> _handleScannedQr(String rawData) async {
    setState(() {
      _isScanning = false;
      _isVerifying = true;
    });

    try {
      // 1. Base85 decompression
      final ProofPayload payload = QrCodec.decode(rawData);

      // 2. Anti-Replay Nonce Validation
      final isNonceValid =
          _nonceManager.validateAndConsumeNonce(payload.sessionNonce);

      if (!isNonceValid) {
        setState(() {
          _isVerifying = false;
          _verificationSuccess = false;
          _resultTitle = 'REPLAY ATTACK PREVENTED';
          _resultMessage =
              'This proof was generated for an expired or previously consumed session nonce.';
        });
        return;
      }

      // 3. Verification Policy Enforcement: the proof must attest exactly the
      //    predicate this verifier requires (no silent substitution).
      if (payload.predicateType != _selectedPolicy.id) {
        setState(() {
          _isVerifying = false;
          _verificationSuccess = false;
          _resultTitle = 'POLICY MISMATCH';
          _resultMessage =
              'Verifier requires the "${_selectedPolicy.label}" policy, but the presented '
              'proof attests ${describePredicateType(payload.predicateType)}. '
              'Select the matching policy or ask the prover for a compliant proof.';
        });
        return;
      }

      // 4. Blockchain Issuer Authorization Validation
      final isIssuerValid =
          await _blockchain.isIssuerAuthorized(payload.issuerReference);
      if (!isIssuerValid) {
        setState(() {
          _isVerifying = false;
          _verificationSuccess = false;
          _resultTitle = 'UNAUTHORIZED ISSUER';
          _resultMessage =
              'Issuer ${payload.issuerReference} is not authorized in the Blockchain Issuer Registry.';
        });
        return;
      }

      final issuerInfo = _blockchain.getIssuer(payload.issuerReference);

      // 5. Cryptographic Groth16 Evaluation (generic multi-predicate engine)
      final isProofValid = await _bridge.verifyPredicateProof(payload: payload);

      if (isProofValid) {
        final modeLabel = _predicateModeLabel(payload);
        setState(() {
          _isVerifying = false;
          _verificationSuccess = true;
          _resultTitle = _selectedPolicy.successTitle;
          _resultMessage =
              'Offline Groth16 proof satisfied the "${_selectedPolicy.label}" policy '
              'with ZERO PII disclosed.';
          _resultDetails = {
            'Predicate Claim': payload.predicateClaim,
            if (modeLabel != null) 'Circuit Predicate': modeLabel,
            'Protocol': 'Groth16 / BN254',
            'Credential Issuer': issuerInfo?.name ?? payload.issuerReference,
            'Blockchain Registry': 'Authorized & Active (On-Chain)',
            'Session Nonce': payload.sessionNonce,
            'Public Nullifier': payload.publicInputs.isNotEmpty
                ? payload.publicInputs.last
                : 'Poseidon Hash',
            'Timestamp': DateTime.fromMillisecondsSinceEpoch(payload.timestamp)
                .toIso8601String(),
          };
        });
      } else {
        setState(() {
          _isVerifying = false;
          _verificationSuccess = false;
          _resultTitle = 'VERIFICATION FAILED';
          _resultMessage =
              'The cryptographic proof points do not satisfy the BN254 pairing constraints.';
        });
      }
    } catch (e) {
      setState(() {
        _isVerifying = false;
        _verificationSuccess = false;
        _resultTitle = 'PAYLOAD ERROR';
        _resultMessage = 'Could not parse incoming QR payload: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanning) {
      return Scaffold(
        body: QrScannerView(
          onScanned: _handleScannedQr,
          onClose: () => setState(() => _isScanning = false),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Offline Verifier'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Generate Fresh Session Nonce',
            onPressed: _refreshSessionNonce,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_verificationSuccess != null) ...[
              VerificationBadge(
                isSuccess: _verificationSuccess!,
                title: _resultTitle,
                message: _resultMessage,
                details: _resultDetails,
                onReset: _refreshSessionNonce,
              ),
            ] else if (_isVerifying) ...[
              const Center(
                child: Padding(
                  padding: EdgeInsets.all(40),
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Evaluating Groth16 Proof on BN254 curve...'),
                    ],
                  ),
                ),
              ),
            ] else ...[
              DropdownButtonFormField<VerificationPolicy>(
                initialValue: _selectedPolicy,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Required Verification Policy',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.gavel),
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
                items: kVerificationPolicies
                    .map((p) => DropdownMenuItem(
                          value: p,
                          child: Text(
                            '${p.label} — ${p.scenario}',
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (policy) {
                  if (policy != null && policy.id != _selectedPolicy.id) {
                    _selectedPolicy = policy;
                    _refreshSessionNonce();
                  }
                },
              ),
              const SizedBox(height: 16),
              QrDisplay(
                data: _currentSessionNonce,
                title: 'Request ${_selectedPolicy.label} Verification',
                subtitle:
                    'Prover can scan this dynamic nonce QR to bind proof',
                size: 200,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => setState(() => _isScanning = true),
                icon: const Icon(Icons.camera_alt),
                label: const Text('Scan Prover QR Offline'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.teal,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
