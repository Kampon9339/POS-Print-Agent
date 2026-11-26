import '../../shared/models/printer_model.dart';
import '../receipt_engine/receipt_renderer.dart';

/// Result of submitting a rendered receipt to a physical or OS print backend.
/// Note: `submitted == true` indicates the OS spooler or network/USB transport
/// accepted the job; it does NOT guarantee physical paper output.
class PrintBackendResult {
  final bool submitted;
  final String backendName;
  final int bytesSent;
  final String? errorCode;
  final String? errorMessage;

  const PrintBackendResult({
    required this.submitted,
    required this.backendName,
    this.bytesSent = 0,
    this.errorCode,
    this.errorMessage,
  });

  factory PrintBackendResult.success({
    required String backendName,
    required int bytesSent,
  }) {
    return PrintBackendResult(
      submitted: true,
      backendName: backendName,
      bytesSent: bytesSent,
    );
  }

  factory PrintBackendResult.failure({
    required String backendName,
    required String errorCode,
    required String errorMessage,
  }) {
    return PrintBackendResult(
      submitted: false,
      backendName: backendName,
      errorCode: errorCode,
      errorMessage: errorMessage,
    );
  }
}

/// Abstract interface for all printer backends (`OsPrintBackend`,
/// `EscPosTcpBackend`, `UsbPrintBackend`, `CoordinatorForwardBackend`).
abstract class IPrintBackend {
  String get backendId;

  /// Checks whether [printer] is currently reachable or registered in the OS.
  Future<bool> checkAvailability(PrinterModel printer);

  /// Submits [document] to [printer].
  Future<PrintBackendResult> submitReceipt(
    PrinterModel printer,
    RenderedReceiptDocument document,
  );
}
