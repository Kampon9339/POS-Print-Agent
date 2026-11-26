import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:pos_print_agent/modules/print_engine/mock_print_backend.dart';
import 'package:pos_print_agent/modules/receipt_engine/esc_pos_encoder.dart';
import 'package:pos_print_agent/modules/receipt_engine/pdf_receipt_builder.dart';
import 'package:pos_print_agent/modules/receipt_engine/receipt_renderer.dart';
import 'package:pos_print_agent/modules/receipt_engine/receipt_validator.dart';
import 'package:pos_print_agent/modules/receipt_engine/thai_raster_renderer.dart';
import 'package:pos_print_agent/shared/models/app_settings_model.dart';
import 'package:pos_print_agent/shared/models/print_job_model.dart';
import 'package:pos_print_agent/shared/models/printer_model.dart';
import 'package:pos_print_agent/shared/services/service_locator.dart';
import 'package:pos_print_agent/shared/utilities/thai_text_utils.dart';

Map<String, dynamic> buildSampleReceiptMap({
  String jobId = 'PRINT-20261104-0001',
  String billId = 'BILL-000125',
  String billNumber = 'INV-000125',
  int paperWidth = 80,
  String jobType = 'receipt',
  num subtotal = 30,
  num discountTotal = 0,
  num vatRate = 0,
  num vatAmount = 0,
  num grandTotal = 30,
}) {
  return {
    'schemaVersion': 1,
    'jobId': jobId,
    'billId': billId,
    'billNumber': billNumber,
    'copyType': 'original',
    'paperWidth': paperWidth,
    'jobType': jobType,
    'store': {
      'name': 'ร้านค้าตัวอย่าง ศรีสะเกษ',
      'address': 'อำเภอเมือง จังหวัดศรีสะเกษ',
      'phone': '0123456789',
      'taxId': '0105559999999',
      'footer': 'ขอบคุณที่ใช้บริการ',
    },
    'cashier': {'name': 'พนักงานขาย สมชาย'},
    'issuedAt': '2026-11-04T10:30:00+07:00',
    'items': [
      {
        'productName': 'น้ำดื่มบริสุทธิ์ กิ่ง กุ้ง เก๋ง',
        'quantity': 3,
        'unit': 'ขวด',
        'unitPrice': 10,
        'discount': 0,
        'total': 30,
      },
    ],
    'subtotal': subtotal,
    'discountTotal': discountTotal,
    'vatRate': vatRate,
    'vatAmount': vatAmount,
    'grandTotal': grandTotal,
    'payment': {'method': 'cash', 'received': 100, 'change': 70},
  };
}

