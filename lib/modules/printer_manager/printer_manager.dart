import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/models/printer_model.dart';
import '../../shared/models/receipt_payload.dart';
import '../print_engine/esc_pos_tcp_backend.dart';
import '../print_engine/os_print_backend.dart';
import '../print_engine/print_backend.dart';
import '../print_engine/usb_print_backend.dart';
import '../printer_discovery/printer_discovery_service.dart';
import '../receipt_engine/receipt_renderer.dart';
import 'printer_repository.dart';

/// Manages printer configurations, backend resolution, availability checks,
/// and test receipt generation.
class PrinterManager extends ChangeNotifier {
  final PrinterRepository repository;
  final PrinterDiscoveryService discoveryService;
  final ReceiptRenderer receiptRenderer;
  final AppLogger logger;

  final IPrintBackend osBackend;
  final IPrintBackend tcpBackend;
  final IPrintBackend usbBackend;
  IPrintBackend? coordinatorForwardBackend;

  final Map<String, bool> _onlineStatus = {};
  final Uuid _uuid = const Uuid();

  PrinterManager({
    required this.repository,
    required this.logger,
    this.discoveryService = const PrinterDiscoveryService(),
    this.receiptRenderer = const ReceiptRenderer(),
    IPrintBackend? osBackend,
    IPrintBackend? tcpBackend,
    IPrintBackend? usbBackend,
    this.coordinatorForwardBackend,
  }) : osBackend = osBackend ?? const OsPrintBackend(),
       tcpBackend = tcpBackend ?? const EscPosTcpBackend(),
       usbBackend = usbBackend ?? const UsbPrintBackend();

  List<PrinterModel> listPrinters() {
    return repository.listAll(onlineStatuses: _onlineStatus);
  }

  PrinterModel? getPrinterById(String id) {
    return repository.findById(id, isOnline: _onlineStatus[id]);
  }

  PrinterModel? getDefaultPrinter() {
    return repository.findDefaultPrinter();
  }

  /// Resolves the appropriate [IPrintBackend] for [printer].
  /// When [forwardLanToCoordinator] is true and [coordinatorForwardBackend] is
  /// configured, LAN/Wi-Fi printers route through the Central Coordinator.
  IPrintBackend backendForPrinter(
    PrinterModel printer, {
    bool forwardLanToCoordinator = false,
  }) {
    if (forwardLanToCoordinator &&
        coordinatorForwardBackend != null &&
        (printer.connectionType == PrinterConnectionType.lan ||
            printer.connectionType == PrinterConnectionType.wifi)) {
      return coordinatorForwardBackend!;
    }

    switch (printer.connectionType) {
      case PrinterConnectionType.lan:
      case PrinterConnectionType.wifi:
        if (printer.protocol == PrinterProtocol.osDriver) {
          return osBackend;
        }
        return tcpBackend;
      case PrinterConnectionType.usb:
        return usbBackend;
      case PrinterConnectionType.os:
        return osBackend;
    }
  }

  /// Adds a new printer configuration.
  PrinterModel addPrinter({
    String? id,
    required String name,
    required PrinterConnectionType connectionType,
    required PrinterProtocol protocol,
    String? host,
    int? port,
    int paperWidth = 80,
    bool isDefault = false,
    bool enabled = true,
    PrinterConfiguration configuration = const PrinterConfiguration(),
  }) {
    final existingAll = repository.listAll();
    final shouldBeDefault = isDefault || existingAll.isEmpty;
    final now = DateTime.now();

    final model = PrinterModel(
      id: id ?? _uuid.v4(),
      name: name.trim(),
      connectionType: connectionType,
      protocol: protocol,
      host: host?.trim(),
      port: port,
      paperWidth: paperWidth == 58 ? 58 : 80,
      isDefault: shouldBeDefault,
      enabled: enabled,
      configuration: configuration,
      createdAt: now,
      updatedAt: now,
      isOnline: enabled,
    );

    repository.insert(model);
    _onlineStatus[model.id] = enabled;
    logger.info('PrinterManager', 'Added printer', {
      'id': model.id,
      'name': model.name,
      'connectionType': model.connectionType.value,
    });
    notifyListeners();
    return model;
  }

  /// Updates an existing printer configuration.
  PrinterModel? updatePrinter(PrinterModel updated) {
    final ok = repository.update(updated);
    if (!ok) return null;
    logger.info('PrinterManager', 'Updated printer', {
      'id': updated.id,
      'name': updated.name,
    });
    notifyListeners();
    return getPrinterById(updated.id);
  }

