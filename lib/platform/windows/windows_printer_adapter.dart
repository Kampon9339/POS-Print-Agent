import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import '../macos/macos_printer_adapter.dart';

/// Native Windows Spooler adapter for discovering OS and USB printers and
/// submitting print jobs on Windows desktop systems.
class WindowsPrinterAdapter {
  const WindowsPrinterAdapter();

  /// Queries Windows installed printers via PowerShell `Get-Printer`.
  Future<List<DiscoveredOsPrinter>> listPrinters() async {
    if (!Platform.isWindows) return const [];
    try {
      final result = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        'Get-Printer | Select-Object Name,DriverName,PortName,PrinterStatus | ConvertTo-Json -Compress',
      ]);
      if (result.exitCode != 0) return const [];

      final rawOut = result.stdout.toString().trim();
      if (rawOut.isEmpty) return const [];

      final decoded = jsonDecode(rawOut);
      final List<dynamic> list = decoded is List ? decoded : [decoded];

      return list.whereType<Map<String, dynamic>>().map((item) {
        final name = (item['Name'] as String?) ?? 'Unknown Printer';
        final portName = (item['PortName'] as String?) ?? '';
        final status = item['PrinterStatus'];
        final isUsb = portName.toUpperCase().startsWith('USB');
        final isOnline = status == null || status == 0 || status == 3;
        return DiscoveredOsPrinter(
          name: name,
          driverOrPort: portName.isNotEmpty ? portName : 'Windows Spooler',
          isDefault: false,
          isUsb: isUsb,
          isAvailable: isOnline,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Submits a PDF document to a Windows Spooler printer queue.
  Future<bool> printPdfWithWindowsSpooler({
    required String printerName,
    required Uint8List pdfBytes,
  }) async {
    if (!Platform.isWindows) return false;
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      p.join(
        tempDir.path,
        'ppa_win_${DateTime.now().microsecondsSinceEpoch}.pdf',
      ),
    );
    try {
      await tempFile.writeAsBytes(pdfBytes, flush: true);
      final escapedPath = tempFile.path.replaceAll("'", "''");
      final escapedPrinter = printerName.replaceAll("'", "''");
      final res = await Process.run('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-Command',
        "Start-Process -FilePath '$escapedPath' -Verb PrintTo -ArgumentList '\"$escapedPrinter\"' -WindowStyle Hidden -Wait",
      ]);
      return res.exitCode == 0;
    } finally {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Sends raw ESC/POS bytes to a shared or local Windows printer port when supported.
  Future<bool> printRawToWindowsShare({
    required String printerShareOrPort,
    required Uint8List rawBytes,
  }) async {
    if (!Platform.isWindows) return false;
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      p.join(
        tempDir.path,
        'ppa_win_${DateTime.now().microsecondsSinceEpoch}.bin',
      ),
    );
    try {
      await tempFile.writeAsBytes(rawBytes, flush: true);
      final res = await Process.run('cmd', [
        '/c',
        'copy',
        '/b',
        tempFile.path,
        printerShareOrPort,
      ]);
      return res.exitCode == 0;
    } finally {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
  }
}
