import '../../shared/models/printer_model.dart';
import '../receipt_engine/receipt_renderer.dart';
import 'print_backend.dart';

/// Recorded submission in [MockPrintBackend] for automated unit and integration tests.
class MockSubmittedPrint {
  final PrinterModel printer;
  final RenderedReceiptDocument document;
  final DateTime submittedAt;

  const MockSubmittedPrint({
    required this.printer,
    required this.document,
    required this.submittedAt,
  });
}

/// Configurable mock print backend used exclusively by automated tests.
/// Production code uses [OsPrintBackend], [EscPosTcpBackend], and [UsbPrintBackend].
class MockPrintBackend implements IPrintBackend {
  @override
  final String backendId;

  final List<MockSubmittedPrint> submissions = [];
  final Map<String, bool> printerAvailability = {};
  final Map<String, String> simulatedErrors = {};
  final Map<String, Duration> simulatedDelays = {};

  MockPrintBackend({this.backendId = 'MockPrintBackend'});

  @override
  Future<bool> checkAvailability(PrinterModel printer) async {
    return printerAvailability[printer.id] ?? printer.enabled;
  }

  @override
  Future<PrintBackendResult> submitReceipt(
    PrinterModel printer,
    RenderedReceiptDocument document,
  ) async {
    final delay = simulatedDelays[printer.id];
    if (delay != null) {
      await Future<void>.delayed(delay);
    }

    final isAvailable = await checkAvailability(printer);
    if (!isAvailable) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'PRINTER_OFFLINE',
        errorMessage: 'Printer ${printer.name} is offline or disconnected.',
      );
    }

    final forcedError = simulatedErrors[printer.id];
    if (forcedError != null) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'SIMULATED_BACKEND_FAILURE',
        errorMessage: forcedError,
      );
    }

    submissions.add(
      MockSubmittedPrint(
        printer: printer,
        document: document,
        submittedAt: DateTime.now(),
      ),
    );

    return PrintBackendResult.success(
      backendName: backendId,
      bytesSent: document.plainText.length,
    );
  }
}
