import 'dart:io';
import 'package:flutter/material.dart';
import '../benchmark/benchmark_runner.dart';
import '../benchmark/metrics_exporter.dart';
import '../models/benchmark_metric.dart';

class BenchmarkDashboard extends StatefulWidget {
  const BenchmarkDashboard({super.key});

  @override
  State<BenchmarkDashboard> createState() => _BenchmarkDashboardState();
}

class _BenchmarkDashboardState extends State<BenchmarkDashboard> {
  final BenchmarkRunner _runner = BenchmarkRunner();
  final List<BenchmarkMetric> _metrics = [];

  bool _isBenchmarking = false;
  int _currentIteration = 0;
  final int _totalIterations = 50;
  File? _exportedFile;

  // Aggregate stats
  double _avgWitnessTime = 0.0;
  double _avgProofTime = 0.0;
  double _avgVerifyTime = 0.0;
  int _avgRawBytes = 0;
  int _avgCompressedBytes = 0;
  double _avgMemoryMb = 0.0;

  Future<void> _startBenchmark() async {
    setState(() {
      _isBenchmarking = true;
      _metrics.clear();
      _currentIteration = 0;
      _exportedFile = null;
    });

    final results = await _runner.runFullBenchmarkSuite(
      iterations: _totalIterations,
      onProgress: (current, total, last) {
        setState(() {
          _currentIteration = current;
          _metrics.add(last);
          _calculateAggregates();
        });
      },
    );

    setState(() {
      _isBenchmarking = false;
    });

    // Automatically export CSV
    if (results.isNotEmpty) {
      final file = await MetricsExporter.exportToFile(results);
      setState(() {
        _exportedFile = file;
      });
    }
  }

  void _calculateAggregates() {
    if (_metrics.isEmpty) return;
    _avgWitnessTime =
        _metrics.map((m) => m.witnessTimeMs).reduce((a, b) => a + b) /
            _metrics.length;
    _avgProofTime =
        _metrics.map((m) => m.proofTimeMs).reduce((a, b) => a + b) /
            _metrics.length;
    _avgVerifyTime =
        _metrics.map((m) => m.verifyTimeMs).reduce((a, b) => a + b) /
            _metrics.length;
    _avgRawBytes =
        (_metrics.map((m) => m.rawPayloadBytes).reduce((a, b) => a + b) /
                _metrics.length)
            .round();
    _avgCompressedBytes =
        (_metrics.map((m) => m.compressedPayloadBytes).reduce((a, b) => a + b) /
                _metrics.length)
            .round();
    _avgMemoryMb =
        _metrics.map((m) => m.peakMemoryMb).reduce((a, b) => a + b) /
            _metrics.length;
  }

  @override
  Widget build(BuildContext context) {
    final compressionRatio = _avgRawBytes > 0
        ? ((1.0 - (_avgCompressedBytes / _avgRawBytes)) * 100).toStringAsFixed(1)
        : '0.0';

    return Scaffold(
      appBar: AppBar(
        title: const Text('Performance & Paper Metrics'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  children: [
                    const Text(
                      'Automated 50-Cycle Benchmark Engine',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Measures Groth16 witness timing, BN254 proving latency, Base85 compression, and mobile RAM usage for final year research paper.',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    if (_isBenchmarking) ...[
                      LinearProgressIndicator(
                        value: _currentIteration / _totalIterations,
                      ),
                      const SizedBox(height: 10),
                      Text('Running Cycle $_currentIteration of $_totalIterations...'),
                    ] else ...[
                      ElevatedButton.icon(
                        onPressed: _startBenchmark,
                        icon: const Icon(Icons.play_arrow),
                        label: const Text('Run 50-Iteration Benchmark'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'AVERAGE PERFORMANCE METRICS',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 1.2,
                color: Colors.grey,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Witness Generation',
                    value: '${_avgWitnessTime.toStringAsFixed(1)} ms',
                    icon: Icons.timer,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Groth16 Proving',
                    value: '${_avgProofTime.toStringAsFixed(1)} ms',
                    subtitle: '< 2.0s goal',
                    icon: Icons.speed,
                    color: Colors.green,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricCard(
                    title: 'Verification Time',
                    value: '${_avgVerifyTime.toStringAsFixed(1)} ms',
                    icon: Icons.verified,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildMetricCard(
                    title: 'Peak RAM Usage',
                    value: '${_avgMemoryMb.toStringAsFixed(1)} MB',
                    icon: Icons.memory,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Card(
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Payload Compression Ratio',
                      style:
                          TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('Raw JSON Size: $_avgRawBytes bytes'),
                        Text('Base85: $_avgCompressedBytes bytes'),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: LinearProgressIndicator(
                        value: _avgRawBytes > 0
                            ? (_avgCompressedBytes / _avgRawBytes)
                            : 0,
                        minHeight: 12,
                        backgroundColor: Colors.grey.shade300,
                        color: Colors.deepPurple,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Compressed payload is $compressionRatio% smaller for fast camera reading',
                      style: const TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
            ),
            if (_exportedFile != null) ...[
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.green.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.check_circle, color: Colors.green.shade700),
                        const SizedBox(width: 8),
                        const Text(
                          'Dataset Exported to CSV',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Saved to: ${_exportedFile!.path}',
                      style: const TextStyle(fontSize: 12, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    String? subtitle,
    required IconData icon,
    required Color color,
  }) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color, size: 20),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(fontSize: 11, color: Colors.grey),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(fontSize: 10, color: Colors.green.shade700),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
