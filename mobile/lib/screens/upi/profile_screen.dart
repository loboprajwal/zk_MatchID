import 'dart:io';

import 'package:flutter/material.dart';

import '../../demo/face_template.dart';
import '../../demo/wallet_store.dart';
import 'demo_face_capture_screen.dart';

/// Profile for a demo wallet: phone, OTP badge, face thumbnail, re-capture.
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key, required this.walletId});

  final String walletId;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  DemoWallet? _wallet;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final match = WalletStore.instance.wallets.cast<DemoWallet?>().firstWhere(
          (w) => w!.id == widget.walletId,
          orElse: () => null,
        );
    setState(() => _wallet = match);
  }

  Future<void> _recapture() async {
    final wallet = _wallet;
    if (wallet == null || _busy) return;
    final result = await Navigator.of(context).push<DemoFaceCaptureResult>(
      MaterialPageRoute(builder: (_) => const DemoFaceCaptureScreen()),
    );
    if (!mounted || result == null) return;
    setState(() => _busy = true);
    try {
      final oldPath = wallet.profile.faceImagePath;
      final savedPath = await FaceTemplateStore.persistFaceImage(
        walletId: wallet.id,
        source: result.imageFile,
      );
      try {
        if (result.imageFile.path != savedPath &&
            await result.imageFile.exists()) {
          await result.imageFile.delete();
        }
      } catch (_) {}
      if (oldPath != null && oldPath != savedPath) {
        await FaceTemplateStore.deleteFaceImage(oldPath);
      }
      await WalletStore.instance.updateProfile(
        wallet.id,
        WalletProfile(
          phoneE164: wallet.profile.phoneE164,
          otpVerified: wallet.profile.otpVerified,
          faceImagePath: savedPath,
          faceTemplate: result.template,
          faceCapturedAt: result.capturedAt,
        ),
      );
      _reload();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _formatDate(DateTime? dt) {
    if (dt == null) return 'Not captured';
    // Asia/Calcutta wall clock as stored (device local).
    final local = dt.toLocal();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${local.year}-${two(local.month)}-${two(local.day)} '
        '${two(local.hour)}:${two(local.minute)} (device local)';
  }

  @override
  Widget build(BuildContext context) {
    final wallet = _wallet;
    if (wallet == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Profile')),
        body: const Center(child: Text('Wallet not found')),
      );
    }
    final profile = wallet.profile;
    final facePath = profile.faceImagePath;
    final faceFilePath =
        (facePath != null && facePath.isNotEmpty && File(facePath).existsSync())
            ? facePath
            : null;
    final hasFaceFile = faceFilePath != null;

    return Scaffold(
      appBar: AppBar(title: Text('${wallet.name} · Profile')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.account_balance_wallet, color: Colors.indigo),
              title: Text(wallet.name),
              subtitle: Text('ID: ${wallet.id}'),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Phone (demo)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const Icon(Icons.phone_iphone, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          profile.hasPhone
                              ? profile.phoneE164!
                              : 'No phone on file',
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Chip(
                    avatar: Icon(
                      profile.otpVerified
                          ? Icons.verified
                          : Icons.hourglass_empty,
                      size: 18,
                      color: profile.otpVerified
                          ? Colors.green.shade800
                          : Colors.orange.shade800,
                    ),
                    label: Text(
                      profile.otpVerified ? 'OTP verified' : 'OTP not verified',
                    ),
                    backgroundColor: profile.otpVerified
                        ? Colors.green.shade50
                        : Colors.orange.shade50,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Face matrix (local)',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 12),
                  if (faceFilePath != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 1,
                        child: Image.file(
                          File(faceFilePath),
                          fit: BoxFit.cover,
                        ),
                      ),
                    )
                  else
                    Container(
                      height: 160,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade200,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Text('No face captured yet'),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Captured: ${_formatDate(profile.faceCapturedAt)}',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                  if (profile.faceTemplate != null &&
                      profile.faceTemplate!.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      'Template: ${profile.faceTemplate!.substring(0, profile.faceTemplate!.length.clamp(0, 20))}…',
                      style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                    ),
                  ],
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: _busy ? null : _recapture,
                    icon: _busy
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.camera_front),
                    label: Text(
                      hasFaceFile ? 'Re-capture face' : 'Capture face',
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Face image & template are stored only in this app’s documents folder. Never uploaded.',
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Credentials',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                  const SizedBox(height: 8),
                  ...wallet.credentials.map(
                    (c) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text('• ${c.type}: ${c.label}'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
