import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:shelf/shelf.dart';
import 'package:shelf/shelf_io.dart' as shelf_io;
import 'package:shelf_router/shelf_router.dart';
import '../../modules/pairing/pairing_service.dart';
import '../../modules/print_queue/print_queue_service.dart';
import '../../modules/printer_discovery/printer_discovery_service.dart';
import '../../modules/printer_manager/printer_manager.dart';
import '../../modules/receipt_engine/receipt_validator.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/print_job_model.dart';
import '../../shared/models/printer_model.dart';
import '../configuration/app_config_service.dart';
import '../logging/app_logger.dart';
import '../security/origin_validator.dart';
import '../security/rate_limiter.dart';

/// Local HTTP API Server bound strictly to `127.0.0.1` (default port 8765).
class LocalApiServer extends ChangeNotifier {
  final AppConfigService configService;
  final PrinterManager printerManager;
  final PrintQueueService printQueueService;
  final PairingService pairingService;
  final PrinterDiscoveryService discoveryService;
  final AppLogger logger;
  final RateLimiter rateLimiter = RateLimiter(maxRequests: 240);

  HttpServer? _server;
  int _boundPort = AppConstants.defaultLocalApiPort;

  LocalApiServer({
    required this.configService,
    required this.printerManager,
    required this.printQueueService,
    required this.pairingService,
    required this.logger,
    this.discoveryService = const PrinterDiscoveryService(),
  });

  bool get isRunning => _server != null;
  String get bindAddress =>
      'http://${AppConstants.localApiBindHost}:$boundPort';
  int get boundPort => _server?.port ?? _boundPort;

  /// Starts the Local HTTP API server bound exclusively to `127.0.0.1`.
  Future<void> start({int? port}) async {
    await stop();
    final targetPort = port ?? configService.settings.localApiPort;

    final router = _buildRouter();
    final handler = const Pipeline()
        .addMiddleware(_securityAndCorsMiddleware)
        .addHandler(router.call);

    // Strictly bind to 127.0.0.1 only (Section 3.A & 14)
    _server = await shelf_io.serve(
      handler,
      InternetAddress.loopbackIPv4,
      targetPort,
    );
    _boundPort = _server!.port;
    logger.info('LocalApiServer', 'Started Local HTTP API server', {
      'host': AppConstants.localApiBindHost,
      'port': _boundPort,
    });
    notifyListeners();
  }

  /// Stops the Local HTTP API server cleanly.
  Future<void> stop() async {
    if (_server != null) {
      await _server!.close(force: true);
      _server = null;
      logger.info('LocalApiServer', 'Stopped Local HTTP API server');
      notifyListeners();
    }
  }

  Router _buildRouter() {
    final router = Router();

    // Status
    router.get('/api/status', _handleGetStatus);

    // Printers
    router.get('/api/printers', _handleGetPrinters);
    router.post('/api/printers', _handleCreatePrinter);
    router.patch('/api/printers/<id>', _handleUpdatePrinter);
    router.delete('/api/printers/<id>', _handleDeletePrinter);
    router.post('/api/printers/discover', _handleDiscoverPrinters);
    router.post('/api/printers/<id>/test', _handleTestPrinterById);

    // Printing & Jobs
    router.post('/api/print', _handlePostPrint);
    router.post('/api/print-image', _handlePostPrintImage);
    router.post('/api/test-print', _handlePostTestPrint);
    router.get('/api/jobs', _handleGetJobs);
    router.get('/api/jobs/<id>', _handleGetJobById);
    router.post('/api/jobs/<id>/retry', _handleRetryJob);
    router.post('/api/jobs/<id>/cancel', _handleCancelJob);
    router.post('/api/jobs/<id>/reprint', _handleReprintJob);

    // Pairing
    router.post('/api/pairing/start', _handlePairingStart);
    router.post('/api/pairing/confirm', _handlePairingConfirm);
    router.post('/api/pairing/revoke', _handlePairingRevoke);

    return router;
  }

