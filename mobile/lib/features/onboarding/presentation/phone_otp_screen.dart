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
  final TextEditingController _codeController = TextEditingController();
  Timer? _resendTimer;
  int _resendSeconds = 0;
  int _failedAttempts = 0;
  bool _codeSent = false;
  bool _busy = false;
  bool _verified = false;
  String? _error;

  String get _phone => _phoneController.text.trim();

  bool get _validPhone => RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(_phone);

  bool get _validCode => RegExp(r'^\d{6}$').hasMatch(_codeController.text);

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
        _codeController.clear();
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
        _codeController.text,
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
    _codeController.clear();
    _codeController.dispose();
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
                    Text(
                      _codeSent
                          ? 'Verify your phone number'
                          : 'Enter mobile number',
                      style: AppTypography.sectionTitle,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      _codeSent
                          ? 'Enter the six-digit code sent to $_phone.'
                          : 'Enter your phone number in international format, for example +919876543210.',
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
                            ? 'Use E.164 format, including country code.'
                            : null,
                      ),
                    ),
                    if (_codeSent) ...[
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        controller: _codeController,
                        enabled: !_busy && _failedAttempts < 5,
                        autofocus: true,
                        keyboardType: TextInputType.number,
                        textInputAction: TextInputAction.done,
                        onChanged: (_) => setState(() => _error = null),
                        autofillHints: const [AutofillHints.oneTimeCode],
                        maxLength: 6,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        decoration: const InputDecoration(
                          labelText: 'Six-digit code',
                          counterText: '',
                          hintText: '123456',
                        ),
                      ),
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
