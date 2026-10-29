import 'dart:async';
import 'dart:io';
import 'dart:math';
import '../core/native_bridge.dart';
import '../core/qr_codec.dart';
import '../models/benchmark_metric.dart';

/// Automated benchmarking engine running 50 iterations of Groth16 proving and verification.
class BenchmarkRunner {
  final NativeBridge _bridge = NativeBridge();
  bool _isRunning = false;

  bool get isRunning => _isRunning;
  bool get isAvailable => _bridge.isPredicateNativeAvailable;

  /// Runs 50 benchmark cycles and reports progress via callback.
  Future<List<BenchmarkMetric>> runFullBenchmarkSuite({
    int iterations = 50,
    void Function(int current, int total, BenchmarkMetric lastMetric)?
        onProgress,
  }) async {
    if (_isRunning) return [];
    if (!isAvailable) {
      throw StateError(
          'The native generic Mopro engine is unavailable. No benchmark data was generated.');
    }
    _isRunning = true;

    final List<BenchmarkMetric> results = [];
    final currentYear = DateTime.now().year;
    const birthYear = 2000;
    const ageLimit = 18;
    final random = Random.secure();

    try {
      for (int i = 1; i <= iterations; i++) {
        final sessionNonce =
            'bench_${DateTime.now().millisecondsSinceEpoch}_$i';

        final userSecret = List<int>.generate(32, (_) => random.nextInt(256))
            .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
            .join();
        final now = DateTime.now();
        final currentTimestamp = now.millisecondsSinceEpoch ~/ 1000;

        // Witness time is part of the native proof call and is not separately
        // exposed by the current Mopro API.
        final proofWatch = Stopwatch()..start();
        final payload = await _bridge.generatePredicateProof(
          predicateMode: 3,
          attributeValue: birthYear,
          userSecret: userSecret,
          credentialExpiry:
              now.add(const Duration(days: 3650)).millisecondsSinceEpoch ~/
                  1000,
          thresholdA: ageLimit,
          thresholdB: currentYear,
          allowedSet: const [0, 0, 0, 0, 0],
          currentTimestamp: currentTimestamp,
          sessionNonce: sessionNonce,
          issuerReference: 'did:zkmatch:benchmark',
          predicateType: 'age_18',
          predicateClaim: 'Age >= 18',
        );
        proofWatch.stop();
        final proofMs = proofWatch.elapsedMicroseconds / 1000.0;

        // 3. Payload Compression & Sizing
        final rawJson = payload.toRawJson();
        final rawBytes = rawJson.length;
        final compressedBase85 = QrCodec.encode(payload);
        final compressedBytes = compressedBase85.length;

        // 4. Verification Timing
        final verifyWatch = Stopwatch()..start();
        final isValid = await _bridge.verifyPredicateProof(payload: payload);
        verifyWatch.stop();
        if (!isValid) {
          throw StateError(
              'Generated proof failed local pairing verification.');
        }
        final verifyMs = verifyWatch.elapsedMicroseconds / 1000.0;

        // 5. Memory Estimation
        final memoryUsageMb = ProcessInfo.currentRss / (1024 * 1024);

        final metric = BenchmarkMetric(
          iteration: i,
          witnessTimeMs: null,
          proofTimeMs: proofMs,
          verifyTimeMs: verifyMs,
          rawPayloadBytes: rawBytes,
          compressedPayloadBytes: compressedBytes,
          peakMemoryMb: memoryUsageMb > 0 ? memoryUsageMb : 0,
        );

        results.add(metric);
        onProgress?.call(i, iterations, metric);

        // Yield execution loop slightly
        await Future.delayed(const Duration(milliseconds: 2));
      }
    } finally {
      _isRunning = false;
    }

    return results;
  }
}
