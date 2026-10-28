import 'package:flutter/widgets.dart';
import 'data/otp_service.dart';

/// Injection seams for deterministic widget tests and future service adapters.
class OnboardingDependencies {
  const OnboardingDependencies({
    this.otpServiceFactory,
    this.faceCaptureScreenBuilder,
    this.walletSetupScreenBuilder,
  });

  final OtpService Function()? otpServiceFactory;
  final Widget Function()? faceCaptureScreenBuilder;
  final Widget Function()? walletSetupScreenBuilder;
}
