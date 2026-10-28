import 'package:flutter/material.dart';
import '../core/native_bridge.dart';
import '../core/qr_codec.dart';
import '../core/vault_service.dart';
import '../models/verifiable_credential.dart';
import '../widgets/qr_display.dart';
import '../widgets/qr_scanner_view.dart';

/// A preset real-world verification profile for the generic multi-predicate
/// engine. Each template binds a vault credential to a `generic_verifier.circom`
/// predicate mode; [policyId] matches the Verifier's `VerificationPolicy.id`.
class ProofTemplate {
  /// Stable predicate id shared with the Verifier's policy selector.
  final String policyId;

  /// Display name of the template.
  final String label;

  /// Real-world scenario this template targets.
  final String scenario;

  /// DID of the credential issuer this predicate is proven from.
  final String issuerId;

  /// Human readable issuer category shown in the UI.
  final String issuerLabel;

  /// Credential type expected inside the vault.
  final String credentialLabel;

  /// `generic_verifier.circom` predicate mode (1 = threshold, 2 = set, 3 = derived/age).
  final int predicateMode;

  /// `credentialSubject` attribute evaluated by the circuit.
  final String attributeKey;

  /// Mode 1: minimum acceptable value. Mode 3: minimum age.
  final int thresholdA;

  /// Mode 3: reference value (current year, injected at proof time). Unused otherwise.
  final int thresholdB;

  /// Mode 2: whitelisted institution / jurisdiction codes (5 elements).
  final List<int> allowedSet;

  /// Zero-knowledge claim transported with the proof payload.
  final String claim;

  const ProofTemplate({
    required this.policyId,
    required this.label,
    required this.scenario,
    required this.issuerId,
    required this.issuerLabel,
    required this.credentialLabel,
    required this.predicateMode,
    required this.attributeKey,
    required this.thresholdA,
    this.thresholdB = 0,
    this.allowedSet = const [0, 0, 0, 0, 0],
    required this.claim,
  });
}

/// Preset proof templates covering the four verification profiles.
const List<ProofTemplate> kProofTemplates = [
  ProofTemplate(
    policyId: 'age_18',
    label: 'Age >= 18',
    scenario: 'Nightlife, hospitality & age-restricted venues',
    issuerId: 'did:zkmatch:gov-uidai',
    issuerLabel: 'Government Identity (UIDAI / Passport)',
    credentialLabel: 'National Identity Credential',
    predicateMode: 3,
    attributeKey: 'birthYear',
    thresholdA: 18,
    claim: 'Age >= 18 verified with zero DOB disclosed',
  ),
  ProofTemplate(
    policyId: 'income_solvency',
    label: 'Income Solvency',
    scenario: 'Apartment rentals & loan pre-qualification',
    issuerId: 'did:zkmatch:bank-apex',
    issuerLabel: 'Financial Institution (Bank / Credit Bureau)',
    credentialLabel: 'Financial Solvency Credential',
    predicateMode: 1,
    attributeKey: 'monthlyIncome',
    thresholdA: 4000,
    claim:
        'Monthly income >= \$4,000/mo verified with zero bank details disclosed',
  ),
  ProofTemplate(
    policyId: 'student_status',
    label: 'Student Status',
    scenario: 'Student discounts, campus perks & software access',
    issuerId: 'did:zkmatch:university-pes',
    issuerLabel: 'University Academic Registry',
    credentialLabel: 'University Student Credential',
    predicateMode: 2,
    attributeKey: 'institutionId',
    thresholdA: 0,
    allowedSet: [1042, 2087, 3311, 4509, 5120],
    claim:
        'Active enrollment at an accredited institution verified with zero student ID disclosed',
  ),
  ProofTemplate(
    policyId: 'regional_residency',
    label: 'Regional Residency',
    scenario: 'Civic subsidies, regional voting & public transport',
    issuerId: 'did:zkmatch:municipal-bda',
    issuerLabel: 'Municipal / Regional Authority',
    credentialLabel: 'Civic Residency Credential',
    predicateMode: 2,
    attributeKey: 'jurisdictionCode',
    thresholdA: 0,
    allowedSet: [29, 7, 13, 22, 33],
    claim:
        'Eligible jurisdiction residency verified with zero address disclosed',
  ),
];

