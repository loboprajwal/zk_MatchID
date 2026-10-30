import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';
import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';

import 'core/theme/app_theme.dart';
import 'data/vault_backup_service.dart';
import 'data/vault_repository.dart';
import 'data/secure_key_value_store.dart';
import 'features/onboarding/presentation/face_capture_screen.dart';
import 'features/onboarding/data/otp_service.dart';
import 'features/onboarding/presentation/phone_otp_screen.dart';
import 'features/onboarding/domain/mnemonic_backup.dart';
import 'features/onboarding/presentation/mnemonic_backup_flow.dart';
import 'features/onboarding/domain/onboarding_flow_guard.dart';
import 'features/onboarding/presentation/binding_success_screen.dart';
import 'features/onboarding/presentation/wallet_setup_screen.dart';
import 'features/onboarding/onboarding_dependencies.dart';
import 'features/verification/credential_verification_service.dart';
import 'features/verification/credential_wallet_matcher.dart';
import 'features/verification/document_provider.dart';

void main() => runApp(const MatchIdApp());

const ink = AppColors.text;
const teal = AppColors.primary;
const canvas = AppColors.background;
const maxVaultJsonBytes = 200 * 1024 * 1024;

int _utf8ByteLength(
  String value, {
  int limit = 100 * 1024 * 1024,
}) {
  var total = 0;
  for (final rune in value.runes) {
    total += rune <= 0x7f
        ? 1
        : rune <= 0x7ff
            ? 2
            : rune <= 0xffff
                ? 3
                : 4;
    if (total > limit) return total;
  }
  return total;
}

String _errorText(Object error) =>
    error is FormatException ? error.message : error.toString();

String _maskPhone(String phone) {
  if (phone.length < 4) return '••••';
  return '${phone.substring(0, phone.length - 2)}••${phone.substring(phone.length - 2)}';
}

String _credentialTitle(Map<String, dynamic> data) {
  final types = data['type'];
  if (types is List) {
    final label =
        types.where((value) => value != 'VerifiableCredential').join(' · ');
    if (label.isNotEmpty) return label;
  }
  if (types is String && types.trim().isNotEmpty) return types;
  for (final key in const ['name', 'documentType', 'docType']) {
    final label = data[key];
    if (label is String && label.trim().isNotEmpty) return label;
  }
  return 'Identity credential';
}

class MatchIdApp extends StatelessWidget {
  const MatchIdApp(
      {super.key, this.vaultRepository, this.onboardingDependencies});

  final VaultRepository? vaultRepository;
  final OnboardingDependencies? onboardingDependencies;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MatchID',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: MatchHome(
            vaultRepository: vaultRepository,
            onboardingDependencies: onboardingDependencies),
      );
}

class MatchHome extends StatefulWidget {
  const MatchHome(
      {super.key, this.vaultRepository, this.onboardingDependencies});

  final VaultRepository? vaultRepository;
  final OnboardingDependencies? onboardingDependencies;

  @override
  State<MatchHome> createState() => _MatchHomeState();
}

class _MatchHomeState extends State<MatchHome> with WidgetsBindingObserver {
  late final VaultRepository vault;
  int tab = 0;
  List<Map<String, dynamic>> credentials = [];
  List<Map<String, dynamic>> activity = [];
  bool walletInitialized = false;
  bool walletCreated = false;
  bool unlocked = false;
  bool backupSkipped = false;
  bool backupCompleted = false;
  String walletName = 'My wallet';
  String? verifiedPhone;
  Timer? vaultLockTimer;

  @override
  void initState() {
    super.initState();
    vault = widget.vaultRepository ?? VaultStore();
    WidgetsBinding.instance.addObserver(this);
    _initializeWallet();
  }

