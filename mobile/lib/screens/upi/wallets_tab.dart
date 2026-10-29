import 'package:flutter/material.dart';

import '../../demo/wallet_store.dart';

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
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create wallet'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'Wallet name',
            hintText: 'e.g. Travel wallet',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Create'),
          ),
        ],
      ),
    );
    if (name == null) return;
    await _store.createWallet(name);
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
            'UPI-style: each wallet holds its own credentials. Switch, then Prove.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.grey.shade700,
                ),
          ),
          const SizedBox(height: 12),
          ..._store.wallets.map((w) {
            final selected = w.id == active?.id;
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
