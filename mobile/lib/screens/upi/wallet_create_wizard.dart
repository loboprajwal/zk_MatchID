import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../demo/country_codes.dart';
import '../../demo/demo_otp.dart';
import '../../demo/face_template.dart';
import '../../demo/wallet_store.dart';
import 'demo_face_capture_screen.dart';

/// Multi-step demo wallet creation: name → phone → OTP → face.
class WalletCreateWizard extends StatefulWidget {
  const WalletCreateWizard({super.key});

  @override
  State<WalletCreateWizard> createState() => _WalletCreateWizardState();
}

class _WalletCreateWizardState extends State<WalletCreateWizard> {
  final _pageController = PageController();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _otpControllers = List.generate(4, (_) => TextEditingController());
  final _otpFocus = List.generate(4, (_) => FocusNode());

  CountryDialCode _country = kDefaultDemoCountry;
  int _step = 0;
  String? _error;
  bool _busy = false;
  Timer? _resendTimer;
  int _resendSeconds = 0;
  DemoFaceCaptureResult? _face;

  static const _stepTitles = [
    'Name your wallet',
    'Demo phone number',
    'Demo OTP',
    'Face verification',
  ];

  @override
  void dispose() {
    _resendTimer?.cancel();
    _pageController.dispose();
    _nameController.dispose();
    _phoneController.dispose();
    for (final c in _otpControllers) {
      c.dispose();
    }
    for (final f in _otpFocus) {
      f.dispose();
    }
    super.dispose();
  }

  String get _otpCode => _otpControllers.map((c) => c.text).join();

  String get _e164 =>
      DemoPhoneValidation.toE164(_country, _phoneController.text);

