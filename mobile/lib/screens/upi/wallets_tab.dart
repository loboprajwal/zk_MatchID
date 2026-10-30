import 'package:flutter/material.dart';

import '../../demo/wallet_store.dart';
import 'profile_screen.dart';
import 'wallet_create_wizard.dart';

class WalletsTab extends StatefulWidget {
  const WalletsTab({super.key});

  @override
  State<WalletsTab> createState() => _WalletsTabState();
}

class _WalletsTabState extends State<WalletsTab> {
  final _store = WalletStore.instance;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _store.ensureLoaded();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _create() async {
    final created = await Navigator.of(context).push<DemoWallet>(
      MaterialPageRoute(builder: (_) => const WalletCreateWizard()),
    );
    if (!mounted) return;
    if (created != null) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Created ${created.name}')),
      );
    }
  }

  Future<void> _openProfile(DemoWallet wallet) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ProfileScreen(walletId: wallet.id),
      ),
    );
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final active = _store.activeWallet;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Wallets'),
        actions: [
          IconButton(
            tooltip: 'Reset demo wallets',
            onPressed: () async {
              await _store.resetToSeed();
              setState(() {});
            },
            icon: const Icon(Icons.restart_alt),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.add),
        label: const Text('New wallet'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'UPI-style: each wallet holds its own credentials. New wallets collect demo phone, OTP (1234) and a local face matrix.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
          ),
          const SizedBox(height: 12),
          ..._store.wallets.map((w) {
            final selected = w.id == active?.id;
            final profile = w.profile;
            return Card(
              elevation: selected ? 3 : 0,
              color: selected ? Colors.indigo.shade50 : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(
                  color: selected ? Colors.indigo : Colors.grey.shade300,
                  width: selected ? 2 : 1,
                ),
              ),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () async {
                  await _store.switchWallet(w.id);
                  setState(() {});
                },
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                            selected
                                ? Icons.account_balance_wallet
                                : Icons.account_balance_wallet_outlined,
                            color: Colors.indigo,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              w.name,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          if (selected)
                            Chip(
                              label: const Text('ACTIVE'),
                              visualDensity: VisualDensity.compact,
                              backgroundColor: Colors.indigo.shade100,
                            ),
                        ],
                      ),
                      if (profile.hasPhone) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.phone_iphone, size: 14),
                            const SizedBox(width: 4),
                            Text(
                              profile.phoneE164!,
                              style: const TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 6),
                            if (profile.otpVerified)
                              Icon(Icons.verified,
                                  size: 14, color: Colors.green.shade700),
                            if (profile.hasFace) ...[
                              const SizedBox(width: 6),
                              Icon(Icons.face,
                                  size: 14, color: Colors.indigo.shade400),
                            ],
                          ],
                        ),
                      ],
                      const SizedBox(height: 8),
                      ...w.credentials.map(
                        (c) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Row(
                            children: [
                              const Icon(Icons.description_outlined, size: 16),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${c.type}: ${c.label}',
                                  style: const TextStyle(fontSize: 13),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () => _openProfile(w),
                          icon: const Icon(Icons.person_outline, size: 18),
                          label: const Text('Profile'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
          const SizedBox(height: 80),
        ],
      ),
    );
  }
}
