import 'package:flutter/material.dart';

/// Renders the cryptographic verification outcome card.
class VerificationBadge extends StatelessWidget {
  final bool isSuccess;
  final String title;
  final String message;
  final Map<String, String>? details;
  final VoidCallback onReset;

  const VerificationBadge({
    super.key,
    required this.isSuccess,
    required this.title,
    required this.message,
    this.details,
    required this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = isSuccess ? Colors.green.shade700 : Colors.red.shade700;
    final bgColor = isSuccess ? Colors.green.shade50 : Colors.red.shade50;

    return Card(
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: primaryColor.withValues(alpha: 0.3), width: 2),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isSuccess ? Icons.verified_user : Icons.gpp_bad,
              color: primaryColor,
              size: 64,
            ),
            const SizedBox(height: 16),
            Text(
              title,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: primaryColor,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              message,
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey.shade800,
              ),
              textAlign: TextAlign.center,
            ),
            if (details != null && details!.isNotEmpty) ...[
              const Divider(height: 32),
              ...details!.entries.map(
                (entry) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        entry.key,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                      Flexible(
                        child: Text(
                          entry.value,
                          style: const TextStyle(
                            fontSize: 12,
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.refresh),
              label: const Text('New Verification'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
