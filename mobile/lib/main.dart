import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:share_plus/share_plus.dart';

import 'core/theme/app_theme.dart';
import 'data/vault_backup_service.dart';
import 'data/vault_repository.dart';
import 'data/secure_key_value_store.dart';
import 'features/onboarding/presentation/face_capture_screen.dart';
import 'features/onboarding/data/otp_service.dart';
import 'features/onboarding/presentation/phone_otp_screen.dart';
import 'features/verification/credential_verification_service.dart';

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
  const MatchIdApp({super.key, this.vaultRepository});

  final VaultRepository? vaultRepository;

  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'MatchID',
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: MatchHome(vaultRepository: vaultRepository),
      );
}

class MatchHome extends StatefulWidget {
  const MatchHome({super.key, this.vaultRepository});

  final VaultRepository? vaultRepository;

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
  int? selectedProofCredential;
  String? selectedProofClaim;
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
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Name your wallet'),
        content: TextField(
          controller: controller,
          maxLength: 32,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(hintText: 'e.g. Personal wallet'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create wallet'),
          ),
        ],
      ),
    );
    await WidgetsBinding.instance.endOfFrame;
    controller.dispose();
    if (name == null) return;
    if (name.isEmpty) {
      _snack('Enter a name for your wallet.');
      return;
    }
    try {
      await vault.createWallet(name);
      await vault.addActivity('Wallet created', 'Local wallet · $name');
      final events = await vault.readActivity();
      if (!mounted) return;
      setState(() {
        walletName = name;
        walletCreated = true;
        unlocked = true;
        activity = events;
        backupSkipped = false;
        backupCompleted = false;
      });
      _refreshVaultLock();
      await _showBackupPhase();
    } catch (e) {
      if (mounted) _snack('Could not create wallet: ${_errorText(e)}');
    }
  }

  Future<void> _showRestoreInfo() => _restoreFromBackup();

  Future<void> _showBackupPhase() async {
    while (mounted && !backupCompleted && !backupSkipped) {
      if (!mounted) return;
      final action = await showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => AlertDialog(
          title: const Text('Back up your wallet'),
          content: const Text(
            'Create an encrypted backup file protected by a passphrase you choose. Keep both the file and passphrase somewhere safe. If this device is lost, the wallet cannot be recovered without them.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, 'skip'),
              child: const Text('Skip for now'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, 'backup'),
              child: const Text('Create encrypted backup'),
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
          otpService: HttpOtpService.fromDartDefine(),
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
    await _showUnavailableScreen(
      'Connect DigiLocker',
      'Credential import is restricted to DigiLocker. This app build needs an approved requester client ID, redirect URI, scopes, and current API Setu integration details before it can connect. No credential was imported.',
    );
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
      _provePage(),
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
                icon: Icon(Icons.verified_user_outlined), label: 'Prove'),
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
          const Expanded(
              child: Text('My credentials',
                  style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -.4))),
          IconButton.filledTonal(
              tooltip: 'Connect DigiLocker',
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
                  'Connect DigiLocker to retrieve your issued credentials. This app does not accept credential JSON files or QR payloads.',
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
              title: 'Issuer checks unavailable',
              text:
                  'Imported credentials are stored securely, but their signatures and revocation status are not verified by this build.'),
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
              const _Notice(
                  icon: Icons.gpp_maybe_outlined,
                  title: 'Not verified',
                  text:
                      'The file format was checked, but issuer signature and revocation status were not.'),
            ]),
      )),
    );
  }

  Widget _activityPage() =>
      ListView(padding: const EdgeInsets.all(20), children: [
        _PageHeader(
            eyebrow: 'ON THIS DEVICE',
            title: 'Activity',
            subtitle: 'Recent proof and verification events.'),
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
          title: const Text('Create encrypted backup'),
          subtitle: Text(backupCompleted
              ? 'Create a fresh copy of this wallet'
              : 'Protect this wallet with a passphrase'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _createBackup,
        )),
        const SizedBox(height: 8),
        Card(
            child: ListTile(
          leading: const Icon(Icons.restore, color: AppColors.primary),
          title: const Text('Restore from backup'),
          subtitle: const Text('Restore an encrypted wallet backup file'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _restoreFromBackup,
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
          leading: const Icon(Icons.speed, color: AppColors.primary),
          title: const Text('Benchmark'),
          subtitle: const Text('Proof runtime measurement'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showUnavailableScreen(
            'Benchmark',
            'Benchmark results require the production proof circuit and native prover, which are not present in this build.',
          ),
        )),
        const SizedBox(height: 12),
        Card(
            child: ListTile(
          leading: const Icon(Icons.compare_arrows, color: AppColors.primary),
          title: const Text('Comparison mode'),
          subtitle: const Text('Compare proof configurations'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _showUnavailableScreen(
            'Comparison mode',
            'There are no configured proof systems to compare. Add audited circuit and prover builds before collecting comparison results.',
          ),
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
                'Credentials are kept in platform-protected storage. This build does not create a recovery phrase or sync wallet data.'),
      ]);

  Future<void> _showUnavailableScreen(String title, String message) =>
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Close'),
            ),
          ],
        ),
      );

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

  List<String> _claimsFor(Map<String, dynamic> credential) {
    final subject = credential['credentialSubject'];
    if (subject is Map) {
      return subject.keys
          .where((key) => key.toString() != 'id')
          .map((key) => key.toString())
          .toList();
    }
    return credential.keys
        .where((key) => !const {
              'id',
              'issuer',
              'proof',
              'type',
              '@context',
              'credentialSubject'
            }.contains(key))
        .map((key) => key.toString())
        .toList();
  }

  Future<void> _reviewProofConsent() async {
    final index = selectedProofCredential;
    if (index == null ||
        index >= credentials.length ||
        selectedProofClaim == null) {
      return;
    }
    final credential = credentials[index];
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Review sharing consent'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Credential: ${_credentialTitle(credential)}'),
            const SizedBox(height: 6),
            Text('Requested claim: $selectedProofClaim'),
            const SizedBox(height: 14),
            const _Notice(
              icon: Icons.gpp_maybe_outlined,
              title: 'Cannot share yet',
              text:
                  'The credential is unverified and this build has no production proof generator. Nothing will be disclosed.',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      await _showUnavailableScreen(
        'Proof unavailable',
        'Consent was reviewed, but no proof was generated or shared. Configure an issuer trust registry, circuit proving key, and audited native Mopro library to continue.',
      );
    }
  }

  Widget _provePage() => ListView(padding: const EdgeInsets.all(22), children: [
        const _PageHeader(
            eyebrow: 'SHARE A CLAIM',
            title: 'Prove a claim',
            subtitle: 'Choose a credential and the minimum claim to share.'),
        const SizedBox(height: 18),
        if (!unlocked)
          _Notice(
            icon: Icons.lock_outline,
            title: 'Unlock your wallet',
            text: 'Unlock to select one of your stored credentials.',
            action: FilledButton(
              onPressed: _unlock,
              child: const Text('Unlock wallet'),
            ),
          )
        else if (credentials.isEmpty)
          _EmptyState(
            icon: Icons.description_outlined,
            title: 'No credentials available',
            text: 'Connect DigiLocker before choosing a claim.',
            action: OutlinedButton.icon(
              onPressed: () => setState(() => tab = 0),
              icon: const Icon(Icons.add),
              label: const Text('Go to wallet'),
            ),
          )
        else ...[
          const Text('1. Choose a credential',
              style: AppTypography.sectionTitle),
          const SizedBox(height: 8),
          ...credentials.asMap().entries.map((entry) => Card(
                child: ListTile(
                  onTap: () => setState(() {
                    selectedProofCredential = entry.key;
                    selectedProofClaim = null;
                  }),
                  leading: Icon(
                    selectedProofCredential == entry.key
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                    color: AppColors.primary,
                  ),
                  title: Text(_credentialTitle(entry.value)),
                  subtitle: const Text('Unverified credential'),
                ),
              )),
          if (selectedProofCredential != null &&
              selectedProofCredential! < credentials.length) ...[
            const SizedBox(height: 14),
            const Text('2. Choose a claim', style: AppTypography.sectionTitle),
            const SizedBox(height: 8),
            ..._claimsFor(credentials[selectedProofCredential!])
                .map((claim) => ListTile(
                      onTap: () => setState(() => selectedProofClaim = claim),
                      leading: Icon(
                        selectedProofClaim == claim
                            ? Icons.radio_button_checked
                            : Icons.radio_button_unchecked,
                        color: AppColors.primary,
                      ),
                      title: Text(claim),
                    )),
            if (_claimsFor(credentials[selectedProofCredential!]).isEmpty)
              const Text('This credential has no selectable claims.'),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed:
                  selectedProofClaim == null ? null : _reviewProofConsent,
              icon: const Icon(Icons.visibility_outlined),
              label: const Text('Review consent'),
            ),
          ],
        ],
        const SizedBox(height: 18),
        const _Notice(
            icon: Icons.lock_outline,
            title: 'Proof generation is disabled',
            text:
                'The app has no production circuit proving key, audited native Mopro library, or trusted policy configuration. It will not create or display a proof payload.'),
        const SizedBox(height: 18),
        const _SetupStep(
            number: '01',
            title: 'Trusted policy registry',
            detail:
                'Install authenticated policy definitions and issuer trust data.'),
        const _SetupStep(
            number: '02',
            title: 'Audited proof artifacts',
            detail:
                'Build and audit the circuit-specific key and native proving libraries.'),
        const _SetupStep(
            number: '03',
            title: 'Verification integration',
            detail:
                'Validate proof, issuer, expiry, policy binding, and replay state on device.'),
        const SizedBox(height: 18),
        FilledButton.icon(
            onPressed: null,
            icon: const Icon(Icons.lock_outline),
            label: const Text('Proof generation not configured')),
      ]);

  Widget _verifyPage() => VerifyPage(onActivity: _recordActivity);
}

