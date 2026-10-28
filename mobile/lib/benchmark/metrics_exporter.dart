import 'dart:io';
import 'package:csv/csv.dart';
import 'package:path_provider/path_provider.dart';
import '../models/benchmark_metric.dart';

/// Exports collected benchmark metrics to CSV format on the mobile device storage.
class MetricsExporter {
  /// Converts metrics to CSV string.
  static String generateCsvString(List<BenchmarkMetric> metrics) {
    final List<List<dynamic>> rows = [
      BenchmarkMetric.csvHeaders(),
      ...metrics.map((m) => m.toCsvRow()),
    ];

    return const ListToCsvConverter().convert(rows);
  }

  /// Writes benchmark_results.csv to the application documents directory.
  static Future<File> exportToFile(List<BenchmarkMetric> metrics) async {
    final csvContent = generateCsvString(metrics);
    final directory = await getApplicationDocumentsDirectory();
    final file = File('${directory.path}/benchmark_results.csv');
    return await file.writeAsString(csvContent);
  }
}
