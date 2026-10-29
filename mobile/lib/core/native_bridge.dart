import 'dart:convert';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'package:ffi/ffi.dart';
import 'package:flutter/services.dart' show rootBundle;
import '../models/proof_payload.dart';
import 'proof_input_validator.dart';

// C-ABI function signatures
typedef FfiFreeStringC = ffi.Void Function(ffi.Pointer<Utf8> ptr);
typedef FfiFreeStringDart = void Function(ffi.Pointer<Utf8> ptr);

// Generic multi-predicate engine C-ABI signatures. The request is a JSON
// document describing predicate mode, thresholds, allowed set and session
// binding; the response is a JSON document with proof + public inputs.
typedef FfiGeneratePredicateProofC = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8> requestJson,
);
typedef FfiGeneratePredicateProofDart = ffi.Pointer<Utf8> Function(
  ffi.Pointer<Utf8> requestJson,
);

typedef FfiVerifyPredicateProofC = ffi.Int32 Function(
  ffi.Pointer<Utf8> proofJson,
  ffi.Pointer<Utf8> verificationKey,
);

typedef FfiVerifyPredicateProofDart = int Function(
  ffi.Pointer<Utf8> proofJson,
  ffi.Pointer<Utf8> verificationKey,
);

/// Native bridge interfacing with Mopro Groth16 native engine via Dart FFI.
class NativeBridge {
  static final NativeBridge _instance = NativeBridge._internal();
  factory NativeBridge() => _instance;
  NativeBridge._internal() {
    _initializeFfi();
  }

  ffi.DynamicLibrary? _dylib;
  FfiGeneratePredicateProofDart? _generatePredicateProofFn;
  FfiVerifyPredicateProofDart? _verifyPredicateProofFn;
  FfiFreeStringDart? _freeStringFn;

  /// The legacy age-only Rust function returns a fixed mock proof. It is
  /// intentionally disabled even when its symbol is present.
  bool get isNativeAvailable => false;

  /// True when the native multi-predicate (generic_verifier) engine is loaded.
  bool get isPredicateNativeAvailable =>
      _generatePredicateProofFn != null &&
      _verifyPredicateProofFn != null &&
      _freeStringFn != null;

  void _initializeFfi() {
    try {
      if (Platform.isAndroid) {
        _dylib = ffi.DynamicLibrary.open('libmopro_bindings.so');
      } else if (Platform.isIOS) {
        _dylib = ffi.DynamicLibrary.process();
      } else if (Platform.isWindows) {
        _dylib = ffi.DynamicLibrary.open('mopro_bindings.dll');
      } else if (Platform.isLinux) {
        _dylib = ffi.DynamicLibrary.open('libmopro_bindings.so');
      } else if (Platform.isMacOS) {
        _dylib = ffi.DynamicLibrary.open('libmopro_bindings.dylib');
      }

      if (_dylib != null) {
        _freeStringFn = _dylib!
            .lookupFunction<FfiFreeStringC, FfiFreeStringDart>(
                'ffi_free_string');

        // Generic proof operations are available only when both proving and
        // pairing-verification symbols exist. No simulation fallback is used.
        try {
          _generatePredicateProofFn = _dylib!.lookupFunction<
              FfiGeneratePredicateProofC,
              FfiGeneratePredicateProofDart>('ffi_generate_generic_proof');
          _verifyPredicateProofFn = _dylib!.lookupFunction<
              FfiVerifyPredicateProofC,
              FfiVerifyPredicateProofDart>('ffi_verify_generic_proof');
        } catch (_) {
          _generatePredicateProofFn = null;
          _verifyPredicateProofFn = null;
        }
      }
    } catch (_) {
      // Native library not yet loaded; proof generation remains unavailable.
      _dylib = null;
    }
  }

  /// Helper to get the verification key from input or load from asset bundle
  Future<String> _getOrLoadVkey(String? providedKey) async {
    if (providedKey != null &&
        providedKey.isNotEmpty &&
        providedKey.trim() != "{}") {
      return providedKey;
    }

    try {
      final vkeyString =
          await rootBundle.loadString('assets/verification_key.json');
      if (vkeyString.isEmpty || vkeyString.trim() == "{}") {
        throw Exception(
            "Invalid or empty verification key found at assets/verification_key.json");
      }
      return vkeyString;
    } catch (e) {
      throw Exception("Failed to load verification key asset: $e");
    }
  }