  @override
  void dispose() {
    vaultLockTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.detached) {
      _lockVault();
    }
  }

  void _lockVault() {
    if (!mounted) return;
    vaultLockTimer?.cancel();
    setState(() {
      unlocked = false;
      credentials = [];
    });
  }

  void _refreshVaultLock() {
    if (!unlocked) return;
    vaultLockTimer?.cancel();
    vaultLockTimer = Timer(const Duration(minutes: 5), _lockVault);
  }

  Future<void> _initializeWallet() async {
    try {
      final config = await vault.readWalletConfig();
      final savedPhone = await vault.readVerifiedPhone();
      final storedCredentials = await vault.read();
      final events = await vault.readActivity();
      final wasBackupSkipped = await vault.isBackupSkipped();
      final wasBackupCompleted = await vault.isBackupCompleted();
      if (!mounted) return;
      setState(() {
        walletCreated = config != null || storedCredentials.isNotEmpty;
        walletName = config?['name'] as String? ?? 'My wallet';
        verifiedPhone = savedPhone;
        activity = events;
        backupSkipped = wasBackupSkipped;
        backupCompleted = wasBackupCompleted;
        walletInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => walletInitialized = true);
      _snack('Could not open local wallet: ${_errorText(e)}');
    }
  }

  Future<void> _createLocalWallet() async {
    if (walletCreated && !unlocked) {
      await _unlock();
      if (!mounted || !unlocked) return;
    }
    final guard = OnboardingFlowGuard();
    final phone = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PhoneOtpScreen(
          otpService:
              widget.onboardingDependencies?.otpServiceFactory?.call() ??
                  MockOtpService(),
          onVerified: (phoneNumber) async {
            await vault.saveVerifiedPhone(phoneNumber);
            if (mounted) setState(() => verifiedPhone = phoneNumber);
          },
        ),
      ),
    );
    if (!mounted || phone == null || !guard.markPhoneVerified()) {
      return;
    }

    final face = await Navigator.of(context).push<FaceCaptureResult>(
      MaterialPageRoute<FaceCaptureResult>(
        builder: (_) =>
            widget.onboardingDependencies?.faceCaptureScreenBuilder?.call() ??
            const FaceCaptureScreen(),
      ),
    );
    if (!mounted ||
        face?.faceDetected != true ||
        face?.movementChallengePassed != true ||
        !guard.markFacePoseSequencePassed()) {
      return;
    }

    final success = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => const BindingSuccessScreen(phoneStoredEncrypted: true),
      ),
    );
    if (!mounted || success != true || !guard.continueToWalletSetup()) {
      return;
    }

    final setup = await Navigator.of(context).push<WalletSetupResult>(
      MaterialPageRoute<WalletSetupResult>(
        builder: (_) =>
            widget.onboardingDependencies?.walletSetupScreenBuilder?.call() ??
            const WalletSetupScreen(),
      ),
    );
    if (!mounted || setup == null || !guard.markWalletSetupComplete()) {
      return;
    }

    final phrase = MnemonicBackup.generate();
    if (!guard.canOpen(OnboardingStep.backup)) {
      return;
    }
    // MnemonicBackupFlow shows the backup acknowledgement and two-word check
    // in sequence, under FLAG_SECURE on Android.
    final backupConfirmed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
          builder: (_) => MnemonicBackupFlow(phrase: phrase)),
    );
    if (!mounted ||
        backupConfirmed != true ||
        !guard.markBackupDisplayed() ||
        !guard.markMnemonicConfirmed()) {
      return;
    }

    try {
      await vault.createWallet(
        setup.name,
        mnemonicDerivedKey:
            base64UrlEncode(MnemonicBackup.deriveWalletKey(phrase)),
        deviceLockEnabled: setup.deviceLockEnabled,
      );
      await vault.addActivity('Wallet created', 'Local wallet · ${setup.name}');
      final events = await vault.readActivity();
      if (!mounted) {
        return;
      }
      setState(() {
        walletName = setup.name;
        walletCreated = true;
        unlocked = !setup.deviceLockEnabled;
        activity = events;
        backupSkipped = false;
        backupCompleted = false;
      });
      if (setup.deviceLockEnabled) _refreshVaultLock();
      await _showBackupPhase();
    } catch (e) {
      if (mounted) _snack('Could not create wallet: ${_errorText(e)}');
    }
  }

  Future<void> _switchWallet() async {
    if (!unlocked) {
      _snack('Unlock your wallet before switching wallets.');
      return;
    }
    final wallets = await vault.readWallets();
    if (wallets.length < 2 || !mounted) return;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const ListTile(title: Text('Switch wallet')),
          ...wallets.map((wallet) => ListTile(
                leading: const Icon(Icons.account_balance_wallet_outlined),
                title: Text(wallet['name']?.toString() ?? 'Wallet'),
                subtitle: Text(wallet['nameMasked']?.toString() ?? ''),
                onTap: () => Navigator.pop(sheetContext, wallet['id'] as String),
              )),
        ]),
      ),
    );
    if (selected == null || !mounted) return;
    await vault.selectWallet(selected);
    final config = await vault.readWalletConfig();
    final data = await vault.read();
    final events = await vault.readActivity();
    if (!mounted) return;
    setState(() {
      walletName = config?['name'] as String? ?? 'My wallet';
      credentials = data;
      activity = events;
      backupSkipped = false;
      backupCompleted = false;
      tab = 0;
    });
  }

  Future<void> _showRestoreInfo() async {
    final method = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore wallet'),
        content: const Text(
            'Restore your wallet key with its recovery phrase, or choose the advanced encrypted file backup.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'mnemonic'),
              child: const Text('Recovery phrase')),
          FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'file'),
              child: const Text('Advanced: file backup')),
        ],
      ),
    );
    if (!mounted) return;
    if (method == 'mnemonic') await _restoreFromMnemonic();
    if (method == 'file') await _restoreFromBackup();
  }

  Future<void> _restoreFromMnemonic() async {
    final phrase = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(builder: (_) => const MnemonicRestoreScreen()),
    );
    if (!mounted || phrase == null) return;
    try {
      final key = base64UrlEncode(MnemonicBackup.deriveWalletKey(phrase));
      final existingConfig = await vault.readWalletConfig();
      final existingCredentials = await vault.read();
      if (existingConfig != null || existingCredentials.isNotEmpty) {
        if (existingConfig?['mnemonicDerivedKey'] != key) {
          _snack(
              'A different wallet is already stored on this device. Nothing was replaced.');
          return;
        }
        walletName = existingConfig?['name'] as String? ?? 'My wallet';
      } else {
        final verifiedPhoneNumber = await _verifyIdentityForRestore();
        if (!mounted || verifiedPhoneNumber == null) return;
        await vault.createWallet('Restored wallet',
            mnemonicDerivedKey: key, deviceLockEnabled: true);
        await vault.setBackupCompleted(true);
        await vault.addActivity(
            'Wallet restored', 'Recovery phrase accepted on this device');
        walletName = 'Restored wallet';
      }
      final config = await vault.readWalletConfig();
      final data = await vault.read();
      final events = await vault.readActivity();
      if (!mounted) return;
      setState(() {
        walletCreated = true;
        walletName = config?['name'] as String? ?? walletName;
        credentials = data;
        activity = events;
        unlocked = config?['deviceLockEnabled'] == false;
        backupCompleted = true;
        backupSkipped = false;
        tab = 0;
      });
      if (unlocked) _refreshVaultLock();
      _snack(
          'Wallet key restored. Credentials that were stored only on another device are not included in a recovery phrase.');
    } on FormatException catch (error) {
      if (mounted) _snack(error.message);
    } catch (error) {
      if (mounted) {
        _snack('Could not restore the recovery phrase: ${_errorText(error)}');
      }
    }
  }

  Future<String?> _verifyIdentityForRestore() async {
    final phone = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PhoneOtpScreen(
          otpService: widget.onboardingDependencies?.otpServiceFactory?.call() ?? MockOtpService(),
          onVerified: (phoneNumber) async {
            await vault.saveVerifiedPhone(phoneNumber);
            if (mounted) setState(() => verifiedPhone = phoneNumber);
          },
        ),
      ),
    );
    if (!mounted || phone == null) return null;
    final face = await Navigator.of(context).push<FaceCaptureResult>(
      MaterialPageRoute<FaceCaptureResult>(
        builder: (_) => widget.onboardingDependencies?.faceCaptureScreenBuilder?.call() ?? const FaceCaptureScreen(),
      ),
    );
    if (face?.faceDetected != true || face?.movementChallengePassed != true) return null;
    return phone;
  }

  Future<void> _showBackupPhase() async {
    while (mounted && !backupCompleted && !backupSkipped) {
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Back up your wallet'),
          content: const Text(
            'Advanced: create an encrypted .zkidbackup file protected by a passphrase. Your BIP-39 phrase remains the primary wallet key recovery path.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'skip'),
              child: const Text('Skip for now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'backup'),
              child: const Text('Advanced: file backup'),
            ),
          ],
        ),
      );
      if (!mounted || action == null) return;
      if (action == 'backup') {
        if (await _createBackup()) return;
      } else if (action == 'skip') {
        final skip = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Confirm backup skip'),
            content: const Text(
              'If this device is lost or damaged, credentials stored only on it may be unrecoverable. You can create an encrypted backup later in Settings.',
            ),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Go back and back up'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Skip anyway'),
              ),
            ],
          ),
        );
        if (skip == true) {
          await vault.setBackupSkipped(true);
          if (mounted) setState(() => backupSkipped = true);
          return;
        }
      } else {
        return;
      }
    }
  }

  Future<bool> _createBackup() async {
    if (!unlocked) {
      await _unlock();
      if (!mounted || !unlocked) return false;
    }
    final password = TextEditingController();
    final confirmation = TextEditingController();
    String? validationError;
    final passphrase = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Protect your backup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: password,
                obscureText: true,
                autofillHints: const [],
                decoration: const InputDecoration(
                  labelText: 'Backup passphrase',
                  helperText: 'Use at least 12 characters.',
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: confirmation,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Confirm passphrase',
                ),
              ),
              if (validationError != null) ...[
                const SizedBox(height: 8),
                Text(validationError!,
                    style:
                        TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (password.text.length < 12) {
                  setDialogState(() => validationError =
                      'Use a passphrase with at least 12 characters.');
                } else if (password.text != confirmation.text) {
                  setDialogState(
                      () => validationError = 'The passphrases do not match.');
                } else {
                  Navigator.pop(dialogContext, password.text);
                }
              },
              child: const Text('Create backup'),
            ),
          ],
        ),
      ),
    );
    password.clear();
    confirmation.clear();
    password.dispose();
    confirmation.dispose();
    if (passphrase == null || !mounted) return false;

    try {
      final snapshot = await vault.createBackupSnapshot();
      final archive = await VaultBackupService().encrypt(snapshot, passphrase);
      await Share.shareXFiles(
        [
          XFile.fromData(
            Uint8List.fromList(archive),
            name: 'matchid-wallet.zkidbackup',
            mimeType: 'application/vnd.zk-matchid.vault-backup+json',
          ),
        ],
        fileNameOverrides: const ['matchid-wallet.zkidbackup'],
      );
      if (!mounted) return false;
      final saved = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Did you save the backup?'),
          content: const Text(
            'The backup file is encrypted. Restore requires the exact passphrase you just created.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Not yet'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('I saved it'),
            ),
          ],
        ),
      );
      if (saved == true) {
        await vault.setBackupCompleted(true);
        await vault.setBackupSkipped(false);
        if (mounted) {
          setState(() {
            backupCompleted = true;
            backupSkipped = false;
          });
        }
        return true;
      }
    } catch (_) {
      if (mounted) {
        _snack('Could not create the encrypted backup. Please try again.');
      }
    }
    return false;
  }

  Future<void> _restoreFromBackup() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['zkidbackup'],
        withData: true,
      );
      if (result == null || result.files.isEmpty || !mounted) return;
      final file = result.files.single;
      if (file.size > VaultBackupService.maxArchiveBytes) {
        throw const FormatException(
            'The backup file exceeds the supported size.');
      }
      final archive = file.bytes;
      if (archive == null || archive.isEmpty) {
        throw const FormatException('Could not read the selected backup file.');
      }
      if (walletCreated && !unlocked) {
        await _unlock();
        if (!mounted || !unlocked) return;
      }
      if (walletCreated) {
        final replace = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Replace this wallet?'),
            content: const Text(
              'Restoring replaces the credentials and activity currently stored on this device.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Continue'),
              ),
            ],
          ),
        );
        if (replace != true || !mounted) return;
      }
      final passphraseController = TextEditingController();
      final passphrase = await showDialog<String>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Unlock backup'),
          content: TextField(
            controller: passphraseController,
            obscureText: true,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Backup passphrase'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.pop(dialogContext, passphraseController.text),
              child: const Text('Restore'),
            ),
          ],
        ),
      );
      passphraseController.clear();
      passphraseController.dispose();
      if (passphrase == null || !mounted) return;
      final snapshot = await VaultBackupService().decrypt(archive, passphrase);
      await vault.restoreBackupSnapshot(snapshot);
      final config = await vault.readWalletConfig();
      final restoredCredentials = await vault.read();
      final restoredActivity = await vault.readActivity();
      if (!mounted) return;
      setState(() {
        walletCreated = true;
        walletName = config?['name'] as String? ?? 'My wallet';
        credentials = restoredCredentials;
        activity = restoredActivity;
        unlocked = true;
        backupSkipped = false;
        backupCompleted = true;
        tab = 0;
      });
      _refreshVaultLock();
      _snack('Wallet backup restored.');
    } on FormatException catch (error) {
      if (mounted) _snack(error.message);
    } catch (_) {
      if (mounted) _snack('Could not restore this backup. Please try again.');
    }
  }

  Future<void> _captureFace() async {
    final result = await Navigator.of(context).push<FaceCaptureResult>(
      MaterialPageRoute<FaceCaptureResult>(
        builder: (_) => const FaceCaptureScreen(),
      ),
    );
    if (result?.faceDetected == true &&
        result?.movementChallengePassed == true &&
        mounted) {
      _snack(
        'The guided face movement check passed on this device. It does not verify identity.',
      );
    }
  }

  Future<void> _linkPhone() async {
    if (walletCreated && !unlocked) {
      await _unlock();
      if (!mounted || !unlocked) return;
    }
    final verifiedPhoneNumber = await Navigator.of(context).push<String>(
      MaterialPageRoute<String>(
        builder: (_) => PhoneOtpScreen(
          otpService: MockOtpService(),
          initialPhoneNumber: verifiedPhone,
          onVerified: (phoneNumber) async {
            await vault.saveVerifiedPhone(phoneNumber);
            if (mounted) setState(() => verifiedPhone = phoneNumber);
            await _recordActivity(
              'Phone number verified',
              'SMS verification completed',
            );
          },
        ),
      ),
    );
    if (verifiedPhoneNumber != null && mounted) await _captureFace();
  }

  Future<void> _unlock() async {
    try {
      final config = await vault.readWalletConfig();
      if (config?['deviceLockEnabled'] == false) {
        final data = await vault.read();
        final events = await vault.readActivity();
        if (!mounted) return;
        setState(() {
          credentials = data;
          activity = events;
          unlocked = true;
        });
        return;
      }
      final auth = LocalAuthentication();
      if (!await auth.isDeviceSupported()) {
        throw Exception(
            'This device does not have a supported biometric or screen lock.');
      }
      final ok = await auth.authenticate(
          localizedReason: 'Unlock your MatchID credential vault');
      if (ok && mounted) {
        final data = await vault.read();
        final events = await vault.readActivity();
        if (mounted) {
          setState(() {
            credentials = data;
            activity = events;
            unlocked = true;
          });
          _refreshVaultLock();
        }
      }
    } on PlatformException catch (e) {
      if (mounted) {
        _snack(
            'Vault unlock failed: ${e.message ?? 'authentication unavailable'}');
      }
    } catch (e) {
      if (mounted) _snack(e.toString().replaceFirst('Exception: ', ''));
    }
  }

  Future<void> _importCredential() async {
    if (!mounted) return;
    if (!unlocked) {
      _snack('Unlock your wallet before adding a credential.');
      return;
    }
    final source = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Wrap(children: [
          const ListTile(
            title: Text('Add a DigiLocker credential'),
            subtitle: Text('Scan its QR or select the JSON export.'),
          ),
          ListTile(
            leading: const Icon(Icons.qr_code_scanner),
            title: const Text('Scan credential QR'),
            onTap: () => Navigator.pop(sheetContext, 'scan'),
          ),
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Choose DigiLocker JSON file'),
            onTap: () => Navigator.pop(sheetContext, 'file'),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('Get simulated demo credential'),
            subtitle: const Text('Fictional data · local demo service only'),
            onTap: () => Navigator.pop(sheetContext, 'demo'),
          ),
        ]),
      ),
    );
    if (!mounted || source == null) return;
    try {
      String raw;
      Map<String, dynamic>? demoEnvelope;
      Map<String, dynamic>? demoIssuerKey;
      if (source == 'scan') {
        final value = await Navigator.of(context).push<String>(
          MaterialPageRoute<String>(
            builder: (_) => const CredentialQrCaptureScreen(),
          ),
        );
        if (value == null) return;
        raw = value;
      } else if (source == 'file') {
        final selection = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: const ['json'],
          allowMultiple: false,
          withData: true,
        );
        if (selection == null || selection.files.isEmpty) return;
        final file = selection.files.single;
        final bytes = file.bytes;
        if (bytes == null || bytes.length > 2 * 1024 * 1024) {
          throw const FormatException('Choose a JSON file up to 2 MB.');
        }
        raw = utf8.decode(bytes);
      } else {
        const demoTypes = {
          'Aadhaar (demo)': 'aadhaar',
          'Voter ID (demo)': 'voter_id',
          'Passport (demo)': 'passport',
          'College (demo)': 'college',
        };
        final selected = await showDialog<String>(
          context: context,
          builder: (dialogContext) => SimpleDialog(
            title: const Text('SIMULATED DIGILOCKER: demo data'),
            children: demoTypes.entries
                .map((entry) => SimpleDialogOption(
                      onPressed: () =>
                          Navigator.pop(dialogContext, entry.value),
                      child: Text(entry.key),
                    ))
                .toList(),
          ),
        );
        if (selected == null) return;
        final provider = SimulatedDigiLockerHttpProvider.fromDartDefine();
        try {
          demoEnvelope = await provider.fetchDocument(
            type: selected,
            verifiedPhone: verifiedPhone ?? '',
          );
          demoIssuerKey = await provider.fetchIssuerKey();
        } finally {
          await provider.close();
        }
        raw = jsonEncode(demoEnvelope);
      }
      final presented = PresentedCredential.decode(raw);
      final credential = Map<String, dynamic>.from(presented.credential)
        ..['_matchidSourcePayload'] = raw
        ..['_matchidSignedToken'] = presented.signedToken
        ..['_matchidIssuerStatus'] = demoEnvelope?['issuerStatus']
        ..['_matchidDemoIssuerKey'] = demoIssuerKey;
      await vault.add(credential);
      await _recordActivity('Credential added',
          '${_credentialTitle(credential)} · ${presented.source}');
      if (mounted) {
        _snack('Credential added to $walletName. Check it in Verify.');
        final data = await vault.read();
        setState(() => credentials = data);
      }
    } on FormatException catch (e) {
      if (mounted) _snack(e.message);
    } catch (e) {
      if (mounted) _snack('Could not add credential: ${_errorText(e)}');
    }
  }

  Future<void> _remove(int index) async {
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
              title: const Text('Delete credential?'),
              content: const Text(
                  'This permanently removes the encrypted copy from this device.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Delete'))
              ],
            ));
    if (confirmed != true || !unlocked) return;
    final next = [...credentials]..removeAt(index);
    try {
      await vault.write(next);
      await _recordActivity('Credential deleted', 'Removed from this device');
      if (mounted) setState(() => credentials = next);
    } catch (e) {
      if (mounted) _snack('Could not delete credential: $e');
    }
  }

  void _snack(String text) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _recordActivity(String title, String detail) async {
    final events = await vault.addActivity(title, detail);
    if (mounted) setState(() => activity = events);
  }

  @override
  Widget build(BuildContext context) {
    if (!walletInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }
    if (!walletCreated) return _welcomePage();
    final pages = [
      _homePage(),
      _verifyPage(),
      _activityPage(),
      _settingsPage(),
    ];
    return Scaffold(
      body: SafeArea(
          child: Listener(
              onPointerDown: (_) => _refreshVaultLock(),
              child: IndexedStack(index: tab, children: pages))),
      bottomNavigationBar: NavigationBar(
          selectedIndex: tab,
          onDestinationSelected: (i) => setState(() => tab = i),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.account_balance_wallet_outlined),
                label: 'Wallet'),
            NavigationDestination(
                icon: Icon(Icons.qr_code_scanner_outlined), label: 'Verify'),
            NavigationDestination(icon: Icon(Icons.history), label: 'Activity'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined), label: 'Settings'),
          ]),
    );
  }

  Widget _welcomePage() => Scaffold(
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(28),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 64,
                      height: 64,
                      decoration: const BoxDecoration(
                        color: AppColors.chip,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.lock_outline,
                        color: AppColors.primary,
                        size: 30,
                      ),
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      'Create your identity wallet',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Your credentials stay encrypted on this device. They are not uploaded.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.secondaryText),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: _createLocalWallet,
                      child: const Text('Create new wallet'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: _showRestoreInfo,
                      child: const Text('Restore from backup'),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Link your phone with SMS verification in Settings. The guided face check detects movement on this device; it does not confirm identity.',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodySmall,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _homePage() =>
      ListView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 28), children: [
        Row(children: [
          Expanded(
              child: InkWell(
            onTap: _switchWallet,
            child: Row(children: [
              Flexible(
                child: Text(walletName,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        letterSpacing: -.4)),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more, size: 20),
            ]),
          )),
          IconButton.filledTonal(
              tooltip: 'Add credential from QR or JSON',
              onPressed: _importCredential,
              icon: const Icon(Icons.add)),
          IconButton(
              tooltip: unlocked ? 'Lock wallet' : 'Unlock wallet',
              onPressed: unlocked ? _lockVault : _unlock,
              icon: Icon(unlocked ? Icons.lock_open : Icons.lock_outline)),
        ]),
        const SizedBox(height: 6),
        const Text('Your credentials stay encrypted on this device.',
            style: TextStyle(color: AppColors.secondaryText, fontSize: 13)),
        const SizedBox(height: 18),
        if (backupSkipped && !backupCompleted) ...[
          _Notice(
            icon: Icons.backup_outlined,
            title: 'Wallet backup skipped',
            text:
                'Create an encrypted backup later to protect your wallet if this device is lost.',
            action: FilledButton(
              onPressed: _createBackup,
              child: const Text('Back up wallet'),
            ),
          ),
          const SizedBox(height: 12),
        ],
        if (!unlocked)
          _Notice(
              icon: Icons.fingerprint,
              title: 'Wallet locked',
              text: 'Unlock to view or manage credentials.',
              action: FilledButton(
                  onPressed: _unlock,
                  child: const Text('Unlock wallet securely')))
        else if (credentials.isEmpty)
          _EmptyState(
              icon: Icons.description_outlined,
              title: 'No credentials yet',
              text:
                  'Add a credential by scanning its QR or selecting the JSON export from DigiLocker.',
              action: OutlinedButton.icon(
                  onPressed: _importCredential,
                  icon: const Icon(Icons.add),
                  label: const Text('Add credential')))
        else ...[
          ...credentials.asMap().entries.map((entry) => _CredentialCard(
                data: entry.value,
                onTap: () => _showCredentialDetail(entry.value),
                onDelete: () => _remove(entry.key),
              )),
          const SizedBox(height: 14),
          const _Notice(
              icon: Icons.info_outline,
              title: 'Signature status is separate',
              text:
                  'A wallet match compares credential fields with credentials already stored here. It does not validate issuer signatures or revocation status.'),
        ],
      ]);

  Future<void> _showCredentialDetail(Map<String, dynamic> data) async {
    final issuer = data['issuer'];
    final issuerName = issuer is Map ? issuer['name'] ?? issuer['id'] : issuer;
    final expiry = data['expirationDate']?.toString();
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => SafeArea(
          child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(_credentialTitle(data),
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              _DetailRow(
                  label: 'Issuer',
                  value: issuerName?.toString() ?? 'Not provided'),
              _DetailRow(
                  label: 'Credential ID',
                  value: data['id']?.toString() ?? 'Unavailable'),
              _DetailRow(label: 'Expires', value: expiry ?? 'Not provided'),
              const SizedBox(height: 12),
              if (data['_matchidIssuerStatus'] == 'SIMULATED')
                const _Notice(
                    icon: Icons.science_outlined,
                    title: 'SIMULATED DIGILOCKER: demo data',
                    text:
                        'This fictional sample is not from DigiLocker or UIDAI. Use the Verify screen to check its signature against the configured demo issuer key.'),
              const _Notice(
                  icon: Icons.gpp_maybe_outlined,
                  title: 'Issuer status',
                  text:
                      'A JSON field match does not establish authenticity. The Verify screen checks an available issuer signature; revocation is only checked when a trusted issuer service is configured.'),
            ]),
      )),
    );
  }

  Widget _activityPage() =>
      ListView(padding: const EdgeInsets.all(20), children: [
        _PageHeader(
            eyebrow: 'ON THIS DEVICE',
            title: 'Activity',
            subtitle: 'Recent wallet and verification events.'),
        const SizedBox(height: 18),
        if (activity.isEmpty)
          const _EmptyState(
              icon: Icons.history,
              title: 'No activity recorded',
              text: 'Wallet actions will appear here.')
        else
          ...activity.map((event) => Card(
                margin: const EdgeInsets.only(bottom: 8),
                child: ListTile(
                  leading: const Icon(Icons.history, color: AppColors.primary),
                  title: Text(event['title']?.toString() ?? 'Wallet event'),
                  subtitle: Text(event['detail']?.toString() ?? ''),
                  trailing: Text(
                    _formatActivityTime(event['createdAt']?.toString()),
                    style: AppTypography.bodySmall,
                  ),
                ),
              )),
      ]);

  Widget _settingsPage() =>
      ListView(padding: const EdgeInsets.all(20), children: [
        _PageHeader(
            eyebrow: walletName.toUpperCase(),
            title: 'Settings',
            subtitle: 'Manage local security and stored credentials.'),
        const SizedBox(height: 18),
        Card(
            child: ListTile(
          leading: const Icon(Icons.backup_outlined, color: AppColors.primary),
          title: const Text('Advanced: file backup'),
          subtitle: Text(backupCompleted
              ? 'Create a fresh copy of this wallet'
              : 'Secondary .zkidbackup restore path'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _createBackup,
        )),
        const SizedBox(height: 8),
        Card(
            child: ListTile(
          leading: const Icon(Icons.restore, color: AppColors.primary),
          title: const Text('Restore wallet'),
          subtitle: const Text('Recovery phrase or Advanced: file backup'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showRestoreInfo,
        )),
        const SizedBox(height: 8),
        Card(
            child: ListTile(
          leading: const Icon(Icons.add_card_outlined, color: AppColors.primary),
          title: const Text('Create another wallet'),
          subtitle: const Text('Keep a separate set of credentials on this device'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _createLocalWallet,
        )),
        const SizedBox(height: 12),
        Card(
            child: ListTile(
          leading: const Icon(Icons.face_retouching_natural,
              color: AppColors.primary),
          title: const Text('Face capture'),
          subtitle: const Text('Local face presence check only'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _captureFace,
        )),
        const SizedBox(height: 12),
        Card(
            child: ListTile(
          leading: const Icon(Icons.phone_android, color: AppColors.primary),
          title: const Text('Linked phone number'),
          subtitle: Text(verifiedPhone == null
              ? 'Verify a phone number with SMS'
              : 'Verified · ${_maskPhone(verifiedPhone!)}'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _linkPhone,
        )),
        const SizedBox(height: 12),
        Card(
            child: ListTile(
          leading: const Icon(Icons.fingerprint, color: AppColors.primary),
          title: const Text('Biometric wallet lock'),
          subtitle: Text(unlocked ? 'Wallet is unlocked' : 'Wallet is locked'),
          trailing: const Icon(Icons.chevron_right),
          onTap: unlocked ? _lockVault : _unlock,
        )),
        const SizedBox(height: 12),
        Card(
            child: ListTile(
          leading: const Icon(Icons.delete_outline, color: AppColors.danger),
          title: const Text('Wipe wallet data'),
          subtitle: const Text('Delete every credential stored on this device'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _requestWipe,
        )),
        const SizedBox(height: 14),
        const _Notice(
            icon: Icons.shield_outlined,
            title: 'Local storage',
            text:
                'Credentials are protected by platform storage and wallet-key encryption. Your wallet stays on this device; cloud sync is not connected.'),
      ]);

  Future<void> _confirmWipe() async {
    final controller = TextEditingController();
    final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => StatefulBuilder(
            builder: (context, setDialogState) => AlertDialog(
                  title: const Text('Wipe wallet data?'),
                  content: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                            'This permanently deletes all credentials stored on this device. Type DELETE to confirm.'),
                        const SizedBox(height: 12),
                        TextField(
                            controller: controller,
                            onChanged: (_) => setDialogState(() {}),
                            decoration: const InputDecoration(
                                labelText: 'Type DELETE')),
                      ]),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel')),
                    FilledButton(
                        onPressed: controller.text == 'DELETE'
                            ? () => Navigator.pop(context, true)
                            : null,
                        child: const Text('Wipe data')),
                  ],
                )));
    controller.dispose();
    if (confirmed != true) return;
    try {
      await vault.wipe();
      if (mounted) {
        setState(() {
          credentials = [];
          activity = [];
          walletCreated = false;
          unlocked = false;
          backupSkipped = false;
          backupCompleted = false;
          walletName = 'My wallet';
          tab = 0;
        });
        _snack('Wallet data deleted.');
      }
    } catch (e) {
      if (mounted) _snack('Could not wipe stored credentials: $e');
    }
  }

  Future<void> _requestWipe() async {
    if (!unlocked) {
      await _unlock();
      if (!unlocked || !mounted) return;
    }
    await _confirmWipe();
  }

  Widget _verifyPage() => VerifyPage(
        onActivity: _recordActivity,
        walletName: walletName,
        walletCredentials: unlocked ? credentials : const [],
      );
}

