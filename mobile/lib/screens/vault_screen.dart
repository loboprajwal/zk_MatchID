import 'package:flutter/material.dart';
import '../core/vault_service.dart';
import '../models/verifiable_credential.dart';

class VaultScreen extends StatefulWidget {
  const VaultScreen({super.key});

  @override
  State<VaultScreen> createState() => _VaultScreenState();
}

class _VaultScreenState extends State<VaultScreen> {
  final VaultService _vaultService = VaultService();
  String _dob = '';
  int _birthYear = 2000;
  String _secretKey = '';
  List<VerifiableCredential> _credentials = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadVaultData();
  }

  Future<void> _loadVaultData() async {
    await _vaultService.initializeDefaultIdentity();
    final dob = await _vaultService.getDobString();
    final year = await _vaultService.getBirthYear();
    final secret = await _vaultService.getUserSecretKey();
    final creds = await _vaultService.getCredentials();

    setState(() {
      _dob = dob;
      _birthYear = year;
      _secretKey = secret;
      _credentials = creds;
      _isLoading = false;
    });
  }

  Future<void> _editDob() async {
    final controller = TextEditingController(text: _dob);
    final selected = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Update Vault Date of Birth'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'YYYY-MM-DD',
            hintText: 'e.g. 2000-01-01',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (selected != null && selected.isNotEmpty) {
      final parts = selected.split('-');
      final year = int.tryParse(parts.first) ?? 2000;
      await _vaultService.updateIdentity(dobString: selected, birthYear: year);
      await _loadVaultData();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Local Identity Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadVaultData,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Card(
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    child: Padding(
                      padding: const EdgeInsets.all(20),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.indigo.shade50,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(Icons.fingerprint,
                                size: 40, color: Colors.indigo.shade700),
                          ),
                          const SizedBox(width: 16),
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Biometric KeyStore Active',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'Hardware-encrypted storage for Verifiable Credentials & ZK keys',
                                  style: TextStyle(
                                      fontSize: 12, color: Colors.grey),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'VERIFIABLE CREDENTIALS (FROM TRUSTED ISSUERS)',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  if (_credentials.isEmpty) ...[
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          'No credentials found.',
                          style: TextStyle(color: Colors.grey.shade600),
                        ),
                      ),
                    ),
                  ] else ...[
                    ..._credentials.map((vc) => Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12)),
                          child: ExpansionTile(
                            leading: Icon(
                              vc.type.contains('NationalIdentityCredential')
                                  ? Icons.account_box
                                  : Icons.school,
                              color: Colors.indigo,
                              size: 32,
                            ),
                            title: Text(
                              vc.type.last,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              'Issuer: ${vc.issuerName}',
                              style: TextStyle(
                                  fontSize: 12, color: Colors.grey.shade700),
                            ),
                            children: [
                              Padding(
                                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Divider(),
                                    Row(
                                      children: [
                                        const Icon(Icons.verified,
                                            size: 16, color: Colors.green),
                                        const SizedBox(width: 6),
                                        Text(
                                          'Cryptographically Signed (${vc.signatureType})',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.green.shade800,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Issuer DID: ${vc.issuerId}',
                                      style: const TextStyle(
                                          fontSize: 11, fontFamily: 'monospace'),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Birth Year: ${vc.birthYear}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Valid Until: ${vc.expirationDate.split('T').first}',
                                      style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                  const SizedBox(height: 16),
                  const Text(
                    'IDENTITY VAULT SECRETS',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.1,
                      color: Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.cake, color: Colors.indigo),
                      title: const Text('Date of Birth (Active Subject)'),
                      subtitle: Text('$_dob (Year: $_birthYear)'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit, size: 20),
                        onPressed: _editDob,
                      ),
                    ),
                  ),
                  Card(
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    child: ListTile(
                      leading: const Icon(Icons.key, color: Colors.indigo),
                      title: const Text('User Secret Key (ZK Seed)'),
                      subtitle: Text(
                        _secretKey,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontFamily: 'monospace'),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.amber.shade300),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(Icons.shield_outlined,
                            color: Colors.amber.shade800),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Text(
                            'Zero-Knowledge Guarantee: Raw credential attributes and signatures never leave your device. The verifier only evaluates zero-knowledge proofs.',
                            style: TextStyle(fontSize: 13, height: 1.4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