  /// Generates Groth16 age proof natively on-device.
  Future<ProofPayload> generateAgeProof({
    required int birthYear,
    required String userSecret,
    required int currentYear,
    required int ageLimit,
    required String sessionNonce,
    String issuerReference = 'did:zkmatch:issuer-authority',
  }) async {
    throw UnsupportedError(
        'The legacy age-only proof path is disabled because it is not backed by the generic circuit.');
  }

  /// Generates a Groth16 proof for an arbitrary predicate using the generic
  /// multi-predicate circuit (`generic_verifier.circom`).
  Future<ProofPayload> generatePredicateProof({
    required int predicateMode,
    required int attributeValue,
    required String userSecret,
    required int credentialExpiry,
    required int thresholdA,
    required int thresholdB,
    required List<int> allowedSet,
    required int currentTimestamp,
    required String sessionNonce,
    required String issuerReference,
    required String predicateType,
    required String predicateClaim,
  }) async {
    ProofInputValidator.validate(
      predicateMode: predicateMode,
      attributeValue: attributeValue,
      userSecret: userSecret,
      credentialExpiry: credentialExpiry,
      thresholdA: thresholdA,
      thresholdB: thresholdB,
      allowedSet: allowedSet,
      currentTimestamp: currentTimestamp,
      sessionNonce: sessionNonce,
    );

    if (isPredicateNativeAvailable) {
      final requestPtr = jsonEncode({
        'predicate_mode': predicateMode,
        'attribute_value': attributeValue,
        'user_secret': userSecret,
        'credential_expiry': credentialExpiry,
        'threshold_a': thresholdA,
        'threshold_b': thresholdB,
        'allowed_set': allowedSet,
        'current_timestamp': currentTimestamp,
        'session_nonce': sessionNonce,
        'issuer_reference': issuerReference,
      }).toNativeUtf8();

      try {
        final resultPtr = _generatePredicateProofFn!(requestPtr);
        final resultStr = resultPtr.toDartString();
        _freeStringFn!(resultPtr);

        final parsed = jsonDecode(resultStr) as Map<String, dynamic>;
        if (parsed.containsKey('error')) {
          throw Exception('Mopro Engine Error: ${parsed['error']}');
        }

        final payload = ProofPayload(
          proof: Groth16Proof.fromJson(parsed['proof'] as Map<String, dynamic>),
          publicInputs: List<String>.from(parsed['public_inputs'] ?? []),
          sessionNonce: sessionNonce,
          issuerReference: issuerReference,
          predicateType: predicateType,
          predicateClaim: predicateClaim,
          timestamp: DateTime.now().millisecondsSinceEpoch,
        );
        if (!await verifyPredicateProof(payload: payload)) {
          throw StateError(
              'The generated proof failed local verification. It was not accepted.');
        }
        return payload;
      } finally {
        calloc.free(requestPtr);
      }
    }

    throw StateError(
        'Native generic prover is unavailable; a cryptographic proof cannot be generated.');
  }

  /// Verifies a generic multi-predicate Groth16 proof on-device.
  /// Explicitly loads `assets/verification_key.json` when [verificationKey] is omitted.
  Future<bool> verifyPredicateProof({
    required ProofPayload payload,
    String? verificationKey,
  }) async {
    final vkey = await _getOrLoadVkey(verificationKey);

    if (_verifyPredicateProofFn != null) {
      final proofJsonPtr = payload.toRawJson().toNativeUtf8();
      final vkeyPtr = vkey.toNativeUtf8();

      try {
        final code = _verifyPredicateProofFn!(proofJsonPtr, vkeyPtr);
        return code == 1;
      } finally {
        calloc.free(proofJsonPtr);
        calloc.free(vkeyPtr);
      }
    }

    // A structurally plausible payload is not a proof. Fail closed if the
    // native pairing verifier is unavailable.
    return false;
  }

  /// Verifies a Groth16 age proof natively on-device.
  /// Explicitly loads `assets/verification_key.json` when [verificationKey] is omitted.
  Future<bool> verifyAgeProof({
    required ProofPayload payload,
    String? verificationKey,
  }) async =>
      false;
}