String _formatActivityTime(String? value) {
  final date = value == null ? null : DateTime.tryParse(value)?.toLocal();
  if (date == null) return '';
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class CredentialQrCaptureScreen extends StatefulWidget {
  const CredentialQrCaptureScreen({super.key});

  @override
  State<CredentialQrCaptureScreen> createState() =>
      _CredentialQrCaptureScreenState();
}

class _CredentialQrCaptureScreenState extends State<CredentialQrCaptureScreen> {
  bool _handled = false;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Scan DigiLocker credential')),
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(children: [
              const Text(
                  'Place the credential QR inside the frame. Its contents stay on this device.'),
              const SizedBox(height: 14),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: MobileScanner(
                    onDetect: (capture) {
                      if (_handled) return;
                      final value = capture.barcodes
                          .map((barcode) => barcode.rawValue)
                          .whereType<String>()
                          .firstOrNull;
                      if (value != null && context.mounted) {
                        _handled = true;
                        Navigator.of(context).pop(value);
                      }
                    },
                  ),
                ),
              ),
            ]),
          ),
        ),
      );
}

class VerifyPage extends StatefulWidget {
  const VerifyPage({
    super.key,
    required this.onActivity,
    required this.walletName,
    required this.walletCredentials,
  });
  final Future<void> Function(String title, String detail) onActivity;
  final String walletName;
  final List<Map<String, dynamic>> walletCredentials;
  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  bool scanning = false;
  bool verifying = false;
  CredentialVerificationResult? result;
  CredentialWalletMatch? walletMatch;
  String? inputError;