  Middleware get _securityAndCorsMiddleware {
    return (Handler innerHandler) {
      return (Request request) async {
        // 1. DNS Rebinding protection: Validate Host header is loopback
        final hostHeader = request.headers[HttpHeaders.hostHeader];
        if (!OriginValidator.isValidLoopbackHost(hostHeader)) {
          logger.security(
            'LocalApiServer',
            'Blocked non-loopback Host header (DNS rebinding guard)',
            {'host': hostHeader},
          );
          return _json(403, {
            'success': false,
            'errorCode': 'FORBIDDEN_HOST',
            'message': 'Requests must target 127.0.0.1 or localhost.',
          });
        }

        // 2. Validate Origin header against allowed origins
        final origin = request.headers['origin'];
        final settings = configService.settings;
        if (!OriginValidator.isAllowedOrigin(origin, settings.allowedOrigins)) {
          logger.security(
            'LocalApiServer',
            'Blocked unauthorized Origin header',
            {'origin': origin},
          );
          return _json(403, {
            'success': false,
            'errorCode': 'FORBIDDEN_ORIGIN',
            'message': 'Origin is not permitted by POS Print Agent.',
          });
        }

        // 3. Handle CORS preflight (OPTIONS)
        if (request.method.toUpperCase() == 'OPTIONS') {
          return Response.ok('', headers: _corsHeaders(origin));
        }

        // 4. Rate limiting
        final clientKey = origin ?? 'loopback-client';
        if (!rateLimiter.allowRequest(clientKey)) {
          return _json(429, {
            'success': false,
            'errorCode': 'RATE_LIMIT_EXCEEDED',
            'message': 'Too many requests. Please slow down.',
          }, origin: origin);
        }

        // 5. Authentication guard for protected endpoints
        final path = request.url.path;
        final isPublicEndpoint =
            path == 'api/status' ||
            path == 'api/pairing/start' ||
            path == 'api/pairing/confirm';

        if (!isPublicEndpoint) {
          final authHeader = request.headers[HttpHeaders.authorizationHeader];
          final hasPairedDevices =
              pairingService.listDevices(includeRevoked: false).isNotEmpty;
          final mustEnforceAuth =
              settings.requirePairingAuth ||
              hasPairedDevices ||
              authHeader != null;

          if (mustEnforceAuth) {
            if (authHeader == null ||
                !authHeader.toLowerCase().startsWith('bearer ')) {
              return _json(401, {
                'success': false,
                'errorCode': 'AUTHENTICATION_REQUIRED',
                'message':
                    'Bearer token authentication is required. Pair your POS via /api/pairing/start.',
              }, origin: origin);
            }
            final rawToken = authHeader.substring(7).trim();
            final requiredScope = _requiredScopeForPath(path);
            final verifiedDevice = pairingService.verifyToken(
              rawToken,
              requiredPermission: requiredScope,
            );
            if (verifiedDevice == null) {
              return _json(403, {
                'success': false,
                'errorCode': 'INVALID_OR_REVOKED_CREDENTIAL',
                'message': 'Invalid, expired, or revoked pairing token.',
              }, origin: origin);
            }
          }
        }

        try {
          final response = await innerHandler(request);
          return response.change(headers: _corsHeaders(origin));
        } catch (e, st) {
          logger.error('LocalApiServer', 'Unhandled API error: $e', {
            'path': request.url.path,
            'stack': st.toString(),
          });
          return _json(500, {
            'success': false,
            'errorCode': 'INTERNAL_SERVER_ERROR',
            'message': 'Internal server error occurred.',
          }, origin: origin);
        }
      };
    };
  }

  String _requiredScopeForPath(String path) {
    if (path.startsWith('api/print') || path.startsWith('api/test-print')) {
      return 'print';
    }
    if (path.startsWith('api/printers')) {
      return 'printers';
    }
    if (path.startsWith('api/jobs')) {
      return 'jobs';
    }
    return 'status';
  }

  Future<Response> _handleGetStatus(Request request) async {
    final printers = printerManager.listPrinters();
    final activeDevices = pairingService.listDevices(includeRevoked: false);
    final queueStats = printQueueService.getQueueStatistics();
    final defaultPrinter = printerManager.getDefaultPrinter();

    return _json(200, {
      'success': true,
      'agentStatus': 'online',
      'agentVersion': AppConstants.appVersion,
      'apiVersion': AppConstants.apiVersion,
      'running': isRunning,
      'bindAddress': bindAddress,
      'pairingStatus': {
        'requirePairingAuth': configService.settings.requirePairingAuth,
        'pairedDeviceCount': activeDevices.length,
        'pendingSessionCount': pairingService.pendingSessions.length,
      },
      'printerCount': printers.length,
      'connectedPrinterCount': printers.where((p) => p.isOnline).length,
      'defaultPrinter': defaultPrinter?.toJson(),
      'queueStatus': queueStats,
      'lanOperatingMode': configService.settings.lanOperatingMode.value,
    });
  }

