import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../domain/mnemonic_backup.dart';

const _secureChannel = MethodChannel('zk_matchid/secure_screen');

class MnemonicBackupFlow extends StatefulWidget {
  const MnemonicBackupFlow({super.key, required this.phrase});
  final String phrase;
  @override
  State<MnemonicBackupFlow> createState() => _MnemonicBackupFlowState();
}

class _MnemonicBackupFlowState extends State<MnemonicBackupFlow> {
  final _entries = [TextEditingController(), TextEditingController()];
  final _indices = MnemonicBackup.confirmationIndices();
  Timer? _clipboardTimer;
  bool _confirming = false;

  @override
  void initState() {
    super.initState();
    unawaited(_secureChannel
        .invokeMethod<void>('setSecure', {'enabled': true}).catchError((_) {}));
  }

  @override
  void dispose() {
    _clipboardTimer?.cancel();
    unawaited(_clearPhraseFromClipboard());
    for (final entry in _entries) {
      entry.clear();
      entry.dispose();
    }
    unawaited(_secureChannel.invokeMethod<void>(
        'setSecure', {'enabled': false}).catchError((_) {}));
    super.dispose();
  }

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: widget.phrase));
    _clipboardTimer?.cancel();
    _clipboardTimer =
        Timer(const Duration(seconds: 30), _clearPhraseFromClipboard);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Copied. Clipboard clears after 30 seconds.')));
    }
  }

  Future<void> _clearPhraseFromClipboard() async {
    try {
      final current = await Clipboard.getData(Clipboard.kTextPlain);
      if (current?.text == widget.phrase) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    } catch (_) {
      // Clipboard access may be unavailable on some platforms.
    }
  }

  void _finish() {
    if (MnemonicBackup.confirm(
        widget.phrase, _indices, _entries.map((e) => e.text).toList())) {
      Navigator.pop(context, true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Those words do not match. Try again.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final words = widget.phrase.split(' ');
    return Scaffold(
      appBar: AppBar(
          title: Text(
              _confirming ? 'Confirm recovery phrase' : 'Back up your wallet')),
      body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
        Text(
            _confirming
                ? 'Enter the requested words'
                : 'Write down these 12 words in order',
            style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 12),
        Text(_confirming
            ? 'This phrase derives your wallet key. Keep it private.'
            : 'Anyone with this phrase can restore and access this wallet. Keep it private and offline.'),
        if (!_confirming) ...[
          const SizedBox(height: 24),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (var i = 0; i < words.length; i++)
              Chip(label: Text('${i + 1}. ${words[i]}'))
          ]),
          const SizedBox(height: 18),
          OutlinedButton.icon(
              onPressed: _copy,
              icon: const Icon(Icons.copy),
              label: const Text('Copy phrase (auto-clears in 30s)')),
          const SizedBox(height: 12),
          FilledButton(
              onPressed: () => setState(() => _confirming = true),
              child: const Text('I saved my phrase')),
        ] else ...[
          const SizedBox(height: 20),
          for (var i = 0; i < 2; i++)
            TextField(
                controller: _entries[i],
                decoration:
                    InputDecoration(labelText: 'Word ${_indices[i] + 1}')),
          const SizedBox(height: 16),
          FilledButton(onPressed: _finish, child: const Text('Confirm')),
        ],
      ])),
    );
  }
}

class MnemonicRestoreScreen extends StatefulWidget {
  const MnemonicRestoreScreen({super.key});

  @override
  State<MnemonicRestoreScreen> createState() => _MnemonicRestoreScreenState();
}

class _MnemonicRestoreScreenState extends State<MnemonicRestoreScreen> {
  final _phrase = TextEditingController();
  String? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_secureChannel
        .invokeMethod<void>('setSecure', {'enabled': true}).catchError((_) {}));
  }

  void _restore() {
    final normalized = MnemonicBackup.normalize(_phrase.text);
    if (normalized.split(' ').length != 12 ||
        !MnemonicBackup.isValid(normalized)) {
      setState(() => _error =
          'Enter the original 12-word BIP-39 phrase in the correct order.');
      return;
    }
    Navigator.of(context).pop(normalized);
  }

  @override
  void dispose() {
    _phrase.clear();
    _phrase.dispose();
    unawaited(_secureChannel.invokeMethod<void>(
        'setSecure', {'enabled': false}).catchError((_) {}));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Restore with recovery phrase')),
        body: SafeArea(
            child: ListView(padding: const EdgeInsets.all(24), children: [
          const Text(
              'Enter your 12-word BIP-39 phrase in order. The phrase is checked on this device and is not saved.'),
          const SizedBox(height: 18),
          TextField(
            controller: _phrase,
            minLines: 3,
            maxLines: 5,
            autocorrect: false,
            enableSuggestions: false,
            textCapitalization: TextCapitalization.none,
            decoration: InputDecoration(
                labelText: 'Recovery phrase', errorText: _error),
          ),
          const SizedBox(height: 16),
          FilledButton(
              onPressed: _restore, child: const Text('Restore wallet')),
        ])),
      );
}
