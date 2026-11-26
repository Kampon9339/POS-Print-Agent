import 'dart:async';
import 'dart:io';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/printer_model.dart';
import '../receipt_engine/esc_pos_encoder.dart';
import '../receipt_engine/receipt_renderer.dart';
import 'print_backend.dart';

/// Network print backend (`EscPosTcpBackend`) for LAN and Wi-Fi thermal printers
/// communicating over RAW TCP (port 9100) or LPR (port 515).
class EscPosTcpBackend implements IPrintBackend {
  final EscPosEncoder encoder;

  const EscPosTcpBackend({this.encoder = const EscPosEncoder()});

  @override
  String get backendId => 'EscPosTcpBackend';

  @override
  Future<bool> checkAvailability(PrinterModel printer) async {
    final host = printer.host?.trim() ?? '';
    if (host.isEmpty) return false;
    final port = printer.port ?? _defaultPortForProtocol(printer.protocol);
    final timeout = Duration(
      milliseconds: printer.configuration.timeoutMs.clamp(1000, 15000),
    );

    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      return true;
    } catch (_) {
      return false;
    } finally {
      try {
        await socket?.close();
        socket?.destroy();
      } catch (_) {}
    }
  }

  @override
  Future<PrintBackendResult> submitReceipt(
    PrinterModel printer,
    RenderedReceiptDocument document,
  ) async {
    final host = printer.host?.trim() ?? '';
    if (host.isEmpty) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'MISSING_PRINTER_HOST',
        errorMessage:
            'ไม่ได้กำหนด IP Address หรือ Hostname ของเครื่องพิมพ์เครือข่าย',
      );
    }

    final port = printer.port ?? _defaultPortForProtocol(printer.protocol);
    final timeout = Duration(
      milliseconds: printer.configuration.timeoutMs.clamp(2000, 30000),
    );

    final escPosBytes = encoder.encode(
      document,
      useRasterMode: printer.configuration.useRasterForEscPos,
      autoCut: printer.configuration.autoCut,
      openCashDrawer: printer.configuration.openCashDrawer,
    );

    Socket? socket;
    try {
      socket = await Socket.connect(host, port, timeout: timeout);
      socket.setOption(SocketOption.tcpNoDelay, true);

      socket.add(escPosBytes);
      await socket.flush().timeout(timeout);
      await socket.close().timeout(const Duration(seconds: 3));

      return PrintBackendResult.success(
        backendName: backendId,
        bytesSent: escPosBytes.length,
      );
    } on SocketException catch (e) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'LAN_PRINTER_UNREACHABLE',
        errorMessage:
            'ไม่สามารถเชื่อมต่อเครื่องพิมพ์เครือข่าย $host:$port (${e.message})',
      );
    } on TimeoutException {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'LAN_PRINTER_TIMEOUT',
        errorMessage:
            'หมดเวลาการเชื่อมต่อ (Timeout) กับเครื่องพิมพ์เครือข่าย $host:$port',
      );
    } catch (e) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'LAN_PRINT_ERROR',
        errorMessage: 'เกิดข้อผิดพลาดขณะส่งข้อมูลไปยัง $host:$port: $e',
      );
    } finally {
      try {
        socket?.destroy();
      } catch (_) {}
    }
  }

  int _defaultPortForProtocol(PrinterProtocol protocol) {
    switch (protocol) {
      case PrinterProtocol.rawTcp:
        return AppConstants.defaultRawTcpPort;
      case PrinterProtocol.ipp:
        return AppConstants.defaultIppPort;
      case PrinterProtocol.lpr:
        return AppConstants.defaultLprPort;
      default:
        return AppConstants.defaultRawTcpPort;
    }
  }
}