  Future<Response> _handleGetPrinters(Request request) async {
    final printers = printerManager.listPrinters();
    return _json(200, {
      'success': true,
      'count': printers.length,
      'printers': printers.map((p) => p.toJson()).toList(),
    });
  }

  Future<Response> _handleCreatePrinter(Request request) async {
    final body = await _readJsonObject(request);
    if (body == null) {
      return _json(400, {
        'success': false,
        'errorCode': 'MALFORMED_JSON',
        'message': 'Request body must be a valid JSON object.',
      });
    }

    final name = (body['name'] as String?)?.trim() ?? '';
    if (name.isEmpty) {
      return _json(422, {
        'success': false,
        'errorCode': 'VALIDATION_ERROR',
        'message': 'Printer name is required.',
      });
    }

    final connectionType = PrinterConnectionType.fromString(
      (body['connectionType'] as String?) ?? 'os',
    );
    final protocol = PrinterProtocol.fromString(
      (body['protocol'] as String?) ??
          (connectionType == PrinterConnectionType.lan ||
                  connectionType == PrinterConnectionType.wifi
              ? 'raw_tcp'
              : 'os_driver'),
    );
    final rawPaperWidth = body['paperWidth'] ?? body['paperSize'] ?? 80;
    final paperWidth = AppConstants.parsePaperWidthMm(rawPaperWidth);
    if (paperWidth == null) {
      return _json(422, {
        'success': false,
        'errorCode': 'INVALID_PAPER_WIDTH',
        'message': 'paperWidth must be 58, 80, or 210 ("A4").',
      });
    }

    final configMap =
        body['configuration'] is Map<String, dynamic>
            ? body['configuration'] as Map<String, dynamic>
            : <String, dynamic>{};

    final created = printerManager.addPrinter(
      name: name,
      connectionType: connectionType,
      protocol: protocol,
      host: body['host'] as String?,
      port: body['port'] as int?,
      paperWidth: paperWidth,
      isDefault: (body['isDefault'] as bool?) ?? false,
      enabled: (body['enabled'] as bool?) ?? true,
      configuration: PrinterConfiguration.fromJson(configMap),
    );

    return _json(201, {'success': true, 'printer': created.toJson()});
  }

  Future<Response> _handleUpdatePrinter(Request request, String id) async {
    final existing = printerManager.getPrinterById(id);
    if (existing == null) {
      return _json(404, {
        'success': false,
        'errorCode': 'PRINTER_NOT_FOUND',
        'message': 'Printer $id not found.',
      });
    }

    final body = await _readJsonObject(request);
    if (body == null) {
      return _json(400, {
        'success': false,
        'errorCode': 'MALFORMED_JSON',
        'message': 'Request body must be a valid JSON object.',
      });
    }

    int? parsedUpdateWidth;
    if (body['paperWidth'] != null || body['paperSize'] != null) {
      parsedUpdateWidth = AppConstants.parsePaperWidthMm(
        body['paperWidth'] ?? body['paperSize'],
      );
      if (parsedUpdateWidth == null) {
        return _json(422, {
          'success': false,
          'errorCode': 'INVALID_PAPER_WIDTH',
          'message': 'paperWidth must be 58, 80, or 210 ("A4").',
        });
      }
    }

    final updatedConfig =
        body['configuration'] is Map<String, dynamic>
            ? PrinterConfiguration.fromJson(
              body['configuration'] as Map<String, dynamic>,
            )
            : existing.configuration;

    final updatedModel = existing.copyWith(
      name: (body['name'] as String?)?.trim() ?? existing.name,
      connectionType:
          body['connectionType'] is String
              ? PrinterConnectionType.fromString(
                body['connectionType'] as String,
              )
              : existing.connectionType,
      protocol:
          body['protocol'] is String
              ? PrinterProtocol.fromString(body['protocol'] as String)
              : existing.protocol,
      host: body.containsKey('host') ? body['host'] as String? : existing.host,
      port: body.containsKey('port') ? body['port'] as int? : existing.port,
      paperWidth: parsedUpdateWidth ?? existing.paperWidth,
      isDefault: (body['isDefault'] as bool?) ?? existing.isDefault,
      enabled: (body['enabled'] as bool?) ?? existing.enabled,
      configuration: updatedConfig,
      updatedAt: DateTime.now(),
    );

    final saved = printerManager.updatePrinter(updatedModel);
    return _json(200, {'success': true, 'printer': saved?.toJson()});
  }