class ProverScreen extends StatefulWidget {
  const ProverScreen({super.key});

  @override
  State<ProverScreen> createState() => _ProverScreenState();
}

class _ProverScreenState extends State<ProverScreen> {
  final NativeBridge _bridge = NativeBridge();
  final VaultService _vaultService = VaultService();

  ProofTemplate _selectedTemplate = kProofTemplates.first;
  String _sessionNonce = '';
  final TextEditingController _nonceController = TextEditingController();

  bool _isProving = false;
  String? _encodedPayload;
  double? _executionTimeMs;
  String? _errorMessage;
  bool _isScanningNonce = false;

  @override
  void initState() {
    super.initState();
    _sessionNonce = 'req_${DateTime.now().millisecondsSinceEpoch}';
    _nonceController.text = _sessionNonce;
  }

  @override
  void dispose() {
    _nonceController.dispose();
    super.dispose();
  }

  /// Maps the selected template to the `credentialSubject` attribute value.
  int _readAttribute(VerifiableCredential credential, ProofTemplate template) {
    if (template.attributeKey == 'birthYear') {
      return credential.birthYear;
    }
    final raw = credential.credentialSubject[template.attributeKey];
    final value = raw is int ? raw : int.tryParse(raw?.toString() ?? '');
    if (value == null) {
      throw Exception(
          'Credential attribute "${template.attributeKey}" missing — the '
          '${template.credentialLabel} cannot satisfy the ${template.label} predicate.');
    }
    return value;
  }

  /// Converts the credential expiration date to Unix seconds (circuit units).
  int _expirySeconds(VerifiableCredential credential) {
    final parsed = DateTime.tryParse(credential.expirationDate);
    if (parsed == null) {
      return DateTime.now()
              .add(const Duration(days: 3650))
              .millisecondsSinceEpoch ~/
          1000;
    }
    return parsed.millisecondsSinceEpoch ~/ 1000;
  }

  Future<void> _generateProof() async {
    final template = _selectedTemplate;
    setState(() {
      _isProving = true;
      _errorMessage = null;
    });

    final stopwatch = Stopwatch()..start();
    try {
      // Ensure the default multi-sector credentials are seeded in the vault.
      await _vaultService.initializeDefaultIdentity();
      final credentials = await _vaultService.getCredentials();

      VerifiableCredential? credential;
      for (final vc in credentials) {
        if (vc.issuerId == template.issuerId) {
          credential = vc;
          break;
        }
      }
      if (credential == null) {
        throw Exception(
            'No ${template.credentialLabel} found in the vault for ${template.issuerId}. '
            'Import the credential before proving "${template.label}".');
      }

      final attributeValue = _readAttribute(credential, template);
      final credentialExpiry = _expirySeconds(credential);
      final userSecret = await _vaultService.getUserSecretKey();
      final nonce = _nonceController.text.trim().isEmpty
          ? _sessionNonce
          : _nonceController.text.trim();
      final currentTimestamp =
          DateTime.now().millisecondsSinceEpoch ~/ 1000;
      // Mode 3 (age derivation) uses the current year as the reference value.
      final thresholdB = template.predicateMode == 3
          ? DateTime.now().year
          : template.thresholdB;

      final payload = await _bridge.generatePredicateProof(
        predicateMode: template.predicateMode,
        attributeValue: attributeValue,
        userSecret: userSecret,
        credentialExpiry: credentialExpiry,
        thresholdA: template.thresholdA,
        thresholdB: thresholdB,
        allowedSet: template.allowedSet,
        currentTimestamp: currentTimestamp,
        sessionNonce: nonce,
        issuerReference: template.issuerId,
        predicateType: template.policyId,
        predicateClaim: template.claim,
      );

      stopwatch.stop();
      final base85String = QrCodec.encode(payload);

      setState(() {
        _encodedPayload = base85String;
        _executionTimeMs = stopwatch.elapsedMicroseconds / 1000.0;
      });
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      setState(() {
        _isProving = false;
      });
    }
  }

