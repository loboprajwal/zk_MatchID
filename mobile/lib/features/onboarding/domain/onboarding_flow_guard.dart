enum OnboardingStep {
  phone,
  face,
  bindingSuccess,
  walletSetup,
  backup,
  confirmation,
  complete
}

/// Transition gate used by the onboarding coordinator. No caller can advance
/// to a later screen without recording the prerequisite result first.
class OnboardingFlowGuard {
  OnboardingStep _step = OnboardingStep.phone;
  bool _phoneVerified = false;
  bool _facePoseSequencePassed = false;
  bool _walletSetupComplete = false;
  bool _backupDisplayed = false;

  OnboardingStep get step => _step;
  bool canOpen(OnboardingStep target) => switch (target) {
        OnboardingStep.phone => true,
        OnboardingStep.face => _phoneVerified,
        OnboardingStep.bindingSuccess =>
          _phoneVerified && _facePoseSequencePassed,
        OnboardingStep.walletSetup => _phoneVerified && _facePoseSequencePassed,
        OnboardingStep.backup => _walletSetupComplete,
        OnboardingStep.confirmation => _walletSetupComplete && _backupDisplayed,
        OnboardingStep.complete => _walletSetupComplete && _backupDisplayed,
      };

  bool markPhoneVerified() {
    if (_step != OnboardingStep.phone) return false;
    _phoneVerified = true;
    _step = OnboardingStep.face;
    return true;
  }

  bool markFacePoseSequencePassed() {
    if (_step != OnboardingStep.face || !_phoneVerified) return false;
    _facePoseSequencePassed = true;
    _step = OnboardingStep.bindingSuccess;
    return true;
  }

  bool continueToWalletSetup() {
    if (_step != OnboardingStep.bindingSuccess || !_canOpenSetup) return false;
    _step = OnboardingStep.walletSetup;
    return true;
  }

  bool get _canOpenSetup => _phoneVerified && _facePoseSequencePassed;

  bool markWalletSetupComplete() {
    if (_step != OnboardingStep.walletSetup) return false;
    _walletSetupComplete = true;
    _step = OnboardingStep.backup;
    return true;
  }

  bool markBackupDisplayed() {
    if (_step != OnboardingStep.backup || !_walletSetupComplete) return false;
    _backupDisplayed = true;
    _step = OnboardingStep.confirmation;
    return true;
  }

  bool markMnemonicConfirmed() {
    if (_step != OnboardingStep.confirmation || !_backupDisplayed) return false;
    _step = OnboardingStep.complete;
    return true;
  }
}
