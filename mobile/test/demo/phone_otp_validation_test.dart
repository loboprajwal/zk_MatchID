import 'package:flutter_test/flutter_test.dart';
import 'package:zk_match_id/demo/country_codes.dart';
import 'package:zk_match_id/demo/demo_otp.dart';

void main() {
  group('DemoPhoneValidation', () {
    test('accepts a valid Indian 10-digit national number', () {
      final india = kDemoCountryCodes.firstWhere((c) => c.iso == 'IN');
      expect(DemoPhoneValidation.validateNational(india, '9876543210'), isNull);
      expect(
        DemoPhoneValidation.toE164(india, '98765 43210'),
        '+919876543210',
      );
      expect(DemoPhoneValidation.isValidE164('+919876543210'), isTrue);
    });

    test('rejects too-short and non-digit national numbers', () {
      final india = kDefaultDemoCountry;
      expect(
        DemoPhoneValidation.validateNational(india, '12345'),
        contains('10 digits'),
      );
      expect(
        DemoPhoneValidation.validateNational(india, ''),
        contains('Enter a phone number'),
      );
    });

    test('US dial code builds +1 E.164', () {
      final us = kDemoCountryCodes.firstWhere((c) => c.iso == 'US');
      expect(DemoPhoneValidation.validateNational(us, '2125551234'), isNull);
      expect(DemoPhoneValidation.toE164(us, '2125551234'), '+12125551234');
    });
  });

  group('DemoOtp', () {
    test('verifies only the fixed demo code 1234', () {
      expect(DemoOtp.verify('1234'), isTrue);
      expect(DemoOtp.verify('0000'), isFalse);
      expect(DemoOtp.verify('12345'), isFalse);
      expect(DemoOtp.verify(''), isFalse);
    });

    test('validateInput requires exactly four digits', () {
      expect(DemoOtp.validateInput('12'), contains('4 digits'));
      expect(DemoOtp.validateInput('abcd'), contains('digits'));
      expect(DemoOtp.validateInput('1234'), isNull);
      expect(DemoOtp.isComplete('1234'), isTrue);
      expect(DemoOtp.isComplete('12'), isFalse);
    });
  });
}
