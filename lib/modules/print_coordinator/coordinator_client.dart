import 'dart:async';
import 'dart:convert';
import 'dart:io';
import '../../core/configuration/app_config_service.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/models/printer_model.dart';
import '../print_engine/print_backend.dart';
import '../receipt_engine/receipt_renderer.dart';

/// Client backend (`CoordinatorForwardBackend`) used when an Agent operates
/// in Mode B (`LanOperatingMode.coordinatorClient`), forwarding shared LAN
/// printer jobs to the Central Print Coordinator over an authenticated channel.
class CoordinatorForwardBackend implements IPrintBackend {
  final AppConfigService configService;
  final AppLogger logger;

  CoordinatorForwardBackend({
    required this.configService,
    required this.logger,
  });

  @override
  String get backendId => 'CoordinatorForwardBackend';

  @override
  Future<bool> checkAvailability(PrinterModel printer) async {
    final baseUrl = configService.settings.remoteCoordinatorUrl.trim();
    final token = configService.settings.remoteCoordinatorToken.trim();
    if (baseUrl.isEmpty || token.isEmpty) return false;

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 4);
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/coordinator/v1/health',
      );
      final req = await client.getUrl(uri);
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
      final resp = await req.close().timeout(const Duration(seconds: 4));
      await resp.drain<void>();
      return resp.statusCode == 200;
    } catch (_) {
      return false;
    } finally {
      client.close(force: true);
    }
  }

  @override
  Future<PrintBackendResult> submitReceipt(
    PrinterModel printer,
    RenderedReceiptDocument document,
  ) async {
    final baseUrl = configService.settings.remoteCoordinatorUrl.trim();
    final token = configService.settings.remoteCoordinatorToken.trim();

    if (baseUrl.isEmpty) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'COORDINATOR_URL_MISSING',
        errorMessage: 'ไม่ได้กำหนด URL ของเครื่องแม่ข่าย Central Coordinator',
      );
    }
    if (token.isEmpty) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'COORDINATOR_TOKEN_MISSING',
        errorMessage:
            'ไม่ได้กำหนดรหัสรับรองสิทธิ์ (Token) สำหรับเชื่อมต่อ Central Coordinator',
      );
    }

    final client = HttpClient()..connectionTimeout = const Duration(seconds: 6);
    try {
      final uri = Uri.parse(
        '${baseUrl.replaceAll(RegExp(r'/$'), '')}/coordinator/v1/print',
      );
      final req = await client.postUrl(uri);
      req.headers.set(
        HttpHeaders.contentTypeHeader,
        'application/json; charset=utf-8',
      );
      req.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');

      final bodyMap = {
        'receipt': document.payload.toJson(),
        'targetPrinter': {
          'id': printer.id,
          'name': printer.name,
          'host': printer.host,
          'port': printer.port,
          'paperWidth': printer.paperWidth,
          'protocol': printer.protocol.value,
        },
      };
      final encodedBody = utf8.encode(jsonEncode(bodyMap));
      req.contentLength = encodedBody.length;
      req.add(encodedBody);

      final resp = await req.close().timeout(const Duration(seconds: 12));
      final respBody = await utf8.decoder.bind(resp).join();

      if (resp.statusCode == 200 ||
          resp.statusCode == 201 ||
          resp.statusCode == 202) {
        return PrintBackendResult.success(
          backendName: backendId,
          bytesSent: encodedBody.length,
        );
      }

      String errorDetail = 'HTTP ${resp.statusCode}';
      try {
        final decoded = jsonDecode(respBody);
        if (decoded is Map && decoded['message'] != null) {
          errorDetail = decoded['message'].toString();
        }
      } catch (_) {}

      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'COORDINATOR_REJECTED_${resp.statusCode}',
        errorMessage: 'Central Coordinator ปฏิเสธคำสั่งพิมพ์: $errorDetail',
      );
    } on TimeoutException {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'COORDINATOR_TIMEOUT',
        errorMessage: 'หมดเวลาเชื่อมต่อกับ Central Coordinator ($baseUrl)',
      );
    } on SocketException catch (e) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'COORDINATOR_UNREACHABLE',
        errorMessage:
            'ไม่สามารถติดต่อ Central Coordinator ($baseUrl): ${e.message}',
      );
    } catch (e) {
      return PrintBackendResult.failure(
        backendName: backendId,
        errorCode: 'COORDINATOR_ERROR',
        errorMessage: 'เกิดข้อผิดพลาดในการส่งงานไปยัง Central Coordinator: $e',
      );
    } finally {
      client.close(force: true);
    }
  }
}
