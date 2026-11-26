import 'dart:io';
import '../../platform/macos/macos_printer_adapter.dart';
import '../../platform/windows/windows_printer_adapter.dart';
import '../../shared/models/printer_model.dart';
import '../receipt_engine/pdf_receipt_builder.dart';
import '../receipt_engine/receipt_renderer.dart';
import 'print_backend.dart';

/// Native Operating System print backend (`OsPrintBackend`) for Windows and macOS.
/// Uses installed OS printer drivers via macOS CUPS (`lp`) and Windows Spooler.
class OsPrintBackend implements IPrintBackend {
  final PdfReceiptBuilder pdfBuilder;
  final MacosPrinterAdapter macosAdapter;
  final WindowsPrinterAdapter windowsAdapter;

  const OsPrintBackend({
    this.pdfBuilder = const PdfReceiptBuilder(),
    this.macosAdapter = const MacosPrinterAdapter(),
    this.windowsAdapter = const WindowsPrinterAdapter(),
  });

  @override
  String get backendId => 'OsPrintBackend';

  @override
  Future<bool> checkAvailability(PrinterModel printer) async {
    final targetName =
        (printer.configuration.osDriverName ?? printer.name).trim();
    if (targetName.isEmpty) return false;

    if (Platform.isMacOS) {
      final list = await macosAdapter.listPrinters();
      final match = list.where(
        (p) => p.name.toLowerCase() == targetName.toLowerCase(),
      );
      if (match.isNotEmpty) {
        return match.first.isAvailable;
      }
    } else if (Platform.isWindows) {
      final list = await windowsAdapter.listPrinters();
      final match = list.where(
        (p) => p.name.toLowerCase() == targetName.toLowerCase(),
      );
      if (match.isNotEmpty) {
        return match.first.isAvailable;
      }
    }

    return false;
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
        errorCode: 'MISSING_OS_PRINTER_NAME',
        errorMessage:
            'ไม่ได้ระบุชื่อเครื่องพิมพ์ในระบบปฏิบัติการ (OS Printer Name)',
      );
    }

    try {
      final pdfBytes = await pdfBuilder.buildPdf(document);
      final jobTitle = 'POS_${document.payload.billNumber}';

      if (Platform.isMacOS) {
        final cupsOk = await macosAdapter.printPdfWithCups(
          printerName: targetName,
          pdfBytes: pdfBytes,
          paperWidthMm: document.paperWidthMm,
          jobTitle: jobTitle,
        );
        if (cupsOk) {
          return PrintBackendResult.success(
            backendName: backendId,
            bytesSent: pdfBytes.length,
          );
        }
        return PrintBackendResult.failure(
          backendName: backendId,
          errorCode: 'CUPS_PRINT_FAILED',
          errorMessage:
              'ไม่พบเครื่องพิมพ์ "$targetName" ใน macOS CUPS หรือเครื่องพิมพ์ไม่พร้อมใช้งาน',
        );
      }

      if (Platform.isWindows) {
        final winOk = await windowsAdapter.printPdfWithWindowsSpooler(
          printerName: targetName,
          pdfBytes: pdfBytes,
        );
        if (winOk) {
          return PrintBackendResult.success(
            backendName: backendId,
            bytesSent: pdfBytes.length,
          );
        }
        return PrintBackendResult.failure(
          backendName: backendId,
          errorCode: 'WINDOWS_SPOOLER_FAILED',
          errorMessage:
              'ไม่สามารถส่งงานพิมพ์ไปยังเครื่องพิมพ์ "$targetName" ผ่าน Windows Spooler',
        );
      }

      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'UNSUPPORTED_OS',
        errorMessage: 'ระบบปฏิบัติการนี้ยังไม่รองรับ OsPrintBackend',
      );
    } catch (e) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'OS_PRINT_ERROR',
        errorMessage: 'เกิดข้อผิดพลาดในการส่งพิมพ์ผ่าน OS Driver: $e',
      );
    }
  }
}