  CredentialVerificationService _verifierForWallet() {
    final registry = <String, dynamic>{};
    final configured = CredentialVerificationService.trustRegistryJson;
    if (configured.isNotEmpty) {
      try {
        final decoded = jsonDecode(configured);
        if (decoded is Map<String, dynamic>) registry.addAll(decoded);
      } on FormatException {
        // An invalid optional registry contributes no trust entries.
      }
    }
    final issuers = <String, Map<String, dynamic>>{};
    final existing = registry['issuers'];
    if (existing is List) {
      for (final issuer in existing.whereType<Map>()) {
        final id = issuer['id'];
        if (id is String && id.isNotEmpty) {
          issuers[id] = Map<String, dynamic>.from(issuer);
        }
      }
    }
    for (final credential in widget.walletCredentials) {
      final key = credential['_matchidDemoIssuerKey'];
      if (key is! Map) continue;
      final issuerId = key['issuer'];
      final keyId = key['id'];
      final algorithm = key['algorithm'];
      final publicKey = key['publicKey'];
      if (issuerId is! String ||
          keyId is! String ||
          algorithm != 'EdDSA' ||
          publicKey is! String ||
          key['demoOnly'] != true) {
        continue;
      }
      final issuer = issuers.putIfAbsent(
          issuerId, () => {'id': issuerId, 'keys': <Map<String, dynamic>>[]});
      final keys = issuer['keys'];
      if (keys is List &&
          !keys.any((entry) => entry is Map && entry['kid'] == keyId)) {
        keys.add({'kid': keyId, 'alg': algorithm, 'publicKey': publicKey});
      }
    }
    registry['issuers'] = issuers.values.toList();
    return CredentialVerificationService(trustRegistry: registry);
  }