  Future<Response> _handleDeletePrinter(Request request, String id) async {
    final deleted = printerManager.removePrinter(id);
    if (!deleted) {
      return _json(404, {
        'success': false,
        'errorCode': 'PRINTER_NOT_FOUND',
        'message': 'Printer $id not found.',
      });
    }
    return _json(200, {'success': true, 'message': 'Printer $id deleted.'});
  }

  Future<Response> _handleDiscoverPrinters(Request request) async {
    Map<String, dynamic> body = const {};
    final raw = await request.readAsString();
    if (raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          body = decoded;
        }
      } catch (_) {}
    }

    final candidates = <DiscoveredPrinterCandidate>[];
    final includeOs = (body['includeOs'] as bool?) ?? true;
    if (includeOs) {
      candidates.addAll(await discoveryService.discoverOsAndUsbPrinters());
    }

    final singleHost = (body['host'] as String?)?.trim();
    if (singleHost != null && singleHost.isNotEmpty) {
      candidates.addAll(await discoveryService.probeSingleHost(singleHost));
    }

    final subnetPrefix = (body['subnetPrefix'] as String?)?.trim();
    if (subnetPrefix != null && subnetPrefix.isNotEmpty) {
      try {
        final startHost = (body['startHost'] as int?) ?? 1;
        final endHost = (body['endHost'] as int?) ?? 50;
        final subnetResults = await discoveryService.discoverControlledSubnet(
          subnetPrefix: subnetPrefix,
          startHost: startHost,
          endHost: endHost,
        );
        candidates.addAll(subnetResults);
      } catch (e) {
        return _json(422, {
          'success': false,
          'errorCode': 'INVALID_SUBNET_RANGE',
          'message': e.toString(),
        });
      }
    }

    return _json(200, {
      'success': true,
      'count': candidates.length,
      'discoveredPrinters': candidates.map((c) => c.toJson()).toList(),
    });
  }

  Future<Response> _handleTestPrinterById(Request request, String id) async {
    final printer = printerManager.getPrinterById(id);
    if (printer == null) {
      return _json(404, {
        'success': false,
        'errorCode': 'PRINTER_NOT_FOUND',
        'message': 'Printer $id not found.',
      });
    }

    final payload = printerManager.buildTestReceiptPayload(printer);
    final result = printQueueService.enqueueReceipt(
      payload,
      overridePrinterId: printer.id,
    );

    return _json(202, {
      'success': true,
      'message':
          'Test print job queued for ${printer.name}. (Status submitted indicates OS/printer accepted the job, not physical paper confirmation).',
      'job': result.job.toJson(),
    });
  }

  Future<Response> _handlePostTestPrint(Request request) async {
    String? printerId;
    final raw = await request.readAsString();
    if (raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          printerId = decoded['printerId'] as String?;
        }
      } catch (_) {}
    }

    final printer =
        printerId != null
            ? printerManager.getPrinterById(printerId)
            : printerManager.getDefaultPrinter();

    if (printer == null) {
      return _json(404, {
        'success': false,
        'errorCode': 'NO_DEFAULT_PRINTER',
        'message': 'No default or matching printer is configured.',
      });
    }

    final payload = printerManager.buildTestReceiptPayload(printer);
    final result = printQueueService.enqueueReceipt(
      payload,
      overridePrinterId: printer.id,
    );

    return _json(202, {
      'success': true,
      'message': 'Test print job queued.',
      'job': result.job.toJson(),
    });
  }

  Future<Response> _handlePostPrint(Request request) async {
    return _enqueueValidatedReceiptRequest(
      request,
      allowAutoJobIdForImage: false,
    );
  }

  Future<Response> _handlePostPrintImage(Request request) async {
    return _enqueueValidatedReceiptRequest(
      request,
      allowAutoJobIdForImage: true,
    );
  }

  Future<Response> _enqueueValidatedReceiptRequest(
    Request request, {
    required bool allowAutoJobIdForImage,
  }) async {
    final rawBody = await request.readAsString();
    final validation = ReceiptValidator.validateRawJson(
      rawBody,
      allowAutoJobIdForImage: allowAutoJobIdForImage,
    );

    if (!validation.isValid || validation.payload == null) {
      final status =
          validation.errorCode == 'PAYLOAD_TOO_LARGE'
              ? 413
              : validation.errorCode == 'MALFORMED_JSON'
              ? 400
              : 422;
      return _json(status, {
        'success': false,
        'errorCode': validation.errorCode ?? 'VALIDATION_ERROR',
        'message': 'Receipt validation failed.',
        'errors': validation.errors,
      });
    }

    final enqueueResult = printQueueService.enqueueReceipt(validation.payload!);
    final job = enqueueResult.job;

    if (enqueueResult.isDuplicate) {
      return _json(200, {
        'success': true,
        'isDuplicate': true,
        'errorCode': 'DUPLICATE_JOB_ID',
        'message':
            'A print job with jobId "${job.id}" already exists. Returning existing job status without re-submitting.',
        'job': job.toJson(),
      });
    }

    if (job.status == PrintJobStatus.failed) {
      return _json(503, {
        'success': false,
        'errorCode': 'PRINTER_UNAVAILABLE',
        'message': job.errorMessage ?? 'No active printer available.',
        'job': job.toJson(),
      });
    }

    return _json(202, {
      'success': true,
      'isDuplicate': false,
      'isImageReceipt': validation.payload!.isImageReceipt,
      'message':
          'Print job queued. Check /api/jobs/${job.id} for submission status.',
      'job': job.toJson(),
    });
  }

  Future<Response> _handleGetJobs(Request request) async {
    final params = request.url.queryParameters;
    final statusParam = params['status'];
    final printerId = params['printerId'];
    final search = params['q'] ?? params['billNumber'];
    final limit = int.tryParse(params['limit'] ?? '') ?? 100;

    List<PrintJobStatus>? statuses;
    if (statusParam != null && statusParam.trim().isNotEmpty) {
      statuses = [PrintJobStatus.fromString(statusParam)];
    }

    final jobs = printQueueService.listJobs(
      statuses: statuses,
      printerId: printerId,
      searchBillNumber: search,
      limit: limit.clamp(1, 500),
    );

    return _json(200, {
      'success': true,
      'count': jobs.length,
      'jobs': jobs.map((j) => j.toJson()).toList(),
    });
  }

  Future<Response> _handleGetJobById(Request request, String id) async {
    final job = printQueueService.getJob(id);
    if (job == null) {
      return _json(404, {
        'success': false,
        'errorCode': 'JOB_NOT_FOUND',
        'message': 'Print job $id not found.',
      });
    }

    return _json(200, {
      'success': true,
      'job': job.toJson(includeSnapshot: true),
    });
  }

  Future<Response> _handleRetryJob(Request request, String id) async {
    try {
      final job = printQueueService.retryJob(id);
      return _json(200, {
        'success': true,
        'message': 'Job $id scheduled for retry.',
        'job': job.toJson(),
      });
    } on StateError catch (e) {
      return _json(409, {
        'success': false,
        'errorCode': 'UNSAFE_JOB_RETRY',
        'message': e.message,
      });
    }
  }

  Future<Response> _handleCancelJob(Request request, String id) async {
    try {
      final job = printQueueService.cancelJob(id);
      return _json(200, {
        'success': true,
        'message': 'Job $id cancelled.',
        'job': job.toJson(),
      });
    } on StateError catch (e) {
      return _json(409, {
        'success': false,
        'errorCode': 'UNSAFE_JOB_CANCEL',
        'message': e.message,
      });
    }
  }

  Future<Response> _handleReprintJob(Request request, String id) async {
    String? overridePrinterId;
    final raw = await request.readAsString();
    if (raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          overridePrinterId = decoded['printerId'] as String?;
        }
      } catch (_) {}
    }

    try {
      final newJob = printQueueService.reprintJob(
        id,
        overridePrinterId: overridePrinterId,
      );
      return _json(201, {
        'success': true,
        'message':
            'Created manual reprint job ${newJob.id} for bill ${newJob.billNumber}.',
        'sourceJobId': id,
        'job': newJob.toJson(),
      });
    } on StateError catch (e) {
      return _json(409, {
        'success': false,
        'errorCode': 'UNSAFE_JOB_REPRINT',
        'message': e.message,
      });
    }
  }

  Future<Response> _handlePairingStart(Request request) async {
    final body = await _readJsonObject(request);
    if (body == null) {
      return _json(400, {
        'success': false,
        'errorCode': 'MALFORMED_JSON',
        'message': 'Request body must be a valid JSON object.',
      });
    }

    final deviceName = (body['deviceName'] as String?)?.trim() ?? '';
    if (deviceName.isEmpty) {
      return _json(422, {
        'success': false,
        'errorCode': 'VALIDATION_ERROR',
        'message': 'deviceName is required to start pairing.',
      });
    }

    List<String>? permissions;
    if (body['permissions'] is List) {
      permissions =
          (body['permissions'] as List).map((e) => e.toString()).toList();
    }

    final session = pairingService.startPairing(
      deviceName: deviceName,
      permissions: permissions,
      origin: request.headers['origin'],
    );

    return _json(200, {
      'success': true,
      'sessionId': session.sessionId,
      'deviceName': session.deviceName,
      'expiresAt': session.expiresAt.toIso8601String(),
      'message':
          'Check the POS Print Agent desktop application for the 6-digit pairing confirmation code.',
    });
  }

  Future<Response> _handlePairingConfirm(Request request) async {
    final body = await _readJsonObject(request);
    if (body == null) {
      return _json(400, {
        'success': false,
        'errorCode': 'MALFORMED_JSON',
        'message': 'Request body must be a valid JSON object.',
      });
    }

    final sessionId = (body['sessionId'] as String?)?.trim() ?? '';
    final pairingCode = (body['pairingCode'] as String?)?.trim() ?? '';
    if (sessionId.isEmpty || pairingCode.isEmpty) {
      return _json(422, {
        'success': false,
        'errorCode': 'VALIDATION_ERROR',
        'message': 'sessionId and pairingCode are required.',
      });
    }

    try {
      final result = pairingService.confirmPairing(
        sessionId: sessionId,
        pairingCode: pairingCode,
      );
      return _json(200, {
        'success': true,
        'deviceId': result.device.id,
        'deviceName': result.device.deviceName,
        'token': result.plainTextToken,
        'permissions': result.device.permissions,
        'createdAt': result.device.createdAt.toIso8601String(),
      });
    } on ArgumentError catch (e) {
      return _json(401, {
        'success': false,
        'errorCode': 'INVALID_PAIRING_CODE',
        'message': e.message.toString(),
      });
    } on StateError catch (e) {
      return _json(404, {
        'success': false,
        'errorCode': 'PAIRING_SESSION_EXPIRED',
        'message': e.message,
      });
    }
  }

  Future<Response> _handlePairingRevoke(Request request) async {
    final body = await _readJsonObject(request) ?? <String, dynamic>{};
    final deviceId = body['deviceId'] as String?;
    String? rawToken = body['token'] as String?;

    if (rawToken == null) {
      final authHeader = request.headers[HttpHeaders.authorizationHeader];
      if (authHeader != null &&
          authHeader.toLowerCase().startsWith('bearer ')) {
        rawToken = authHeader.substring(7).trim();
      }
    }

    final revoked = pairingService.revoke(
      deviceId: deviceId,
      rawToken: rawToken,
    );

    if (!revoked) {
      return _json(404, {
        'success': false,
        'errorCode': 'DEVICE_NOT_FOUND',
        'message': 'No matching active paired device found to revoke.',
      });
    }

    return _json(200, {
      'success': true,
      'message': 'Device credential revoked successfully.',
    });
  }

  Future<Map<String, dynamic>?> _readJsonObject(Request request) async {
    final raw = await request.readAsString();
    if (utf8.encode(raw).length > AppConstants.maxRequestBodyBytes) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
    } catch (_) {}
    return null;
  }

  Map<String, String> _corsHeaders(String? origin) {
    final effectiveOrigin =
        origin != null && origin.isNotEmpty ? origin : 'http://localhost';
    return {
      'Access-Control-Allow-Origin': effectiveOrigin,
      'Access-Control-Allow-Methods': 'GET, POST, PATCH, DELETE, OPTIONS',
      'Access-Control-Allow-Headers':
          'Origin, Content-Type, Accept, Authorization, X-Requested-With',
      'Access-Control-Max-Age': '3600',
      'Vary': 'Origin',
      'X-Content-Type-Options': 'nosniff',
      'X-Frame-Options': 'DENY',
    };
  }

  Response _json(int statusCode, Map<String, Object?> data, {String? origin}) {
    return Response(
      statusCode,
      body: jsonEncode(data),
      headers: {
        HttpHeaders.contentTypeHeader: 'application/json; charset=utf-8',
        ..._corsHeaders(origin),
      },
    );
  }
}
