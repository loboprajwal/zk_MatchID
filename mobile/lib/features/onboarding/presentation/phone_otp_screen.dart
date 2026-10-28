import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/theme/app_theme.dart';
import '../data/otp_service.dart';

class PhoneOtpScreen extends StatefulWidget {
  const PhoneOtpScreen({
    super.key,
    required this.otpService,
    this.initialPhoneNumber,
    required this.onVerified,
  });

  final OtpService otpService;
  final String? initialPhoneNumber;
  final Future<void> Function(String phoneNumber) onVerified;

  @override
  State<PhoneOtpScreen> createState() => _PhoneOtpScreenState();
}

class _PhoneOtpScreenState extends State<PhoneOtpScreen> {
  late final TextEditingController _phoneController;
  final List<TextEditingController> _codeBoxes = List.generate(4, (_) => TextEditingController());
  final List<FocusNode> _codeFocus = List.generate(4, (_) => FocusNode());
  Timer? _resendTimer;
  int _resendSeconds = 0;
  int _failedAttempts = 0;
  bool _codeSent = false;
  bool _busy = false;
  bool _verified = false;
  String? _error;

  String get _phone => _phoneController.text.trim();

  bool get _validPhone => RegExp(r'^\+91[6-9]\d{9}$').hasMatch(_phone);

  String get _code => _codeBoxes.map((box) => box.text).join();
  bool get _validCode => RegExp(r'^\d{4}$').hasMatch(_code);

  @override
  void initState() {
    super.initState();
    _phoneController = TextEditingController(text: widget.initialPhoneNumber);
  }

  Future<void> _sendCode({bool resend = false}) async {
    if (_busy || !_validPhone || (resend && _resendSeconds > 0)) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await widget.otpService.sendSmsCode(_phone);
      if (!mounted) return;
      setState(() {
        _codeSent = true;
        _failedAttempts = 0;
        for (final box in _codeBoxes) { box.clear(); }
      });
      _startResendTimer();
    } on OtpServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not send a code. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _startResendTimer() {
    _resendTimer?.cancel();
    setState(() => _resendSeconds = 30);
    _resendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_resendSeconds <= 1) {
        timer.cancel();
        setState(() => _resendSeconds = 0);
      } else {
        setState(() => _resendSeconds--);
      }
    });
  }

  Future<void> _verifyCode() async {
    if (_busy || !_validPhone || !_validCode || _failedAttempts >= 5) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final verified = await widget.otpService.verifySmsCode(
        _phone,
        _code,
      );
      if (!mounted) return;
      if (!verified) {
        setState(() {
          _failedAttempts++;
          _error = _failedAttempts >= 5
              ? 'Too many incorrect codes. Request a new code to continue.'
              : 'That code is incorrect or expired. Check it and try again.';
        });
        return;
      }
      await widget.onVerified(_phone);
      if (!mounted) return;
      setState(() => _verified = true);
    } on OtpServiceException catch (error) {
      if (mounted) setState(() => _error = error.message);
    } catch (_) {
      if (mounted) {
        setState(() => _error = 'Could not verify this code. Please retry.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  void dispose() {
    _resendTimer?.cancel();
    _phoneController.dispose();
    for (final box in _codeBoxes) { box.clear(); box.dispose(); }
    for (final node in _codeFocus) { node.dispose(); }
    unawaited(widget.otpService.close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Phone verification')),
        body: SafeArea(
          child: _verified
              ? ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    const SizedBox(height: AppSpacing.xl),
                    const Icon(
                      Icons.check_circle_outline,
                      size: 64,
                      color: AppColors.primary,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    Text('Phone number verified',
                        textAlign: TextAlign.center,
                        style: AppTypography.sectionTitle),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      '${_maskPhone(_phone)} is linked to this wallet. The number is stored in secure device storage.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.xl),
                    FilledButton(
                      onPressed: () => Navigator.of(context).pop(_phone),
                      child: const Text('Continue'),
                    ),
                  ],
                )
              : ListView(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceMuted,
                        borderRadius: BorderRadius.circular(AppRadius.medium),
                      ),
                      child: const Text('Demo mode: OTP simulated'),
                    ),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      _codeSent
                          ? 'Verify your phone number'
                          : 'Enter mobile number',
                      style: AppTypography.sectionTitle,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _codeSent
                          ? 'Enter the 4-digit code sent to $_phone. Demo code: 1234.'
                          : 'Enter your 10-digit Indian mobile number with +91.',
                      style: AppTypography.bodySmall,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    TextField(
                      controller: _phoneController,
                      enabled: !_codeSent && !_busy,
                      keyboardType: TextInputType.phone,
                      textInputAction: TextInputAction.done,
                      onChanged: (_) => setState(() => _error = null),
                      autofillHints: const [AutofillHints.telephoneNumber],
                      inputFormatters: [
                        FilteringTextInputFormatter.allow(RegExp(r'[+\d]')),
                        LengthLimitingTextInputFormatter(16),
                      ],
                      decoration: InputDecoration(
                        labelText: 'Phone number',
                        hintText: '+919876543210',
                        errorText: _phone.isNotEmpty && !_validPhone
                            ? 'Enter a valid +91 mobile number.'
                            : null,
                      ),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: AppSpacing.md),
                      Row(children: List.generate(4, (index) => Expanded(
                        child: Padding(
                          padding: EdgeInsets.only(right: index == 3 ? 0 : 8),
                          child: TextField(
                            controller: _codeBoxes[index], focusNode: _codeFocus[index],
                            enabled: !_busy && _failedAttempts < 5,
                            autofocus: index == 0, textAlign: TextAlign.center,
                            keyboardType: TextInputType.number,
                            autofillHints: index == 0 ? const [AutofillHints.oneTimeCode] : null,
                            inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(1)],
                            onChanged: (value) {
                              setState(() => _error = null);
                              if (value.isNotEmpty && index < 3) _codeFocus[index + 1].requestFocus();
                              if (value.isEmpty && index > 0) _codeFocus[index - 1].requestFocus();
                            },
                            decoration: const InputDecoration(counterText: '', hintText: '•'),
                          ),
                        ),
                      ))),
                      const SizedBox(height: AppSpacing.sm),
                      TextButton(
                        onPressed: _busy || _resendSeconds > 0
                            ? null
                            : () => _sendCode(resend: true),
                        child: Text(_resendSeconds > 0
                            ? 'Resend code in 0:${_resendSeconds.toString().padLeft(2, '0')}'
                            : 'Resend code'),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.sm),
                      Semantics(
                        liveRegion: true,
                        child: Text(
                          _error!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error),
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton(
                      onPressed: _busy ||
                              (_codeSent
                                  ? !_validCode || _failedAttempts >= 5
                                  : !_validPhone)
                          ? null
                          : _codeSent
                              ? _verifyCode
                              : _sendCode,
                      child: _busy
                          ? const SizedBox.square(
                              dimension: 20,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(_codeSent ? 'Verify code' : 'Send OTP'),
                    ),
                  ],
                ),
        ),
      );
}

String _maskPhone(String phone) {
  if (phone.length < 4) return '••••';
  return '${phone.substring(0, phone.length - 2)}••${phone.substring(phone.length - 2)}';
}