  Future<void> _verifyValue(String raw) async {
    if (verifying) return;
    setState(() {
      scanning = false;
      verifying = true;
      result = null;
      walletMatch = null;
      inputError = null;
    });
    try {
      final presented = PresentedCredential.decode(raw);
      final match = CredentialWalletMatcher.match(
        walletName: widget.walletName,
        presented: presented.credential,
        walletCredentials: widget.walletCredentials,
      );
      CredentialVerificationResult? signature;
      final signedToken = presented.signedToken;
      if (signedToken != null) {
        signature = await _verifierForWallet().verifyQr(signedToken);
      }
      if (!mounted) return;
      setState(() {
        verifying = false;
        walletMatch = match;
        result = signature;
      });
      await widget.onActivity(
        match.matches
            ? 'Credential matched wallet'
            : 'Credential did not match wallet',
        '${match.credentialType} · name ${match.nameMatches ? 'matched' : 'not matched'} · masked ID ${match.maskedIdentifierMatches ? 'matched' : 'not matched'}',
      );
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        verifying = false;
        inputError = e.message;
      });
    }
  }

  Future<void> _handleScan(BarcodeCapture capture) async {
    final value =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    await _verifyValue(value);
  }

  Future<void> _chooseJson() async {
    final selection = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: const ['json'],
      allowMultiple: false,
      withData: true,
    );
    if (selection == null || selection.files.isEmpty) return;
    final bytes = selection.files.single.bytes;
    if (bytes == null || bytes.length > 2 * 1024 * 1024) {
      setState(() => inputError = 'Choose a JSON file up to 2 MB.');
      return;
    }
    try {
      await _verifyValue(utf8.decode(bytes));
    } on FormatException catch (e) {
      if (mounted) setState(() => inputError = e.message);
    }
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(22), children: [
        const _PageHeader(
            eyebrow: 'CREDENTIAL VERIFICATION',
            title: 'Match a credential to this wallet',
            subtitle:
                'Scan the credential QR or choose its DigiLocker JSON export. We compare its holder name and masked ID suffix with credentials saved in this wallet.'),
        const SizedBox(height: 16),
        const _Notice(
          icon: Icons.security_outlined,
          title: 'Wallet match is not an issuer proof',
          text:
              'A matching name and masked identifier show that the presented data matches a credential already in this local wallet. This does not prove the QR is issuer-signed or current.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: scanning || verifying
              ? null
              : () => setState(() {
                    scanning = true;
                    result = null;
                    walletMatch = null;
                    inputError = null;
                  }),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan credential QR'),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          onPressed: verifying ? null : _chooseJson,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('Choose DigiLocker JSON'),
        ),
        if (widget.walletCredentials.isEmpty) ...[
          const SizedBox(height: 12),
          const _Notice(
            icon: Icons.lock_outline,
            title: 'Unlock and add a credential first',
            text:
                'The wallet match needs at least one credential stored in this wallet for comparison.',
          ),
        ],
        if (verifying) ...[
          const SizedBox(height: 18),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text('Reading credential and comparing wallet fields…'),
        ],
        if (scanning) ...[
          const SizedBox(height: 16),
          SizedBox(
              height: 320,
              child: ClipRRect(
                  borderRadius: BorderRadius.circular(22),
                  child: MobileScanner(onDetect: _handleScan))),
          TextButton(
              onPressed: () => setState(() => scanning = false),
              child: const Text('Cancel scan')),
        ],
        if (walletMatch != null) ...[
          const SizedBox(height: 16),
          _Notice(
            icon: walletMatch!.matches
                ? Icons.verified_user_outlined
                : Icons.gpp_bad_outlined,
            title: walletMatch!.matches
                ? 'Credential matches ${walletMatch!.walletName}'
                : 'Credential does not match this wallet',
            text:
                '${walletMatch!.credentialType}\nHolder name: ${walletMatch!.nameMatches ? 'MATCH' : 'NO MATCH'}\nMasked credential: ${walletMatch!.maskedIdentifierMatches ? walletMatch!.maskedIdentifiers.join(', ') : 'NO MATCH'}',
          ),
          const SizedBox(height: 8),
          _Notice(
            icon: result == null
                ? Icons.info_outline
                : result!.verified
                    ? Icons.verified_outlined
                    : Icons.gpp_bad_outlined,
            title: result == null
                ? 'Issuer signature not checked'
                : result!.verified
                    ? 'Issuer signature verified'
                    : 'Issuer signature rejected',
            text: result == null
                ? 'No signed token was included or a trusted issuer key is not configured. Field matching alone is not cryptographic verification.'
                : '${result!.message}${result!.issuer == null ? '' : '\n${result!.issuer}'}${result!.expiresAt == null ? '' : '\nExpires ${result!.expiresAt!.toLocal()}'}',
          ),
          const SizedBox(height: 8),
          const _Notice(
            icon: Icons.info_outline,
            title: 'Verification scope',
            text:
                'This check compares values inside the presented payload to values already in the local wallet. It does not verify QR authenticity, prove that the person holding the phone is the holder, or check revocation/DigiLocker status.',
          ),
        ],
        if (inputError != null) ...[
          const SizedBox(height: 12),
          _Notice(
              icon: Icons.error_outline,
              title: 'Could not read credential',
              text: inputError!),
        ],
        const SizedBox(height: 18),
        if (!scanning && !verifying)
          OutlinedButton.icon(
            onPressed: () => setState(() {
              scanning = true;
              result = null;
            }),
            icon: const Icon(Icons.refresh),
            label: const Text('Scan again'),
          ),
      ]);
}