  String _describePredicate(ProofTemplate template) {
    switch (template.predicateMode) {
      case 1:
        return 'attributeValue >= ${template.thresholdA}';
      case 2:
        return 'attributeValue ∈ {${template.allowedSet.join(', ')}}';
      case 3:
        return 'currentYear - birthYear >= ${template.thresholdA}';
      default:
        return 'unsupported mode';
    }
  }

  String _modeLabel(ProofTemplate template) {
    switch (template.predicateMode) {
      case 1:
        return 'Mode 1 · Threshold / Range';
      case 2:
        return 'Mode 2 · Set Membership';
      case 3:
        return 'Mode 3 · Derived (Age)';
      default:
        return 'Mode ${template.predicateMode}';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isScanningNonce) {
      return Scaffold(
        body: QrScannerView(
          onScanned: (scannedNonce) {
            setState(() {
              _nonceController.text = scannedNonce;
              _sessionNonce = scannedNonce;
              _isScanningNonce = false;
            });
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Nonce acquired from Verifier!')),
            );
          },
          onClose: () => setState(() => _isScanningNonce = false),
        ),
      );
    }

    final template = _selectedTemplate;

    return Scaffold(
      appBar: AppBar(
        title: const Text('ZK Prover'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'PROOF TEMPLATE',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 6),
                    DropdownButtonFormField<ProofTemplate>(
                      initialValue: _selectedTemplate,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                            horizontal: 12, vertical: 12),
                      ),
                      items: kProofTemplates
                          .map((t) => DropdownMenuItem(
                                value: t,
                                child: Text(
                                  '${t.label} — ${t.scenario}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            _selectedTemplate = val;
                            _encodedPayload = null;
                            _errorMessage = null;
                          });
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            template.label,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo,
                            ),
                          ),
                        ),
                        Chip(
                          label: Text(_modeLabel(template)),
                          backgroundColor: Colors.indigo.shade50,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Predicate: ${_describePredicate(template)}',
                            style: const TextStyle(
                                fontSize: 12, fontFamily: 'monospace'),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Credential source: ${template.credentialLabel} (${template.issuerId})',
                            style: TextStyle(
                                fontSize: 11, color: Colors.grey.shade700),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Proves "${template.claim}".',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _nonceController,
              decoration: InputDecoration(
                labelText: 'Session Nonce (Anti-Replay)',
                hintText: 'Scan verifier nonce or generate one',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.qr_code_scanner),
                  tooltip: 'Scan Verifier Nonce QR',
                  onPressed: () => setState(() => _isScanningNonce = true),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _isProving ? null : _generateProof,
              icon: _isProving
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          color: Colors.white, strokeWidth: 2),
                    )
                  : const Icon(Icons.flash_on),
              label: Text(_isProving
                  ? 'Generating Witness & Proof...'
                  : 'Generate Zero-Knowledge Proof'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.indigo,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
            if (_errorMessage != null) ...[
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Text(
                  _errorMessage!,
                  style: TextStyle(color: Colors.red.shade900),
                ),
              ),
            ],
            if (_encodedPayload != null) ...[
              const SizedBox(height: 24),
              if (_executionTimeMs != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Center(
                    child: Chip(
                      avatar: const Icon(Icons.speed, size: 16),
                      label: Text(
                        'Proving Time: ${_executionTimeMs!.toStringAsFixed(1)} ms (< 2.0s target)',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      backgroundColor: Colors.green.shade50,
                    ),
                  ),
                ),
              QrDisplay(
                data: _encodedPayload!,
                title: 'zk-MatchID ${template.label} Proof',
                subtitle: 'Present this QR to Verifier offline',
              ),
            ],
          ],
        ),
      ),
    );
  }
}
