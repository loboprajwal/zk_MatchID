import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../demo/demo_proof_service.dart';
import '../../demo/predicates.dart';
import '../../demo/wallet_store.dart';
import '../../widgets/qr_display.dart';

class ProveTab extends StatefulWidget {
  const ProveTab({super.key});

  @override
  State<ProveTab> createState() => _ProveTabState();
}

class _ProveTabState extends State<ProveTab> {
  final _store = WalletStore.instance;
  final _proofs = DemoProofService.instance;
  bool _loading = true;
  DemoPredicate? _selected;
  String? _encoded;
  String? _kindLabel;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    await _store.ensureLoaded();
    await _proofs.ensureCatalogLoaded();
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _consentAndProve() async {
    final wallet = _store.activeWallet;
    final pred = _selected;
    if (wallet == null || pred == null) return;

    final accepted = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.shade400,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text('Consent', style: Theme.of(ctx).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                'Wallet: ${wallet.name}',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              Text('Predicate: ${pred.label}'),
              const SizedBox(height: 12),
              Text(pred.consentSummary),
              const SizedBox(height: 12),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.amber.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.amber.shade200),
                ),
                child: const Text(
                  'QR never contains raw PII (no DOB, Aadhaar, address, or name). '
                  'It carries a ZK proof (or signed demo fallback), a nonce, and a 5-minute expiry.',
                  style: TextStyle(fontSize: 13),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: const Text('Deny'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      child: const Text('Allow & generate QR'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );

    if (accepted != true) return;
    setState(() => _busy = true);
    try {
      final result = await _proofs.buildProofQr(wallet: wallet, predicate: pred);
      if (!mounted) return;
      setState(() {
        _encoded = result.encoded;
        _kindLabel = result.proofKindLabel;
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final wallet = _store.activeWallet;
    return Scaffold(
      appBar: AppBar(title: const Text('Prove (generate QR)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet, color: Colors.indigo),
              title: Text(wallet?.name ?? 'No wallet'),
              subtitle: const Text('Active wallet — switch in Wallets tab'),
            ),
          ),
          const SizedBox(height: 8),
          Text('Pick a predicate', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...kDemoPredicates.map((p) {
            final selected = _selected?.id == p.id;
            return Card(
              color: selected ? Colors.teal.shade50 : null,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: selected ? Colors.teal : Colors.transparent,
                  width: 2,
                ),
              ),
              child: ListTile(
                leading: Icon(
                  selected ? Icons.check_circle : Icons.circle_outlined,
                  color: selected ? Colors.teal : Colors.grey,
                ),
                title: Text(p.label),
                subtitle: Text(p.description),
                onTap: () => setState(() {
                  _selected = p;
                  _encoded = null;
                  _kindLabel = null;
                }),
              ),
            );
          }),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: (_selected == null || _busy || wallet == null)
                ? null
                : _consentAndProve,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                : const Icon(Icons.qr_code_2),
            label: Text(_busy ? 'Generating…' : 'Consent & generate QR'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
            ),
          ),
          if (_encoded != null) ...[
            const SizedBox(height: 20),
            QrDisplay(
              data: _encoded!,
              title: _selected?.label ?? 'Proof QR',
              subtitle: _kindLabel ?? '',
              size: 240,
            ),
            const SizedBox(height: 8),
            Text(
              'Expires in ${DemoProofService.defaultTtlSeconds ~/ 60} minutes · no raw PII',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () async {
                await Clipboard.setData(ClipboardData(text: _encoded!));
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('QR payload copied (for paste-verify)')),
                  );
                }
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy payload'),
            ),
          ],
          const SizedBox(height: 40),
        ],
      ),
    );
  }
}
