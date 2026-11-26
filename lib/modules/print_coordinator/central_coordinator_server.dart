import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../../core/logging/app_logger.dart';
import '../../core/security/rate_limiter.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/paired_device_model.dart';
import '../pairing/pairing_service.dart';
import '../print_queue/print_queue_service.dart';
import '../printer_manager/printer_manager.dart';
import '../receipt_engine/receipt_validator.dart';

/// Mode B Central Print Coordinator HTTP service for shared LAN printers.
/// Runs on a separate port from the Local Agent API and requires mandatory
/// Bearer token authentication for all remote POS Print Agents.
class CentralCoordinatorServer extends ChangeNotifier {
  final PairingService pairingService;
  final PrinterManager printerManager;
  final PrintQueueService printQueueService;
  final AppLogger logger;
  final RateLimiter rateLimiter = RateLimiter(maxRequests: 180);

  HttpServer? _server;
  String _boundHost = '127.0.0.1';
  int _boundPort = AppConstants.defaultCoordinatorPort;

  CentralCoordinatorServer({
    required this.pairingService,
    required this.printerManager,
    required this.printQueueService,
    required this.logger,
  });

  bool get isRunning => _server != null;
  String get boundHost => _boundHost;
  int get boundPort => _server?.port ?? _boundPort;

  /// Starts the Central Print Coordinator server on [host]:[port].
  Future<void> start({
    String host = '0.0.0.0',
    int port = AppConstants.defaultCoordinatorPort,
  }) async {
    await stop();
    final router =
        Router()
          ..get('/coordinator/v1/health', _handleHealth)
          ..post('/coordinator/v1/print', _handleCoordinatorPrint);

    final handler = const Pipeline()
        .addMiddleware(_securityMiddleware)
        .addHandler(router.call);

    _server = await shelf_io.serve(handler, host, port);
    _boundHost = host;
    _boundPort = _server!.port;
    logger.info(
      'CoordinatorServer',
      'Started Central Print Coordinator service',
      {'host': _boundHost, 'port': _boundPort},
    );
    notifyListeners();
  }

  /// Stops the Central Print Coordinator server.
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      logger.info('CoordinatorServer', 'Stopped Central Print Coordinator');
      notifyListeners();
    }
  }

  Middleware get _securityMiddleware {
    return (Handler innerHandler) {
      return (Request request) async {
        final clientIp =
            (request.context['shelf.io.connection_info'] as HttpConnectionInfo?)
                ?.remoteAddress
                .address ??
            'unknown';

        if (!rateLimiter.allowRequest(clientIp)) {
          logger.security('CoordinatorServer', 'Rate limit exceeded', {
            'clientIp': clientIp,
          });
          return _jsonResponse(429, {
            'success': false,
            'errorCode': 'RATE_LIMIT_EXCEEDED',
            'message': 'Too many requests to Central Coordinator.',
          });
        }

        final authHeader = request.headers[HttpHeaders.authorizationHeader];
        if (authHeader == null ||
            !authHeader.toLowerCase().startsWith('bearer ')) {
          logger.security(
            'CoordinatorServer',
            'Rejected unauthenticated Coordinator request',
            {'clientIp': clientIp, 'path': request.url.path},
          );
          return _jsonResponse(401, {
            'success': false,
            'errorCode': 'COORDINATOR_UNAUTHORIZED',
            'message':
                'Central Coordinator requires a valid paired Agent Bearer token.',
          });
        }

        final rawToken = authHeader.substring(7).trim();
        final PairedDeviceModel? device =
            pairingService.verifyToken(
              rawToken,
              requiredPermission: 'coordinator',
            ) ??
            pairingService.verifyToken(rawToken, requiredPermission: 'print');

        if (device == null) {
          logger.security(
            'CoordinatorServer',
            'Rejected invalid or revoked Coordinator token',
            {'clientIp': clientIp},
          );
          return _jsonResponse(403, {
            'success': false,
            'errorCode': 'COORDINATOR_FORBIDDEN',
            'message': 'Invalid, revoked, or unauthorized Agent credential.',
          });
        }

        final updatedReq = request.change(context: {'pairedDevice': device});
        return innerHandler(updatedReq);
      };
    };
  }

  Future<Response> _handleHealth(Request request) async {
    final device = request.context['pairedDevice'] as PairedDeviceModel?;
    final stats = printQueueService.getQueueStatistics();
    return _jsonResponse(200, {
      'success': true,
      'service': 'POS Print Agent Central Coordinator',
      'version': AppConstants.appVersion,
      'authenticatedDevice': device?.deviceName,
      'printerCount': printerManager.listPrinters().length,
      'queue': stats,
    });
  }

  Future<Response> _handleCoordinatorPrint(Request request) async {
    final rawBody = await request.readAsString();
    if (utf8.encode(rawBody).length > AppConstants.maxImageRequestBodyBytes) {
      return _jsonResponse(413, {
        'success': false,
        'errorCode': 'PAYLOAD_TOO_LARGE',
        'message': 'Request exceeds maximum allowed size.',
      });
    }

    Map<String, dynamic> decoded;
    try {
      final parsed = jsonDecode(rawBody);
      if (parsed is! Map<String, dynamic>) {
        return _jsonResponse(400, {
          'success': false,
          'errorCode': 'MALFORMED_JSON',
          'message': 'Request body must be a JSON object.',
        });
      }
      decoded = parsed;
    } catch (e) {
      return _jsonResponse(400, {
        'success': false,
        'errorCode': 'MALFORMED_JSON',
        'message': 'Malformed JSON: $e',
      });
    }

    final receiptMap =
        decoded['receipt'] is Map<String, dynamic>
            ? decoded['receipt'] as Map<String, dynamic>
            : decoded;

    final validation = ReceiptValidator.validateMap(receiptMap);
    if (!validation.isValid || validation.payload == null) {
      return _jsonResponse(422, {
        'success': false,
        'errorCode': validation.errorCode ?? 'VALIDATION_ERROR',
        'message': 'Invalid receipt JSON payload.',
        'errors': validation.errors,
      });
    }

    String? overridePrinterId;
    if (decoded['targetPrinter'] is Map<String, dynamic>) {
      final tp = decoded['targetPrinter'] as Map<String, dynamic>;
      final requestedId = tp['id'] as String?;
      if (requestedId != null &&
          printerManager.getPrinterById(requestedId) != null) {
        overridePrinterId = requestedId;
      }
    }

    final result = printQueueService.enqueueReceipt(
      validation.payload!,
      overridePrinterId: overridePrinterId,
    );

    return _jsonResponse(result.isDuplicate ? 200 : 202, {
      'success': true,
      'isDuplicate': result.isDuplicate,
      'message':
          result.isDuplicate
              ? 'Duplicate jobId detected; returning existing job status.'
              : 'Job accepted into Central Coordinator shared queue.',
      'job': result.job.toJson(),
    });
  }

  Response _jsonResponse(int statusCode, Map<String, Object?> body) {
    return Response(
      statusCode,
      body: jsonEncode(body),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        'X-Content-Type-Options': 'nosniff',
      },
    );
  }
}