class VaultStore implements VaultRepository {
  VaultStore({SecureKeyValueStore? storage})
      : _storage = storage ?? const DeviceSecureKeyValueStore();

  final SecureKeyValueStore _storage;
  static const _key = 'credential_vault_v1';
  static const _walletConfigKey = 'wallet_config_v1';
  static const _activityKey = 'wallet_activity_v1';
  static const _backupSkippedKey = 'backup_skipped_v1';
  static const _backupCompletedKey = 'backup_completed_v1';
  static const _verifiedPhoneKey = 'verified_phone_v1';
  static const _identityRecordKey = 'identity_record_v1';
  static const _identityPepperKey = 'identity_phone_pepper_v1';
  static const _walletRecordsKey = 'wallet_records_v1';
  static const _activeWalletIdKey = 'active_wallet_id_v1';

  Future<List<Map<String, dynamic>>> _readWalletRecords() async {
    final raw = await _storage.read(key: _walletRecordsKey);
    if (raw == null) return [];
    final value = jsonDecode(raw);
    if (value is! List || value.any((item) => item is! Map)) {
      throw const FormatException('The saved wallet index is invalid.');
    }
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<List<Map<String, dynamic>>> _readIdentityRecords() async {
    final raw = await _storage.read(key: _identityRecordKey);
    if (raw == null) return [];
    final value = jsonDecode(raw);
    if (value is Map) return [Map<String, dynamic>.from(value)];
    if (value is! List || value.any((item) => item is! Map)) {
      throw const FormatException('The saved identity index is invalid.');
    }
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  Future<String?> _activeWalletId() => _storage.read(key: _activeWalletIdKey);

  Future<String> _newWalletId() async {
    final bytes = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final hex = bytes.map((value) => value.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-4${hex.substring(13, 16)}-a${hex.substring(17, 20)}-${hex.substring(20)}';
  }

  Future<String> _phoneHash(String phone) async {
    var pepper = await _storage.read(key: _identityPepperKey);
    if (pepper == null) {
      pepper = base64UrlEncode(List<int>.generate(32, (_) => Random.secure().nextInt(256)));
      await _storage.write(key: _identityPepperKey, value: pepper);
    }
    return crypto.Hmac(crypto.sha256, base64Url.decode(base64Url.normalize(pepper)))
        .convert(utf8.encode(phone)).toString();
  }

  Future<String> _encryptWalletName(String name, String derivedKey) async {
    final key = base64Url.decode(base64Url.normalize(derivedKey));
    if (key.length != 32) throw StateError('Wallet key material is invalid.');
    final algorithm = AesGcm.with256bits();
    final nonce = algorithm.newNonce();
    final box = await algorithm.encrypt(utf8.encode(name), secretKey: SecretKey(key), nonce: nonce);
    return base64UrlEncode([...nonce, ...box.cipherText, ...box.mac.bytes]);
  }

  Future<String> _decryptWalletName(String encrypted, String derivedKey) async {
    final bytes = base64Url.decode(base64Url.normalize(encrypted));
    if (bytes.length < 29) throw const FormatException('Encrypted wallet name is invalid.');
    final algorithm = AesGcm.with256bits();
    final box = SecretBox(bytes.sublist(12, bytes.length - 16), nonce: bytes.sublist(0, 12), mac: Mac(bytes.sublist(bytes.length - 16)));
    final clear = await algorithm.decrypt(box, secretKey: SecretKey(base64Url.decode(base64Url.normalize(derivedKey))));
    return utf8.decode(clear);
  }

  Future<String> _encryptVaultContents(String plainJson, String derivedKey) async =>
      jsonEncode({
        'format': 'matchid-encrypted-vault-v1',
        'blob': await _encryptWalletName(plainJson, derivedKey),
      });

  Future<String> _decryptVaultContents(String stored, String derivedKey) async {
    final decoded = jsonDecode(stored);
    if (decoded is Map && decoded['format'] == 'matchid-encrypted-vault-v1') {
      final blob = decoded['blob'];
      if (blob is! String) throw const FormatException('Encrypted wallet data is invalid.');
      return _decryptWalletName(blob, derivedKey);
    }
    return stored; // Legacy secure-storage vault; migration re-encrypts it.
  }

  String _maskWalletName(String name) {
    final visible = String.fromCharCodes(name.trim().runes.take(2));
    return '$visible•••••';
  }

  Future<String> _credentialKeyForActiveWallet() async {
    final id = await _activeWalletId();
    return id == null ? _key : 'credential_vault_$id';
  }

  Future<String> _configKeyForActiveWallet() async {
    final id = await _activeWalletId();
    return id == null ? _walletConfigKey : 'wallet_config_$id';
  }

  String _localCredentialFingerprint(Map<String, dynamic> value) {
    final issuer = value['issuer'];
    final issuerId = issuer is Map ? issuer['id'] : issuer;
    final id = value['id'];
    final stableId = id is String && id.isNotEmpty
        ? '$issuerId\u0000$id'
        : jsonEncode(value);
    return crypto.sha256.convert(utf8.encode(stableId)).toString();
  }

  @override
  Future<List<Map<String, dynamic>>> readWallets() async {
    final records = await _readWalletRecords();
    final result = <Map<String, dynamic>>[];
    for (final record in records) {
      final id = record['id'];
      if (id is! String) continue;
      final configRaw = await _storage.read(key: 'wallet_config_$id');
      final config = configRaw == null ? <String, dynamic>{} : jsonDecode(configRaw) as Map<String, dynamic>;
      final derivedKey = config['mnemonicDerivedKey'];
      final encrypted = record['nameEncrypted'];
      String? name;
      if (derivedKey is String && encrypted is String) name = await _decryptWalletName(encrypted, derivedKey);
      result.add({...record, if (name != null) 'name': name});
    }
    return result;
  }

  @override
  Future<void> selectWallet(String walletId) async {
    final records = await _readWalletRecords();
    if (!records.any((record) => record['id'] == walletId)) {
      throw const FormatException('That wallet is not available on this device.');
    }
    await _storage.write(key: _activeWalletIdKey, value: walletId);
  }

  @override
  Future<String?> readVerifiedPhone() => _storage.read(key: _verifiedPhoneKey);

  @override
  Future<void> saveVerifiedPhone(String phoneNumber) async {
    if (!RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phoneNumber)) {
      throw const FormatException(
          'Phone number must use international E.164 format.');
    }
    await _storage.write(key: _verifiedPhoneKey, value: phoneNumber);
  }

  @override
  Future<bool> isBackupSkipped() async =>
      await _storage.read(key: _backupSkippedKey) == 'true';

  @override
  Future<void> setBackupSkipped(bool skipped) =>
      _storage.write(key: _backupSkippedKey, value: skipped.toString());

  @override
  Future<bool> isBackupCompleted() async =>
      await _storage.read(key: _backupCompletedKey) == 'true';

  @override
  Future<void> setBackupCompleted(bool completed) =>
      _storage.write(key: _backupCompletedKey, value: completed.toString());

  @override
  Future<Map<String, dynamic>> createBackupSnapshot() async {
    final config = await readWalletConfig();
    if (config == null) {
      throw StateError('Create a wallet before backing it up.');
    }
    return {
      'format': 'zk-matchid-wallet-state',
      'version': 1,
      'walletConfig': config,
      'credentials': await read(),
      'activity': await readActivity(),
      'verifiedPhone': await readVerifiedPhone(),
    };
  }

  @override
  Future<void> restoreBackupSnapshot(Map<String, dynamic> snapshot) async {
    if (snapshot['format'] != 'zk-matchid-wallet-state' ||
        snapshot['version'] != 1) {
      throw const FormatException(
          'This backup does not contain a supported wallet.');
    }
    final config = snapshot['walletConfig'];
    final credentials = snapshot['credentials'];
    final events = snapshot['activity'];
    final phone = snapshot['verifiedPhone'];
    if (config is! Map ||
        credentials is! List ||
        events is! List ||
        (phone != null &&
            (phone is! String ||
                !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(phone))) ||
        credentials.length > 50 ||
        credentials.any((item) => item is! Map) ||
        events.any((item) => item is! Map)) {
      throw const FormatException('The backup wallet data is invalid.');
    }
    final normalizedConfig = Map<String, dynamic>.from(config);
    final normalizedCredentials = credentials
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final normalizedEvents = events
        .take(100)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
    final encodedCredentials = jsonEncode(normalizedCredentials);
    if (_utf8ByteLength(encodedCredentials, limit: maxVaultJsonBytes) >
        maxVaultJsonBytes) {
      throw const FormatException(
          'The backup vault exceeds the supported size.');
    }
    final activeId = await _activeWalletId();
    final credentialsKey = activeId == null ? _key : 'credential_vault_$activeId';
    final configKey = activeId == null ? _walletConfigKey : 'wallet_config_$activeId';
    await _storage.write(
        key: configKey, value: jsonEncode(normalizedConfig));
    if (activeId != null) {
      final name = normalizedConfig['name'];
      final derivedKey = normalizedConfig['mnemonicDerivedKey'];
      if (name is String && derivedKey is String) {
        final records = await _readWalletRecords();
        final index = records.indexWhere((record) => record['id'] == activeId);
        if (index >= 0) {
          records[index] = {
            ...records[index],
            'nameMasked': _maskWalletName(name),
            'nameEncrypted': await _encryptWalletName(name, derivedKey),
          };
          await _storage.write(key: _walletRecordsKey, value: jsonEncode(records));
        }
      }
    }
    final derivedKey = normalizedConfig['mnemonicDerivedKey'];
    if (derivedKey is! String) {
      throw const FormatException('Backup wallet recovery key is missing.');
    }
    await _storage.write(
        key: credentialsKey,
        value: await _encryptVaultContents(encodedCredentials, derivedKey));
    await _storage.write(
        key: _activityKey, value: jsonEncode(normalizedEvents));
    if (phone is String) {
      await saveVerifiedPhone(phone);
    } else {
      await _storage.delete(key: _verifiedPhoneKey);
    }
    await setBackupCompleted(true);
    await setBackupSkipped(false);
  }

  @override
  Future<List<Map<String, dynamic>>> readActivity() async {
    final raw = await _storage.read(key: _activityKey);
    if (raw == null) return [];
    final decoded = jsonDecode(raw);
    if (decoded is! List || decoded.any((item) => item is! Map)) return [];
    return decoded
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  @override
  Future<List<Map<String, dynamic>>> addActivity(
      String title, String detail) async {
    final events = await readActivity();
    events.insert(0, {
      'title': title,
      'detail': detail,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
    });
    if (events.length > 100) events.removeRange(100, events.length);
    await _storage.write(key: _activityKey, value: jsonEncode(events));
    return events;
  }

  @override
  Future<Map<String, dynamic>?> readWalletConfig() async {
    final raw = await _storage.read(key: await _configKeyForActiveWallet());
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('The saved wallet profile is invalid.');
    }
    final config = Map<String, dynamic>.from(decoded);
    final activeId = await _activeWalletId();
    if (activeId != null) {
      final records = await _readWalletRecords();
      final record = records.where((item) => item['id'] == activeId).firstOrNull;
      final encrypted = record?['nameEncrypted'];
      final derivedKey = config['mnemonicDerivedKey'];
      if (encrypted is String && derivedKey is String) {
        config['name'] = await _decryptWalletName(encrypted, derivedKey);
      }
    }
    return config;
  }

  @override
  Future<void> createWallet(String name,
      {String? mnemonicDerivedKey, bool deviceLockEnabled = true}) async {
    if (mnemonicDerivedKey == null) {
      throw StateError('A recovery phrase is required to protect the wallet name.');
    }
    final phone = await readVerifiedPhone();
    if (phone == null) throw StateError('Verify a phone number before creating a wallet.');
    final phoneHash = await _phoneHash(phone);
    final identities = await _readIdentityRecords();
    var identity = identities.where((item) => item['phoneHash'] == phoneHash).firstOrNull;
    if (identity == null) {
      identity = {
        'id': await _newWalletId(),
        'phoneHash': phoneHash,
        'faceEmbedding': null,
        'createdAt': DateTime.now().toUtc().toIso8601String(),
      };
      identities.add(identity);
      await _storage.write(key: _identityRecordKey, value: jsonEncode(identities));
    }

    var records = await _readWalletRecords();
    if (records.isEmpty) {
      final legacyConfigRaw = await _storage.read(key: _walletConfigKey);
      final legacyCredentialsRaw = await _storage.read(key: _key);
      if (legacyConfigRaw != null || legacyCredentialsRaw != null) {
        final legacyConfig = legacyConfigRaw == null
            ? <String, dynamic>{}
            : Map<String, dynamic>.from(jsonDecode(legacyConfigRaw) as Map);
        final legacyId = await _newWalletId();
        final legacyKey = (legacyConfig['mnemonicDerivedKey'] as String?) ?? mnemonicDerivedKey;
        final oldName = (legacyConfig['name'] as String?) ?? 'Recovered wallet';
        final encryptedName = await _encryptWalletName(oldName, legacyKey);
        final now = DateTime.now().toUtc().toIso8601String();
        records.add({
          'id': legacyId,
          'identityId': identity['id'],
          'nameMasked': _maskWalletName(oldName),
          'nameEncrypted': encryptedName,
          'vaultRef': 'local-wallet:$legacyId',
          'createdAt': (legacyConfig['createdAt'] as String?) ?? now,
        });
        await _storage.write(key: 'wallet_config_$legacyId', value: jsonEncode({
          'mnemonicDerivedKey': legacyKey,
          'deviceLockEnabled': legacyConfig['deviceLockEnabled'] ?? true,
          'createdAt': (legacyConfig['createdAt'] as String?) ?? now,
        }));
        if (legacyCredentialsRaw != null) {
          await _storage.write(
              key: 'credential_vault_$legacyId',
              value: await _encryptVaultContents(legacyCredentialsRaw, legacyKey));
        }
        await _storage.write(key: _walletRecordsKey, value: jsonEncode(records));
        // Remove the legacy copies only after the re-encrypted wallet and its
        // index are durable; the migrated data remains available as Wallet #1.
        await _storage.delete(key: _key);
        await _storage.delete(key: _walletConfigKey);
      }
    }

    final walletId = await _newWalletId();
    final createdAt = DateTime.now().toUtc().toIso8601String();
    final encryptedName = await _encryptWalletName(name, mnemonicDerivedKey);
    records.add({
      'id': walletId,
      'identityId': identity['id'],
      'nameMasked': _maskWalletName(name),
      'nameEncrypted': encryptedName,
      'vaultRef': 'local-wallet:$walletId',
      'createdAt': createdAt,
    });
    await _storage.write(key: 'wallet_config_$walletId', value: jsonEncode({
      'mnemonicDerivedKey': mnemonicDerivedKey,
      'deviceLockEnabled': deviceLockEnabled,
      'createdAt': createdAt,
    }));
    await _storage.write(key: _walletRecordsKey, value: jsonEncode(records));
    await _storage.write(key: _activeWalletIdKey, value: walletId);
  }

  @override
  Future<void> wipe() async {
    for (final record in await _readWalletRecords()) {
      final id = record['id'];
      if (id is String) {
        await _storage.delete(key: 'credential_vault_$id');
        await _storage.delete(key: 'wallet_config_$id');
      }
    }
    await _storage.delete(key: _key);
    await _storage.delete(key: _walletConfigKey);
    await _storage.delete(key: _activityKey);
    await _storage.delete(key: _backupSkippedKey);
    await _storage.delete(key: _backupCompletedKey);
    await _storage.delete(key: _verifiedPhoneKey);
    await _storage.delete(key: _identityRecordKey);
    await _storage.delete(key: _identityPepperKey);
    await _storage.delete(key: _walletRecordsKey);
    await _storage.delete(key: _activeWalletIdKey);
  }

  @override
  Future<List<Map<String, dynamic>>> read() async {
    final raw = await _storage.read(key: await _credentialKeyForActiveWallet());
    if (raw == null) return [];
    final configRaw = await _storage.read(key: await _configKeyForActiveWallet());
    if (configRaw == null) throw const FormatException('Wallet key configuration is missing.');
    final config = jsonDecode(configRaw);
    final derivedKey = config is Map ? config['mnemonicDerivedKey'] : null;
    if (derivedKey is! String) throw const FormatException('Wallet recovery key is missing.');
    final value = jsonDecode(await _decryptVaultContents(raw, derivedKey));
    if (value is! List || value.any((item) => item is! Map)) {
      throw const FormatException(
          'The encrypted credential vault has invalid data.');
    }
    return value.map((item) => Map<String, dynamic>.from(item as Map)).toList();
  }

  @override
  Future<void> write(List<Map<String, dynamic>> data) async {
    final encoded = jsonEncode(data);
    if (_utf8ByteLength(encoded, limit: maxVaultJsonBytes) >
        maxVaultJsonBytes) {
      throw StateError('The vault has reached its 200 MB storage limit.');
    }
    final configRaw = await _storage.read(key: await _configKeyForActiveWallet());
    if (configRaw == null) throw StateError('Create or restore a wallet before storing credentials.');
    final config = jsonDecode(configRaw);
    final derivedKey = config is Map ? config['mnemonicDerivedKey'] : null;
    if (derivedKey is! String) throw StateError('The wallet recovery key is unavailable.');
    await _storage.write(
        key: await _credentialKeyForActiveWallet(),
        value: await _encryptVaultContents(encoded, derivedKey));
  }

  @override
  Future<void> add(Map<String, dynamic> value) async {
    final all = await read();
    if (all.length >= 50) {
      throw StateError('The vault has reached its 50 credential limit.');
    }
    final valueId = value['id'];
    final valueIssuer = value['issuer'];
    if (valueId is String &&
        valueId.isNotEmpty &&
        all.any((existing) =>
            existing['id'] == valueId &&
            existing['issuer'].toString() == valueIssuer.toString())) {
      throw StateError('This credential is already stored.');
    }
    final fingerprint = _localCredentialFingerprint(value);
    final activeId = await _activeWalletId();
    for (final record in await _readWalletRecords()) {
      final walletId = record['id'];
      if (walletId is! String || walletId == activeId) continue;
      final raw = await _storage.read(key: 'credential_vault_$walletId');
      if (raw == null) continue;
      final configRaw = await _storage.read(key: 'wallet_config_$walletId');
      if (configRaw == null) continue;
      final config = jsonDecode(configRaw);
      final key = config is Map ? config['mnemonicDerivedKey'] : null;
      if (key is! String) continue;
      final decoded = jsonDecode(await _decryptVaultContents(raw, key));
      if (decoded is List && decoded.whereType<Map>().any((credential) =>
          _localCredentialFingerprint(Map<String, dynamic>.from(credential)) == fingerprint)) {
        throw StateError('This credential already belongs to another wallet on this device.');
      }
    }
    all.add(value);
    await write(all);
  }
}

class BrandMark extends StatelessWidget {
  const BrandMark({super.key});
  @override
  Widget build(BuildContext context) => Container(
      width: 42,
      height: 42,
      decoration:
          BoxDecoration(color: teal, borderRadius: BorderRadius.circular(14)),
      child: const Icon(Icons.fingerprint, color: Colors.white, size: 27));
}

class _PageHeader extends StatelessWidget {
  const _PageHeader(
      {required this.eyebrow, required this.title, required this.subtitle});
  final String eyebrow, title, subtitle;
  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(eyebrow,
            style: const TextStyle(
                fontSize: 11,
                color: AppColors.primary,
                letterSpacing: 1.6,
                fontWeight: FontWeight.bold)),
        const SizedBox(height: AppSpacing.sm),
        Text(title,
            style: const TextStyle(
                fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -.6)),
        const SizedBox(height: 7),
        Text(subtitle,
            style:
                const TextStyle(color: AppColors.secondaryText, fontSize: 13))
      ]);
}