String _formatActivityTime(String? value) {
  final date = value == null ? null : DateTime.tryParse(value)?.toLocal();
  if (date == null) return '';
  final hour = date.hour.toString().padLeft(2, '0');
  final minute = date.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

class VerifyPage extends StatefulWidget {
  const VerifyPage({super.key, required this.onActivity});
  final Future<void> Function(String title, String detail) onActivity;
  @override
  State<VerifyPage> createState() => _VerifyPageState();
}

class _VerifyPageState extends State<VerifyPage> {
  final verifier = CredentialVerificationService.fromDartDefine();
  bool scanning = false;
  bool verifying = false;
  CredentialVerificationResult? result;

  Future<void> _handleScan(BarcodeCapture capture) async {
    if (verifying) return;
    final value =
        capture.barcodes.isEmpty ? null : capture.barcodes.first.rawValue;
    if (value == null || value.isEmpty) return;
    setState(() {
      scanning = false;
      verifying = true;
      result = null;
    });
    final checked = await verifier.verifyQr(value);
    if (!mounted) return;
    setState(() {
      verifying = false;
      result = checked;
    });
    await widget.onActivity(
      checked.verified ? 'Credential verified' : 'Credential rejected',
      checked.verified
          ? '${checked.credentialType ?? 'Credential'} · issuer signature and expiry valid'
          : 'Rejected · ${checked.status.name}',
    );
  }

  @override
  Widget build(BuildContext context) =>
      ListView(padding: const EdgeInsets.all(22), children: [
        const _PageHeader(
            eyebrow: 'CREDENTIAL VERIFICATION',
            title: 'Scan to verify',
            subtitle:
                'Scan an issuer-signed credential QR. The verifier checks its signature and expiry against its trusted issuer registry.'),
        const SizedBox(height: 16),
        const _Notice(
          icon: Icons.security_outlined,
          title: 'Issuer trust is required',
          text:
              'Configure CREDENTIAL_TRUST_REGISTRY_JSON with issuer public keys before accepting credentials. Unknown issuers and unsupported QR formats are rejected.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: scanning || verifying
              ? null
              : () => setState(() {
                    scanning = true;
                    result = null;
                  }),
          icon: const Icon(Icons.qr_code_scanner),
          label: const Text('Scan credential QR'),
        ),
        if (verifying) ...[
          const SizedBox(height: 18),
          const LinearProgressIndicator(),
          const SizedBox(height: 12),
          const Text('Checking signature, issuer trust, and expiry…'),
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
        if (result != null) ...[
          const SizedBox(height: 16),
          if (result!.verified)
            _Notice(
              icon: Icons.verified_user_outlined,
              title: 'Credential signature verified',
              text:
                  '${result!.credentialType} · ${result!.issuer}\nExpires ${result!.expiresAt!.toLocal()}\n\n${result!.message}',
            )
          else
            _Notice(
              icon: Icons.gpp_bad_outlined,
              title: 'Verification failed',
              text: result!.message,
            ),
          const SizedBox(height: 8),
          const _Notice(
            icon: Icons.info_outline,
            title: 'Verification scope',
            text:
                'A valid issuer signature does not prove the QR presenter is the credential subject. Revocation and DigiLocker document status are not checked in this offline flow.',
          ),
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
    await _storage.write(key: _key, value: encodedCredentials);
    await _storage.write(
        key: _walletConfigKey, value: jsonEncode(normalizedConfig));
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
    final raw = await _storage.read(key: _walletConfigKey);
    if (raw == null) return null;
    final decoded = jsonDecode(raw);
    if (decoded is! Map) {
      throw const FormatException('The saved wallet profile is invalid.');
    }
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<void> createWallet(String name) => _storage.write(
        key: _walletConfigKey,
        value: jsonEncode({
          'name': name,
          'createdAt': DateTime.now().toUtc().toIso8601String(),
        }),
      );

  @override
  Future<void> wipe() async {
    await _storage.delete(key: _key);
    await _storage.delete(key: _walletConfigKey);
    await _storage.delete(key: _activityKey);
    await _storage.delete(key: _backupSkippedKey);
    await _storage.delete(key: _backupCompletedKey);
    await _storage.delete(key: _verifiedPhoneKey);
  }

  @override
  Future<List<Map<String, dynamic>>> read() async {
    final raw = await _storage.read(key: _key);
    if (raw == null) return [];
    final value = jsonDecode(raw);
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
    await _storage.write(key: _key, value: encoded);
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

class _SetupStep extends StatelessWidget {
  const _SetupStep(
      {required this.number, required this.title, required this.detail});
  final String number, title, detail;
  @override
  Widget build(BuildContext context) => Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
          color: Colors.white, borderRadius: BorderRadius.circular(16)),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 34,
          height: 34,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: const Color(0xffe7f2ef),
              borderRadius: BorderRadius.circular(11)),
          child: Text(number,
              style: const TextStyle(
                  color: teal, fontWeight: FontWeight.bold, fontSize: 12)),
        ),
        const SizedBox(width: 12),
        Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(detail,
              style: const TextStyle(
                  color: Colors.black54, height: 1.4, fontSize: 13))
        ]))
      ]));
}
