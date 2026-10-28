/// Stores measurement data for one iteration of the Groth16 benchmark.
class BenchmarkMetric {
  final int iteration;
  final double witnessTimeMs;
  final double proofTimeMs;
  final double verifyTimeMs;
  final int rawPayloadBytes;
  final int compressedPayloadBytes;
  final double peakMemoryMb;

  BenchmarkMetric({
    required this.iteration,
    required this.witnessTimeMs,
    required this.proofTimeMs,
    required this.verifyTimeMs,
    required this.rawPayloadBytes,
    required this.compressedPayloadBytes,
    required this.peakMemoryMb,
  });

  List<dynamic> toCsvRow() => [
        iteration,
        witnessTimeMs.toStringAsFixed(2),
        proofTimeMs.toStringAsFixed(2),
        verifyTimeMs.toStringAsFixed(2),
        rawPayloadBytes,
        compressedPayloadBytes,
        peakMemoryMb.toStringAsFixed(2),
      ];

  static List<String> csvHeaders() => [
        'iteration',
        'witness_time_ms',
        'proof_time_ms',
        'verify_time_ms',
        'raw_payload_bytes',
        'compressed_payload_bytes',
        'peak_memory_mb',
      ];
}