class _Notice extends StatelessWidget {
  const _Notice(
      {required this.icon,
      required this.title,
      required this.text,
      this.action});
  final IconData icon;
  final String title, text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
          color: AppColors.surfaceMuted,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(AppRadius.card)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Icon(icon, color: AppColors.primary, size: 20),
          const SizedBox(width: 9),
          Expanded(
              child: Text(title,
                  style: const TextStyle(fontWeight: FontWeight.bold)))
        ]),
        const SizedBox(height: 8),
        Text(text,
            style: const TextStyle(
                fontSize: 13, height: 1.45, color: AppColors.secondaryText)),
        if (action != null) ...[const SizedBox(height: 12), action!]
      ]));
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(
      {required this.icon,
      required this.title,
      required this.text,
      this.action});
  final IconData icon;
  final String title, text;
  final Widget? action;
  @override
  Widget build(BuildContext context) => Padding(
      padding: const EdgeInsets.symmetric(vertical: 34),
      child: Column(children: [
        Icon(icon, size: 42, color: AppColors.primary),
        const SizedBox(height: 12),
        Text(title, style: AppTypography.sectionTitle),
        const SizedBox(height: 6),
        Text(text, textAlign: TextAlign.center, style: AppTypography.bodySmall),
        if (action != null) ...[const SizedBox(height: 16), action!]
      ]));
}

