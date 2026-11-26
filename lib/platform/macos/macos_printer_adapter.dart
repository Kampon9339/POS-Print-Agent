import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;

/// Discovered OS/USB printer metadata on macOS.
class DiscoveredOsPrinter {
  final String name;
  final String driverOrPort;
  final bool isDefault;
  final bool isUsb;
  final bool isAvailable;

  const DiscoveredOsPrinter({
    required this.name,
    this.driverOrPort = 'CUPS',
    this.isDefault = false,
    this.isUsb = false,
    this.isAvailable = true,
  });
}

/// Native macOS CUPS (`lpstat`, `lp`) adapter for printer discovery and job submission.
class MacosPrinterAdapter {
  const MacosPrinterAdapter();

  /// Lists installed macOS CUPS printers via `lpstat`.
  Future<List<DiscoveredOsPrinter>> listPrinters() async {
    if (!Platform.isMacOS) return const [];
    try {
      final statusRes = await Process.run('lpstat', ['-p', '-d', '-v']);
      if (statusRes.exitCode != 0) return const [];

      final output = statusRes.stdout.toString();
      final lines = output.split('\n');
      String? defaultPrinter;
      final usbDevices = <String, String>{};
      final printers = <String, bool>{};

      for (final rawLine in lines) {
        final line = rawLine.trim();
        if (line.startsWith('system default destination:')) {
          defaultPrinter =
              line.substring('system default destination:'.length).trim();
        } else if (line.startsWith('device for ')) {
          // Format: device for <name>: usb://... or ipp://...
          final colonIdx = line.indexOf(':');
          if (colonIdx > 'device for '.length) {
            final name = line.substring('device for '.length, colonIdx).trim();
            final uri = line.substring(colonIdx + 1).trim();
            usbDevices[name] = uri;
          }
        } else if (line.startsWith('printer ')) {
          final parts = line.split(' ');
          if (parts.length >= 2) {
            final name = parts[1].trim();
            final disabled = line.toLowerCase().contains('disabled');
            printers[name] = !disabled;
          }
        }
      }

      return printers.entries.map((entry) {
        final uri = usbDevices[entry.key] ?? 'cups://local';
        final isUsb = uri.toLowerCase().contains('usb:');
        return DiscoveredOsPrinter(
          name: entry.key,
          driverOrPort: uri,
          isDefault: entry.key == defaultPrinter,
          isUsb: isUsb,
          isAvailable: entry.value,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  /// Submits a PDF document to macOS CUPS `lp` command for the specified printer.
  Future<bool> printPdfWithCups({
    required String printerName,
    required Uint8List pdfBytes,
    required int paperWidthMm,
    required String jobTitle,
  }) async {
    if (!Platform.isMacOS) return false;
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      p.join(tempDir.path, 'ppa_${DateTime.now().microsecondsSinceEpoch}.pdf'),
    );
    try {
      await tempFile.writeAsBytes(pdfBytes, flush: true);
      final mediaOption =
          paperWidthMm == 210
              ? 'iso_a4_210x297mm'
              : (paperWidthMm == 58 ? 'Custom.58x200mm' : 'Custom.80x200mm');
      final result = await Process.run('lp', [
        '-d',
        printerName,
        '-t',
        jobTitle,
        '-o',
        'media=$mediaOption',
        '-o',
        'fit-to-page',
        tempFile.path,
      ]);
      return result.exitCode == 0;
    } finally {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
  }

  /// Sends raw ESC/POS bytes to a USB/CUPS printer queue using `lp -o raw`.
  Future<bool> printRawWithCups({
    required String printerName,
    required Uint8List rawBytes,
    required String jobTitle,
  }) async {
    if (!Platform.isMacOS) return false;
    final tempDir = Directory.systemTemp;
    final tempFile = File(
      p.join(
        tempDir.path,
        'ppa_raw_${DateTime.now().microsecondsSinceEpoch}.bin',
      ),
    );
    try {
      await tempFile.writeAsBytes(rawBytes, flush: true);
      final result = await Process.run('lp', [
        '-d',
        printerName,
        '-t',
        jobTitle,
        '-o',
        'raw',
        tempFile.path,
      ]);
      return result.exitCode == 0;
    } finally {
      if (tempFile.existsSync()) {
        try {
          tempFile.deleteSync();
        } catch (_) {}
      }
    }
  }
}
