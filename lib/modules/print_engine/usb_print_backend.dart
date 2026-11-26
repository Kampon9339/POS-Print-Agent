import 'dart:io';
import '../../platform/macos/macos_printer_adapter.dart';
import '../../platform/windows/windows_printer_adapter.dart';
import '../../shared/models/printer_model.dart';
import '../receipt_engine/esc_pos_encoder.dart';
import '../receipt_engine/receipt_renderer.dart';
import 'os_print_backend.dart';
import 'print_backend.dart';

/// USB printer backend (`UsbPrintBackend`) supporting USB printers exposed
/// through macOS CUPS or Windows Spooler (both driver mode and raw ESC/POS mode).
class UsbPrintBackend implements IPrintBackend {
  final OsPrintBackend osBackend;
  final EscPosEncoder escPosEncoder;
  final MacosPrinterAdapter macosAdapter;
  final WindowsPrinterAdapter windowsAdapter;

  const UsbPrintBackend({
    this.osBackend = const OsPrintBackend(),
    this.escPosEncoder = const EscPosEncoder(),
    this.macosAdapter = const MacosPrinterAdapter(),
    this.windowsAdapter = const WindowsPrinterAdapter(),
  });

  @override
  String get backendId => 'UsbPrintBackend';

  @override
  Future<bool> checkAvailability(PrinterModel printer) async {
    return osBackend.checkAvailability(printer);
  }

  @override
  Future<PrintBackendResult> submitReceipt(
    PrinterModel printer,
    RenderedReceiptDocument document,
  ) async {
    final targetName =
        (printer.configuration.osDriverName ?? printer.name).trim();
    if (targetName.isEmpty) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'USB_DEVICE_NOT_CONFIGURED',
        errorMessage: 'ไม่ได้ระบุชื่อพอร์ตหรือไดรเวอร์ของเครื่องพิมพ์ USB',
      );
    }

    // If raw USB ESC/POS mode is explicitly configured, attempt raw pass-through first
    if (printer.protocol == PrinterProtocol.usbRaw) {
      final rawBytes = escPosEncoder.encode(
        document,
        useRasterMode: printer.configuration.useRasterForEscPos,
        autoCut: printer.configuration.autoCut,
        openCashDrawer: printer.configuration.openCashDrawer,
      );

      if (Platform.isMacOS) {
        final ok = await macosAdapter.printRawWithCups(
          printerName: targetName,
          rawBytes: rawBytes,
          jobTitle: 'POS_USB_${document.payload.billNumber}',
        );
        if (ok) {
          return PrintBackendResult.success(
            backendName: backendId,
            bytesSent: rawBytes.length,
          );
        }
      } else if (Platform.isWindows) {
        final ok = await windowsAdapter.printRawToWindowsShare(
          printerShareOrPort: targetName,
          rawBytes: rawBytes,
        );
        if (ok) {
          return PrintBackendResult.success(
            backendName: backendId,
            bytesSent: rawBytes.length,
          );
        }
      }
    }

    // Standard OS USB printer driver submission
    final osResult = await osBackend.submitReceipt(printer, document);
    return PrintBackendResult(
      submitted: osResult.submitted,
      backendName: backendId,
      bytesSent: osResult.bytesSent,
      errorCode: osResult.errorCode,
      errorMessage: osResult.errorMessage,
    );
  }
}