  void _goTo(int step) {
    setState(() {
      _step = step;
      _error = null;
    });
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 280),
      curve: Curves.easeOut,
    );
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = DemoOtp.resendSeconds);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        t.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _nextFromName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Enter a wallet name.');
      return;
    }
    _goTo(1);
  }

  Future<void> _nextFromPhone() async {
    final err =
        DemoPhoneValidation.validateNational(_country, _phoneController.text);
    if (err != null) {
      setState(() => _error = err);
      return;
    }
    _startResendTimer();
    _goTo(2);
  }

  Future<void> _nextFromOtp() async {
    final formatErr = DemoOtp.validateInput(_otpCode);
    if (formatErr != null) {
      setState(() => _error = formatErr);
      return;
    }
    if (!DemoOtp.verify(_otpCode)) {
      setState(() => _error = 'Incorrect OTP. Demo OTP is ${DemoOtp.demoCode}.');
      return;
    }
    _goTo(3);
  }

  Future<void> _openFaceCapture() async {
    setState(() => _error = null);
    final result = await Navigator.of(context).push<DemoFaceCaptureResult>(
      MaterialPageRoute(builder: (_) => const DemoFaceCaptureScreen()),
    );
    if (!mounted) return;
    if (result != null) {
      setState(() => _face = result);
    }
  }

  Future<void> _finish() async {
    if (_face == null) {
      setState(() => _error = 'Capture your face to finish.');
      return;
    }
    setState(() => _busy = true);
    try {
      final name = _nameController.text.trim();
      // Create wallet first to get a stable id for the face filename.
      final wallet = await WalletStore.instance.createWallet(
        name,
        profile: WalletProfile(
          phoneE164: _e164,
          otpVerified: true,
        ),
      );
      final savedPath = await FaceTemplateStore.persistFaceImage(
        walletId: wallet.id,
        source: _face!.imageFile,
      );
      // Best-effort cleanup of the camera temp file.
      try {
        if (_face!.imageFile.path != savedPath &&
            await _face!.imageFile.exists()) {
          await _face!.imageFile.delete();
        }
      } catch (_) {}

      await WalletStore.instance.updateProfile(
        wallet.id,
        WalletProfile(
          phoneE164: _e164,
          otpVerified: true,
          faceImagePath: savedPath,
          faceTemplate: _face!.template,
          faceCapturedAt: _face!.capturedAt,
        ),
      );
      if (!mounted) return;
      Navigator.of(context).pop(wallet);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Could not save wallet: $e';
          _busy = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_stepTitles[_step]),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Row(
                children: List.generate(4, (i) {
                  final active = i <= _step;
                  return Expanded(
                    child: Container(
                      height: 4,
                      margin: EdgeInsets.only(right: i < 3 ? 6 : 0),
                      decoration: BoxDecoration(
                        color: active ? Colors.indigo : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  );
                }),
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.shade200),
              ),
              child: const Text(
                'DEMO ONLY — no real SMS is sent. Phone, OTP and face stay on this device.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _buildNameStep(),
                  _buildPhoneStep(),
                  _buildOtpStep(),
                  _buildFaceStep(),
                ],
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  if (_step > 0)
                    OutlinedButton(
                      onPressed: _busy ? null : () => _goTo(_step - 1),
                      child: const Text('Back'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: _busy
                        ? null
                        : () {
                            switch (_step) {
                              case 0:
                                _nextFromName();
                              case 1:
                                _nextFromPhone();
                              case 2:
                                _nextFromOtp();
                              case 3:
                                _finish();
                            }
                          },
                    child: _busy
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Text(_step == 3 ? 'Create wallet' : 'Continue'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _nameController,
          autofocus: true,
          textInputAction: TextInputAction.next,
          decoration: const InputDecoration(
            labelText: 'Wallet name',
            hintText: 'e.g. Travel wallet',
            border: OutlineInputBorder(),
          ),
          onChanged: (_) => setState(() => _error = null),
          onSubmitted: (_) => _nextFromName(),
        ),
      ],
    );
  }

  Widget _buildPhoneStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Enter a demo phone number with country code',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 12),
        InputDecorator(
          decoration: const InputDecoration(
            labelText: 'Country code',
            border: OutlineInputBorder(),
            helperText: 'Demo country picker',
          ),
          child: DropdownButtonHideUnderline(
            child: DropdownButton<CountryDialCode>(
              isExpanded: true,
              value: _country,
              items: kDemoCountryCodes
                  .map(
                    (c) => DropdownMenuItem(
                      value: c,
                      child: Text(c.label),
                    ),
                  )
                  .toList(),
              onChanged: (c) {
                if (c == null) return;
                setState(() {
                  _country = c;
                  _error = null;
                });
              },
            ),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _phoneController,
          keyboardType: TextInputType.phone,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(_country.maxNationalDigits),
          ],
          decoration: InputDecoration(
            labelText: 'Phone number (demo)',
            hintText: _country.iso == 'IN' ? '9876543210' : 'National number',
            prefixText: '${_country.dialCode} ',
            border: const OutlineInputBorder(),
            helperText: 'Stored locally as $_e164 preview when valid',
          ),
          onChanged: (_) => setState(() => _error = null),
        ),
      ],
    );
  }

  Widget _buildOtpStep() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Enter the 4-digit demo OTP sent to $_e164',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Text(
            'Demo OTP: 1234',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 16,
              letterSpacing: 1.2,
            ),
          ),
        ),
        const SizedBox(height: 20),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(4, (i) {
            return SizedBox(
              width: 56,
              child: TextField(
                controller: _otpControllers[i],
                focusNode: _otpFocus[i],
                textAlign: TextAlign.center,
                keyboardType: TextInputType.number,
                maxLength: 1,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(1),
                ],
                decoration: const InputDecoration(
                  counterText: '',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) {
                  setState(() => _error = null);
                  if (v.isNotEmpty && i < 3) {
                    _otpFocus[i + 1].requestFocus();
                  } else if (v.isEmpty && i > 0) {
                    _otpFocus[i - 1].requestFocus();
                  }
                },
              ),
            );
          }),
        ),
        const SizedBox(height: 16),
        TextButton(
          onPressed: _resendSeconds > 0
              ? null
              : () {
                  // Demo resend is a no-op (no SMS).
                  _startResendTimer();
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Demo resend — OTP is still 1234'),
                    ),
                  );
                },
          child: Text(
            _resendSeconds > 0
                ? 'Resend in 0:${_resendSeconds.toString().padLeft(2, '0')}'
                : 'Resend OTP (demo)',
          ),
        ),
      ],
    );
  }

  Widget _buildFaceStep() {
    final face = _face;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          'Capture a face matrix for this wallet',
          style: Theme.of(context).textTheme.titleSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Front camera · oval guide · bars slide from left & right to the centre, then capture. Template stays on-device.',
          style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
        ),
        const SizedBox(height: 16),
        if (face != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: AspectRatio(
              aspectRatio: 1,
              child: Image.file(face.imageFile, fit: BoxFit.cover),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Template: ${face.template.substring(0, 16)}…'
            '${face.faceConfirmedByMlKit ? ' · ML Kit OK' : ''}',
            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _busy ? null : _openFaceCapture,
            icon: const Icon(Icons.refresh),
            label: const Text('Re-capture'),
          ),
        ] else
          FilledButton.icon(
            onPressed: _busy ? null : _openFaceCapture,
            icon: const Icon(Icons.face_retouching_natural),
            label: const Text('Open face capture'),
          ),
      ],
    );
  }
}
