/// Demo country dial codes for the UPI wallet-creation phone step.
class CountryDialCode {
  final String iso;
  final String name;
  final String dialCode;
  final int minNationalDigits;
  final int maxNationalDigits;

  const CountryDialCode({
    required this.iso,
    required this.name,
    required this.dialCode,
    required this.minNationalDigits,
    required this.maxNationalDigits,
  });

  String get label => '$name ($dialCode)';
}

const kDemoCountryCodes = <CountryDialCode>[
  CountryDialCode(
    iso: 'IN',
    name: 'India',
    dialCode: '+91',
    minNationalDigits: 10,
    maxNationalDigits: 10,
  ),
  CountryDialCode(
    iso: 'US',
    name: 'United States',
    dialCode: '+1',
    minNationalDigits: 10,
    maxNationalDigits: 10,
  ),
  CountryDialCode(
    iso: 'GB',
    name: 'United Kingdom',
    dialCode: '+44',
    minNationalDigits: 10,
    maxNationalDigits: 10,
  ),
  CountryDialCode(
    iso: 'AE',
    name: 'UAE',
    dialCode: '+971',
    minNationalDigits: 9,
    maxNationalDigits: 9,
  ),
  CountryDialCode(
    iso: 'SG',
    name: 'Singapore',
    dialCode: '+65',
    minNationalDigits: 8,
    maxNationalDigits: 8,
  ),
  CountryDialCode(
    iso: 'AU',
    name: 'Australia',
    dialCode: '+61',
    minNationalDigits: 9,
    maxNationalDigits: 9,
  ),
  CountryDialCode(
    iso: 'DE',
    name: 'Germany',
    dialCode: '+49',
    minNationalDigits: 10,
    maxNationalDigits: 11,
  ),
];

CountryDialCode get kDefaultDemoCountry => kDemoCountryCodes.first; // India +91

/// Pure phone validation used by the demo wizard and unit tests.
class DemoPhoneValidation {
  /// Digits only (no spaces/dashes).
  static String digitsOnly(String raw) =>
      raw.replaceAll(RegExp(r'\D'), '');

  /// Returns null when valid; otherwise a short error message.
  static String? validateNational(
    CountryDialCode country,
    String nationalRaw,
  ) {
    final digits = digitsOnly(nationalRaw);
    if (digits.isEmpty) {
      return 'Enter a phone number.';
    }
    if (digits.length < country.minNationalDigits ||
        digits.length > country.maxNationalDigits) {
      if (country.minNationalDigits == country.maxNationalDigits) {
        return 'Enter ${country.minNationalDigits} digits for ${country.name}.';
      }
      return 'Enter ${country.minNationalDigits}–${country.maxNationalDigits} digits for ${country.name}.';
    }
    return null;
  }

  /// E.164-style string, e.g. +919876543210.
  static String toE164(CountryDialCode country, String nationalRaw) {
    final digits = digitsOnly(nationalRaw);
    return '${country.dialCode}$digits';
  }

  static bool isValidE164(String e164) =>
      RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(e164);
}