  /// Sets the specified printer as the default printer.
  bool setDefaultPrinter(String printerId) {
    final ok = repository.setDefault(printerId);
    if (ok) {
      logger.info('PrinterManager', 'Set default printer', {
        'printerId': printerId,
      });
      notifyListeners();
    }
    return ok;
  }

  /// Removes a printer configuration.
  bool removePrinter(String printerId) {
    final ok = repository.delete(printerId);
    if (ok) {
      _onlineStatus.remove(printerId);
      logger.info('PrinterManager', 'Deleted printer', {
        'printerId': printerId,
      });
      notifyListeners();
    }
    return ok;
  }

  /// Checks and updates live availability status for a single printer.
  Future<bool> checkPrinterOnline(PrinterModel printer) async {
    if (!printer.enabled) {
      _onlineStatus[printer.id] = false;
      notifyListeners();
      return false;
    }
    final backend = backendForPrinter(printer);
    final available = await backend.checkAvailability(printer);
    _onlineStatus[printer.id] = available;
    notifyListeners();
    return available;
  }

  /// Checks availability across all configured printers.
  Future<void> refreshAllPrinterStatuses() async {
    final printers = repository.listAll();
    for (final printer in printers) {
      if (!printer.enabled) {
        _onlineStatus[printer.id] = false;
      } else {
        final backend = backendForPrinter(printer);
        _onlineStatus[printer.id] = await backend.checkAvailability(printer);
      }
    }
    notifyListeners();
  }

  /// Generates a diagnostic Thai + English test receipt payload for [printer].
  ReceiptPayload buildTestReceiptPayload(PrinterModel printer) {
    final nowIso = DateTime.now().toIso8601String();
    final testJobId = 'TEST-${_uuid.v4().substring(0, 8).toUpperCase()}';
    return ReceiptPayload(
      schemaVersion: 1,
      jobId: testJobId,
      billId: 'TEST-BILL-001',
      billNumber: 'TEST-0001',
      copyType: 'original',
      paperWidth: printer.paperWidth,
      targetPrinterId: printer.id,
      store: const StoreInfo(
        name: 'ทดสอบระบบพิมพ์ POS Print Agent',
        address: 'ใบเสร็จทดสอบภาษาไทย & English (58mm/80mm)',
        phone: '02-000-0000',
        taxId: '0105550000000',
        footer: 'พิมพ์ทดสอบสำเร็จ — ขอบคุณที่ใช้บริการ',
      ),
      cashier: CashierInfo(
        name: '${printer.name} (${printer.connectionType.value.toUpperCase()})',
      ),
      issuedAt: nowIso,
      items: const [
        ReceiptItem(
          productName: 'น้ำดื่มบริสุทธิ์ (Drinking Water)',
          quantity: 2,
          unit: 'ขวด',
          unitPrice: 10,
          discount: 0,
          total: 20,
        ),
        ReceiptItem(
          productName:
              'กาแฟสดคั่วบดพิเศษ (テスト / ทดสอบสระและวรรณยุกต์ กิ่ง กุ้ง เก๋ง)',
          quantity: 1,
          unit: 'แก้ว',
          unitPrice: 55,
          discount: 5,
          total: 50,
        ),
      ],
      subtotal: 75,
      discountTotal: 5,
      vatRate: 7,
      vatAmount: 4.58,
      grandTotal: 70,
      payment: const PaymentInfo(method: 'cash', received: 100, change: 30),
    );
  }

  /// Sends a test receipt directly to [printerId] and returns the backend result.
  Future<PrintBackendResult> testPrint(String printerId) async {
    final printer = getPrinterById(printerId);
    if (printer == null) {
      return PrintBackendResult.failure(
        backendName: 'PrinterManager',
        errorCode: 'PRINTER_NOT_FOUND',
        errorMessage: 'ไม่พบเครื่องพิมพ์รหัส $printerId',
      );
    }

    final payload = buildTestReceiptPayload(printer);
    final doc = receiptRenderer.render(
      payload,
      overridePaperWidthMm: printer.paperWidth,
      fontSize: 14.0 * printer.configuration.fontScale,
      lineSpacing: printer.configuration.lineSpacing,
      marginMm: printer.configuration.marginMm,
    );

    final backend = backendForPrinter(printer);
    final result = await backend.submitReceipt(printer, doc);
    _onlineStatus[printer.id] = result.submitted;
    notifyListeners();
    return result;
  }
}
