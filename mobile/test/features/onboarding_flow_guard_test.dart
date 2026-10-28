import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/features/onboarding/domain/onboarding_flow_guard.dart';

void main() {
  test('screens 05-08 cannot be reached without their prior verified steps',
      () {
    final guard = OnboardingFlowGuard();
    expect(guard.canOpen(OnboardingStep.bindingSuccess), isFalse);
    expect(guard.canOpen(OnboardingStep.walletSetup), isFalse);
    expect(guard.canOpen(OnboardingStep.backup), isFalse);
    expect(guard.canOpen(OnboardingStep.confirmation), isFalse);
    expect(guard.markFacePoseSequencePassed(), isFalse);
    expect(guard.continueToWalletSetup(), isFalse);

    expect(guard.markPhoneVerified(), isTrue);
    expect(guard.canOpen(OnboardingStep.face), isTrue);
    expect(guard.canOpen(OnboardingStep.bindingSuccess), isFalse);
    expect(guard.markFacePoseSequencePassed(), isTrue);
    expect(guard.canOpen(OnboardingStep.bindingSuccess), isTrue);
    expect(guard.canOpen(OnboardingStep.walletSetup), isTrue);
    expect(guard.markWalletSetupComplete(), isFalse);

    expect(guard.continueToWalletSetup(), isTrue);
    expect(guard.markWalletSetupComplete(), isTrue);
    expect(guard.canOpen(OnboardingStep.backup), isTrue);
    expect(guard.canOpen(OnboardingStep.confirmation), isFalse);
    expect(guard.markBackupDisplayed(), isTrue);
    expect(guard.canOpen(OnboardingStep.confirmation), isTrue);
    expect(guard.markMnemonicConfirmed(), isTrue);
    expect(guard.step, OnboardingStep.complete);
  });

  test('cancelled face capture cannot advance to binding success', () {
    final guard = OnboardingFlowGuard();
    guard.markPhoneVerified();
    expect(guard.step, OnboardingStep.face);
    expect(guard.canOpen(OnboardingStep.bindingSuccess), isFalse);
    expect(guard.continueToWalletSetup(), isFalse);
  });
}