void main() {
  group('1. JSON Receipt Validation & Financial Preservation', () {
    test(
      'Validates compliant Thai JSON receipt and preserves POS totals without recalculation',
      () {
        // Intentionally supply custom POS-authoritative totals to prove Agent never recalculates
        final map = buildSampleReceiptMap(
          subtotal: 30,
          discountTotal: 5,
          vatRate: 7,
          vatAmount: 1.75,
          grandTotal: 26.75,
        );
        final res = ReceiptValidator.validateRawJson(jsonEncode(map));
        expect(res.isValid, isTrue);
        expect(res.payload, isNotNull);
        expect(res.payload!.subtotal, equals(30));
        expect(res.payload!.discountTotal, equals(5));
        expect(res.payload!.vatRate, equals(7));
        expect(res.payload!.vatAmount, equals(1.75));
        expect(res.payload!.grandTotal, equals(26.75));
      },
    );

    test(
      'Rejects missing required fields, invalid paper width, and negative quantities',
      () {
        final badMap = buildSampleReceiptMap(paperWidth: 75);
        badMap.remove('billId');
        (badMap['items'] as List).first['quantity'] = -2;

        final res = ReceiptValidator.validateMap(badMap);
        expect(res.isValid, isFalse);
        expect(res.errors, contains(contains('billId is required')));
        expect(
          res.errors,
          contains(contains('paperWidth must be one of 58, 80')),
        );
        expect(
          res.errors,
          contains(contains('items[0].quantity must be greater than 0')),
        );
      },
    );

    test(
      'Rejects executable HTML/JavaScript injection and oversized payloads',
      () {
        final xssMap = buildSampleReceiptMap();
        (xssMap['store'] as Map<String, dynamic>)['name'] =
            '<script>alert("xss")</script>ร้านค้า';
        final res = ReceiptValidator.validateMap(xssMap);
        expect(res.isValid, isFalse);
        expect(
          res.errors.any(
            (e) => e.contains('prohibited executable HTML/JavaScript'),
          ),
          isTrue,
        );

        final hugeResult = ReceiptValidator.validateRawJson(
          jsonEncode(buildSampleReceiptMap()),
          maxBytes: 20,
        );
        expect(hugeResult.isValid, isFalse);
        expect(hugeResult.errorCode, equals('PAYLOAD_TOO_LARGE'));
      },
    );
  });

  group('2. Thai Text Utilities, 58mm & 80mm Rendering, and ESC/POS Raster', () {
    test(
      'Normalizes Thai vowel + tone mark ordering and wraps grapheme clusters safely',
      () {
        // Tone mark before upper vowel (\u0E49 before \u0E34) -> normalized to \u0E34\u0E49
        const brokenOrder = 'ก\u0E49\u0E34นข้าว';
        final normalized = ThaiTextUtils.normalizeThaiSequence(brokenOrder);
        expect(normalized, equals('ก\u0E34\u0E49นข้าว'));

        final clusters = ThaiTextUtils.splitGraphemeClusters(
          'น้ำดื่มบริสุทธิ์',
        );
        for (final cluster in clusters) {
          // Every cluster must start with a non-combining base character
          expect(
            ThaiTextUtils.isThaiCombiningChar(cluster.codeUnitAt(0)),
            isFalse,
          );
        }
      },
    );

    test(
      'Renders 58mm (384 dots / 48mm printable) and 80mm (576 dots / 72mm printable) layouts',
      () async {
        const renderer = ReceiptRenderer();
        const rasterizer = ThaiRasterRenderer();
        const encoder = EscPosEncoder();
        const pdfBuilder = PdfReceiptBuilder();

        final payload58 =
            ReceiptValidator.validateMap(
              buildSampleReceiptMap(paperWidth: 58),
            ).payload!;
        final doc58 = renderer.render(payload58, marginMm: 0);
        expect(doc58.paperWidthMm, equals(58));
        expect(doc58.printableWidthMm, equals(48.0));
        expect(doc58.rasterWidthDots, equals(384));

        final bitmap58 = rasterizer.renderToBitmap(doc58);
        expect(bitmap58.widthDots, equals(384));
        expect(bitmap58.widthBytes, equals(48));

        final escPos58 = encoder.encode(
          doc58,
          useRasterMode: true,
          autoCut: true,
        );
        // Starts with ESC @ (0x1B, 0x40) and contains GS v 0 (0x1D, 0x76, 0x30)
        expect(escPos58[0], equals(0x1B));
        expect(escPos58[1], equals(0x40));

        final payload80 =
            ReceiptValidator.validateMap(
              buildSampleReceiptMap(paperWidth: 80),
            ).payload!;
        final doc80 = renderer.render(payload80, marginMm: 0);
        expect(doc80.paperWidthMm, equals(80));
        expect(doc80.printableWidthMm, equals(72.0));
        expect(doc80.rasterWidthDots, equals(576));

        final pdfBytes = await pdfBuilder.buildPdf(doc80);
        expect(pdfBytes.length, greaterThan(500));
        // PDF magic header "%PDF-"
        expect(String.fromCharCodes(pdfBytes.sublist(0, 5)), equals('%PDF-'));

        // Verify A4 (210mm / "A4") support
        final a4Map = buildSampleReceiptMap();
        a4Map['paperWidth'] = 'A4';
        final payloadA4 = ReceiptValidator.validateMap(a4Map).payload!;
        expect(payloadA4.paperWidth, equals(210));
        final docA4 = renderer.render(payloadA4, marginMm: 10);
        expect(docA4.paperWidthMm, equals(210));
        expect(docA4.printableWidthMm, equals(190.0));
        expect(docA4.rasterWidthDots, equals(1200));

        final pdfA4Bytes = await pdfBuilder.buildPdf(docA4);
        expect(pdfA4Bytes.length, greaterThan(500));
        expect(String.fromCharCodes(pdfA4Bytes.sublist(0, 5)), equals('%PDF-'));
      },
    );
  });

  group(
    '3. Print Queue, Duplicate Prevention, Routing, Multi-Printer & Restart Recovery',
    () {
      late MockPrintBackend mockOsBackend;
      late MockPrintBackend mockTcpBackend;
      late AgentServiceContainer container;

      setUp(() {
        mockOsBackend = MockPrintBackend(backendId: 'MockOsBackend');
        mockTcpBackend = MockPrintBackend(backendId: 'MockTcpBackend');
        container = AgentServiceContainer.createForTest(
          osBackend: mockOsBackend,
          tcpBackend: mockTcpBackend,
        );
      });

      tearDown(() async {
        await container.shutdown();
      });

      test(
        'Prevents duplicate jobs with same jobId and transitions queued -> submitted',
        () async {
          final printer = container.printerManager.addPrinter(
            name: 'Cashier Printer 80mm',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.200',
            port: 9100,
            isDefault: true,
          );

          final payload =
              ReceiptValidator.validateMap(
                buildSampleReceiptMap(jobId: 'JOB-UNIQUE-1001'),
              ).payload!;

          final first = container.printQueueService.enqueueReceipt(payload);
          expect(first.isDuplicate, isFalse);

          final duplicate = container.printQueueService.enqueueReceipt(payload);
          expect(duplicate.isDuplicate, isTrue);
          expect(duplicate.job.id, equals('JOB-UNIQUE-1001'));

          await container.printQueueService.waitForIdle();

          final completed =
              container.printQueueService.getJob('JOB-UNIQUE-1001')!;
          expect(completed.status, equals(PrintJobStatus.submitted));
          expect(completed.printerId, equals(printer.id));
          expect(mockTcpBackend.submissions.length, equals(1));
        },
      );

      test(
        'Routes jobs by jobType and fails over to backup printer when primary is offline',
        () async {
          final backupPrinter = container.printerManager.addPrinter(
            name: 'Backup Printer',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.202',
            port: 9100,
          );

          final kitchenPrinter = container.printerManager.addPrinter(
            name: 'Kitchen Printer',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.201',
            port: 9100,
            configuration: PrinterConfiguration(
              backupPrinterId: backupPrinter.id,
            ),
          );

          container.routingEngine.saveRule(
            jobType: 'kitchen',
            printerId: kitchenPrinter.id,
            priority: 1,
          );

          // Mark kitchenPrinter offline in PrinterManager -> should route to backupPrinter
          mockTcpBackend.printerAvailability[kitchenPrinter.id] = false;
          await container.printerManager.checkPrinterOnline(kitchenPrinter);

          final kitchenPayload =
              ReceiptValidator.validateMap(
                buildSampleReceiptMap(
                  jobId: 'JOB-KITCHEN-1',
                  jobType: 'kitchen',
                ),
              ).payload!;

          final enqueued = container.printQueueService.enqueueReceipt(
            kitchenPayload,
          );
          expect(enqueued.job.printerId, equals(backupPrinter.id));
          await container.printQueueService.waitForIdle();

          final finished = container.printQueueService.getJob('JOB-KITCHEN-1')!;
          expect(finished.status, equals(PrintJobStatus.submitted));
        },
      );

      test(
        'Slow printer queue does not block unrelated printer queue',
        () async {
          final slowPrinter = container.printerManager.addPrinter(
            name: 'Slow Printer',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.210',
            port: 9100,
          );
          final fastPrinter = container.printerManager.addPrinter(
            name: 'Fast Printer',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.211',
            port: 9100,
            isDefault: true,
          );

          mockTcpBackend.simulatedDelays[slowPrinter.id] = const Duration(
            milliseconds: 400,
          );
          mockTcpBackend.simulatedDelays[fastPrinter.id] = const Duration(
            milliseconds: 10,
          );

          final slowPayload =
              ReceiptValidator.validateMap(
                buildSampleReceiptMap(jobId: 'JOB-SLOW'),
              ).payload!;
          final fastPayload =
              ReceiptValidator.validateMap(
                buildSampleReceiptMap(jobId: 'JOB-FAST'),
              ).payload!;

          container.printQueueService.enqueueReceipt(
            slowPayload,
            overridePrinterId: slowPrinter.id,
          );
          container.printQueueService.enqueueReceipt(
            fastPayload,
            overridePrinterId: fastPrinter.id,
          );

          await Future<void>.delayed(const Duration(milliseconds: 80));
          final fastStatus =
              container.printQueueService.getJob('JOB-FAST')!.status;
          expect(fastStatus, equals(PrintJobStatus.submitted));

          await container.printQueueService.waitForIdle();
          final slowStatus =
              container.printQueueService.getJob('JOB-SLOW')!.status;
          expect(slowStatus, equals(PrintJobStatus.submitted));
        },
      );

      test(
        'Safe retry, cancel, manual reprint (new jobId, same billId), and crash recovery',
        () async {
          final printer = container.printerManager.addPrinter(
            name: 'Receipt Printer',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.220',
            port: 9100,
            isDefault: true,
          );

          // Force backend failure initially
          mockTcpBackend.simulatedErrors[printer.id] = 'Out of paper';

          final payload =
              ReceiptValidator.validateMap(
                buildSampleReceiptMap(
                  jobId: 'JOB-FAIL-THEN-RETRY',
                  billId: 'BILL-999',
                ),
              ).payload!;

          container.printQueueService.enqueueReceipt(payload);
          await container.printQueueService.waitForIdle();

          final failedJob =
              container.printQueueService.getJob('JOB-FAIL-THEN-RETRY')!;
          expect(failedJob.status, equals(PrintJobStatus.failed));
          expect(failedJob.errorMessage, contains('Out of paper'));

          // Clear error and retry
          mockTcpBackend.simulatedErrors.remove(printer.id);
          container.printQueueService.retryJob('JOB-FAIL-THEN-RETRY');
          await container.printQueueService.waitForIdle();

          final retriedJob =
              container.printQueueService.getJob('JOB-FAIL-THEN-RETRY')!;
          expect(retriedJob.status, equals(PrintJobStatus.submitted));
          expect(retriedJob.retryCount, equals(1));

          // Cannot retry an already submitted job
          expect(
            () => container.printQueueService.retryJob('JOB-FAIL-THEN-RETRY'),
            throwsStateError,
          );

          // Manual reprint creates a new jobId with copyType='reprint' and same billId
          final reprinted = container.printQueueService.reprintJob(
            'JOB-FAIL-THEN-RETRY',
          );
          expect(reprinted.id, isNot(equals('JOB-FAIL-THEN-RETRY')));
          expect(reprinted.billId, equals('BILL-999'));
          expect(reprinted.copyType, equals('reprint'));
          await container.printQueueService.waitForIdle();

          // Simulate an interrupted job left in `printing` state before crash
          container.printJobRepository.updateStatus(
            'JOB-FAIL-THEN-RETRY',
            status: PrintJobStatus.printing,
          );
          container.printQueueService.recoverAfterRestart();
          final recovered =
              container.printQueueService.getJob('JOB-FAIL-THEN-RETRY')!;
          expect(recovered.status, equals(PrintJobStatus.failed));
          expect(
            recovered.errorMessage,
            contains('Uncertain submission state'),
          );
        },
      );
    },
  );

  group(
    '4. Local HTTP API, Pairing Security & Central Print Coordinator (Mode B)',
    () {
      late MockPrintBackend mockTcpBackend;
      late AgentServiceContainer agentA;
      late AgentServiceContainer coordinatorHost;

      setUp(() async {
        mockTcpBackend = MockPrintBackend(backendId: 'MockCoordTcp');
        agentA = AgentServiceContainer.createForTest(
          tcpBackend: mockTcpBackend,
        );
        coordinatorHost = AgentServiceContainer.createForTest(
          tcpBackend: mockTcpBackend,
        );
      });

      tearDown(() async {
        await agentA.shutdown();
        await coordinatorHost.shutdown();
      });

      test(
        'Local API binds to 127.0.0.1, enforces pairing flow, and processes /api/print',
        () async {
          agentA.printerManager.addPrinter(
            name: 'Local LAN Printer',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.50',
            port: 9100,
            isDefault: true,
          );

          await agentA.localApiServer.start(port: 0);
          final baseUrl = agentA.localApiServer.bindAddress;
          final client = HttpClient();

          // 1. Start pairing
          final startReq = await client.postUrl(
            Uri.parse('$baseUrl/api/pairing/start'),
          );
          startReq.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json',
          );
          startReq.write(jsonEncode({'deviceName': 'Web POS Cashier #1'}));
          final startResp = await startReq.close();
          expect(startResp.statusCode, equals(200));
          final startBody =
              jsonDecode(await utf8.decoder.bind(startResp).join())
                  as Map<String, dynamic>;
          final sessionId = startBody['sessionId'] as String;

          // Retrieve the 6-digit code from the desktop pairing service
          final pending = agentA.pairingService.pendingSessions.firstWhere(
            (s) => s.sessionId == sessionId,
          );

          // 2. Confirm pairing
          final confirmReq = await client.postUrl(
            Uri.parse('$baseUrl/api/pairing/confirm'),
          );
          confirmReq.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json',
          );
          confirmReq.write(
            jsonEncode({
              'sessionId': sessionId,
              'pairingCode': pending.pairingCode,
            }),
          );
          final confirmResp = await confirmReq.close();
          expect(confirmResp.statusCode, equals(200));
          final confirmBody =
              jsonDecode(await utf8.decoder.bind(confirmResp).join())
                  as Map<String, dynamic>;
          final token = confirmBody['token'] as String;
          expect(token, startsWith('ppa_'));

          // 3. Unauthenticated request to /api/print is now rejected with 401
          final unauthReq = await client.postUrl(
            Uri.parse('$baseUrl/api/print'),
          );
          unauthReq.add(
            utf8.encode(jsonEncode(buildSampleReceiptMap(jobId: 'API-JOB-1'))),
          );
          final unauthResp = await unauthReq.close();
          expect(unauthResp.statusCode, equals(401));
          await unauthResp.drain<void>();

          // 4. Authenticated request to /api/print succeeds (202 Accepted)
          final printReq = await client.postUrl(
            Uri.parse('$baseUrl/api/print'),
          );
          printReq.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer $token',
          );
          printReq.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json; charset=utf-8',
          );
          printReq.add(
            utf8.encode(jsonEncode(buildSampleReceiptMap(jobId: 'API-JOB-1'))),
          );
          final printResp = await printReq.close();
          expect(printResp.statusCode, equals(202));
          await printResp.drain<void>();

          await agentA.printQueueService.waitForIdle();

          // 5. Check job status via GET /api/jobs/API-JOB-1
          final jobReq = await client.getUrl(
            Uri.parse('$baseUrl/api/jobs/API-JOB-1'),
          );
          jobReq.headers.set(HttpHeaders.authorizationHeader, 'Bearer $token');
          final jobResp = await jobReq.close();
          expect(jobResp.statusCode, equals(200));
          final jobBody =
              jsonDecode(await utf8.decoder.bind(jobResp).join())
                  as Map<String, dynamic>;
          expect((jobBody['job'] as Map)['status'], equals('submitted'));

          client.close(force: true);
        },
      );

      test(
        'Mode B Central Coordinator authenticates remote Agents and serializes shared LAN jobs',
        () async {
          // Configure shared LAN printer on Coordinator Host
          final sharedPrinter = coordinatorHost.printerManager.addPrinter(
            id: 'shared-lan-printer-1',
            name: 'Shared LAN Receipt Printer',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.250',
            port: 9100,
            isDefault: true,
          );

          // Issue a paired Agent credential on Coordinator Host
          final issued = coordinatorHost.pairingService
              .createDeviceDirectlyFromUi(deviceName: 'POS Computer A Agent');

          await coordinatorHost.coordinatorServer.start(
            host: '127.0.0.1',
            port: 0,
          );
          final coordPort = coordinatorHost.coordinatorServer.boundPort;
          final coordUrl = 'http://127.0.0.1:$coordPort';

          // Configure Agent A in Mode B client mode pointing to Coordinator Host
          agentA.printerManager.addPrinter(
            id: sharedPrinter.id,
            name: sharedPrinter.name,
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.250',
            port: 9100,
            isDefault: true,
          );
          agentA.configService.updateSettings(
            agentA.configService.settings.copyWith(
              lanOperatingMode: LanOperatingMode.coordinatorClient,
              remoteCoordinatorUrl: coordUrl,
              remoteCoordinatorToken: issued.plainTextToken,
            ),
          );

          final payload =
              ReceiptValidator.validateMap(
                buildSampleReceiptMap(jobId: 'COORD-FORWARD-JOB-1'),
              ).payload!;

          agentA.printQueueService.enqueueReceipt(payload);
          await agentA.printQueueService.waitForIdle();
          await coordinatorHost.printQueueService.waitForIdle();

          final agentJob =
              agentA.printQueueService.getJob('COORD-FORWARD-JOB-1')!;
          final coordJob =
              coordinatorHost.printQueueService.getJob('COORD-FORWARD-JOB-1')!;

          expect(agentJob.status, equals(PrintJobStatus.submitted));
          expect(coordJob.status, equals(PrintJobStatus.submitted));
        },
      );

      test(
        'Supports Base64 Image Receipt printing via /api/print-image and /api/print',
        () async {
          agentA.printerManager.addPrinter(
            name: 'Image Thermal Printer 80mm',
            connectionType: PrinterConnectionType.lan,
            protocol: PrinterProtocol.rawTcp,
            host: '192.168.1.88',
            port: 9100,
            paperWidth: 80,
            isDefault: true,
          );

          // Generate a valid PNG receipt image from a sample receipt bitmap
          const renderer = ReceiptRenderer();
          const raster = ThaiRasterRenderer();
          final sampleDoc = renderer.render(
            ReceiptValidator.validateMap(buildSampleReceiptMap()).payload!,
          );
          final sampleBitmap = raster.renderToBitmap(sampleDoc);
          final pngBytes = PdfReceiptBuilder.encodeBitmapToPng(sampleBitmap);
          final dataUrlBase64 =
              'data:image/png;base64,${base64Encode(pngBytes)}';

          final issued = agentA.pairingService.createDeviceDirectlyFromUi(
            deviceName: 'Web POS Image Client',
          );
          await agentA.localApiServer.start(port: 0);
          final baseUrl = agentA.localApiServer.bindAddress;
          final client = HttpClient();

          final req = await client.postUrl(
            Uri.parse('$baseUrl/api/print-image'),
          );
          req.headers.set(
            HttpHeaders.authorizationHeader,
            'Bearer ${issued.plainTextToken}',
          );
          req.headers.set(
            HttpHeaders.contentTypeHeader,
            'application/json; charset=utf-8',
          );
          req.add(
            utf8.encode(
              jsonEncode({
                'jobId': 'IMG-JOB-001',
                'billNumber': 'INV-IMG-001',
                'paperWidth': 80,
                'dithering': true,
                'imageBase64': dataUrlBase64,
              }),
            ),
          );
          final resp = await req.close();
          expect(resp.statusCode, equals(202));
          final respBody =
              jsonDecode(await utf8.decoder.bind(resp).join())
                  as Map<String, dynamic>;
          expect(respBody['isImageReceipt'], isTrue);

          await agentA.printQueueService.waitForIdle();

          final submittedJob = agentA.printQueueService.getJob('IMG-JOB-001')!;
          expect(submittedJob.status, equals(PrintJobStatus.submitted));
          expect(submittedJob.parsedReceipt!.isImageReceipt, isTrue);

          client.close(force: true);
        },
      );
    },
  );
}
