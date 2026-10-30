/// Demo OTP verifier — always accepts the fixed code `1234`.
///
/// No SMS is sent. Resend is a UI-only timer (no-op).
class DemoOtp {
  static const demoCode = '1234';
  static const codeLength = 4;
  static const resendSeconds = 30;

  /// Returns true only when [code] equals the demo OTP.
  static bool verify(String code) => code.trim() == demoCode;

  /// True when [code] is exactly four digits (may still be wrong).
  static bool isComplete(String code) =>
      RegExp(r'^\d{4}$').hasMatch(code.trim());

  /// Null when the entered code looks ready; otherwise a hint.
  static String? validateInput(String code) {
    final trimmed = code.trim();
    if (trimmed.isEmpty) return 'Enter the 4-digit demo OTP.';
    if (!RegExp(r'^\d+$').hasMatch(trimmed)) {
      return 'OTP must be digits only.';
    }
    if (trimmed.length < codeLength) {
      return 'Enter all $codeLength digits.';
    }
    if (trimmed.length > codeLength) {
      return 'OTP must be exactly $codeLength digits.';
    }
    return null;
  }
}