class _CredentialCard extends StatelessWidget {
  const _CredentialCard(
      {required this.data, required this.onTap, required this.onDelete});
  final Map<String, dynamic> data;
  final VoidCallback onTap, onDelete;
  @override
  Widget build(BuildContext context) {
    final issuer = data['issuer'];
    final issuerName = issuer is Map ? issuer['name'] ?? issuer['id'] : issuer;
    final simulated = data['_matchidIssuerStatus'] == 'SIMULATED' ||
        issuerName.toString().toUpperCase().contains('SIMULATED DIGILOCKER');
    return Card(
      margin: const EdgeInsets.only(bottom: 9),
      child: ListTile(
        onTap: onTap,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: const CircleAvatar(
            backgroundColor: AppColors.chip,
            child: Icon(Icons.description_outlined, color: AppColors.primary)),
        title: Text(_credentialTitle(data),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
        subtitle: Padding(
            padding: const EdgeInsets.only(top: 3),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(issuerName?.toString() ?? 'Issuer not specified',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall),
              if (simulated) ...[
                const SizedBox(height: 4),
                const Text('SIMULATED DIGILOCKER: demo data',
                    style: TextStyle(
                        color: AppColors.pendingText,
                        fontSize: 10,
                        fontWeight: FontWeight.w700)),
              ],
              const SizedBox(height: 4),
              const _StatusBadge(
                  label: 'UNVERIFIED',
                  background: AppColors.pendingBackground,
                  foreground: AppColors.pendingText),
            ])),
        isThreeLine: true,
        trailing: IconButton(
            tooltip: 'Delete credential',
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline)),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
              width: 112, child: Text(label, style: AppTypography.bodySmall)),
          Expanded(
              child: Text(value,
                  style: const TextStyle(
                      fontSize: 12, fontWeight: FontWeight.w600))),
        ]),
      );
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge(
      {required this.label,
      required this.background,
      required this.foreground});
  final String label;
  final Color background;
  final Color foreground;
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
            color: background, borderRadius: BorderRadius.circular(20)),
        child: Text(label,
            style: TextStyle(
                fontSize: 9,
                fontWeight: FontWeight.w700,
                color: foreground,
                letterSpacing: .2)),
      );
}

