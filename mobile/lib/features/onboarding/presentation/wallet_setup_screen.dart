import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

class WalletSetupResult {
  const WalletSetupResult(
      {required this.name, required this.deviceLockEnabled});
  final String name;
  final bool deviceLockEnabled;
}

abstract interface class DeviceAuthService {
  Future<bool> isDeviceSupported();
  Future<bool> authenticate();
}

class LocalDeviceAuthService implements DeviceAuthService {
  LocalDeviceAuthService([LocalAuthentication? auth])
      : _auth = auth ?? LocalAuthentication();
  final LocalAuthentication _auth;

  @override
  Future<bool> isDeviceSupported() => _auth.isDeviceSupported();

  @override
  Future<bool> authenticate() => _auth.authenticate(
        localizedReason: 'Confirm device authentication for this wallet',
        options: const AuthenticationOptions(biometricOnly: false),
      );
}

class WalletSetupScreen extends StatefulWidget {
  const WalletSetupScreen({super.key, this.auth});
  final DeviceAuthService? auth;

  @override
  State<WalletSetupScreen> createState() => _WalletSetupScreenState();
}

class _WalletSetupScreenState extends State<WalletSetupScreen> {
  late final DeviceAuthService _auth;
  final _name = TextEditingController();
  bool _lockEnabled = false;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _auth = widget.auth ?? LocalDeviceAuthService();
  }

  Future<void> _setLock(bool enabled) async {
    if (!enabled) {
      setState(() {
        _lockEnabled = false;
        _error = null;
      });
      return;
    }
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (!await _auth.isDeviceSupported()) {
        setState(() => _error =
            'Device authentication is not supported. You can continue with the lock disabled.');
        return;
      }
      final authenticated = await _auth.authenticate();
      if (mounted && authenticated) setState(() => _lockEnabled = true);
      if (mounted && !authenticated) {
        setState(() => _error =
            'Authentication was cancelled. The device lock remains off.');
      }
    } catch (_) {
      if (mounted) {
        setState(() => _error =
            'Device authentication is unavailable. The lock remains off.');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _continue() {
    final name = _name.text.trim();
    if (name.isEmpty || name.length > 32) {
      setState(
          () => _error = 'Enter a wallet name between 1 and 32 characters.');
      return;
    }
    Navigator.of(context)
        .pop(WalletSetupResult(name: name, deviceLockEnabled: _lockEnabled));
  }

  @override
  void dispose() {
    _name.clear();
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Set up your wallet')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(20), children: [
            const Text('Choose a wallet name and device lock.'),
            const SizedBox(height: 20),
            TextField(
                controller: _name,
                maxLength: 32,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(
                    labelText: 'Wallet name', hintText: 'Personal wallet')),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Require device authentication'),
              subtitle: Text(_lockEnabled
                  ? 'Enabled after successful device authentication.'
                  : 'Off until device authentication succeeds.'),
              value: _lockEnabled,
              onChanged: _busy ? null : _setLock,
            ),
            if (_busy) const Center(child: CircularProgressIndicator()),
            if (_error case final error?)
              Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(error,
                      style: TextStyle(
                          color: Theme.of(context).colorScheme.error))),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: _busy ? null : _continue,
                child: const Text('Continue')),
          ]),
        ),
      );
}
