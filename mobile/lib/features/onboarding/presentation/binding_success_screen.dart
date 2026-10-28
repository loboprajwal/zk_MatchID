import 'package:flutter/material.dart';

class BindingSuccessScreen extends StatelessWidget {
  const BindingSuccessScreen({super.key, required this.phoneStoredEncrypted});
  final bool phoneStoredEncrypted;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Verification steps complete')),
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(24), children: [
            const Icon(Icons.verified_outlined, size: 64),
            const SizedBox(height: 20),
            Text('Face and number verified',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 12),
            const Text(
                'DEMO MODE: The phone code is simulated. This step detected the ordered face poses only; no biometric identity match or face template was produced.',
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            Text(
                phoneStoredEncrypted
                    ? 'Stored locally, encrypted\nThe verified phone number is in device secure storage.'
                    : 'Local encrypted storage could not be confirmed.',
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            FilledButton(
                onPressed: phoneStoredEncrypted
                    ? () => Navigator.of(context).pop(true)
                    : null,
                child: const Text('Continue')),
          ]),
        ),
      );
}
