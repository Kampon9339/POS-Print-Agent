import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/configuration/app_config_service.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/models/app_settings_model.dart';
import '../../shared/models/print_job_model.dart';
import '../../shared/models/receipt_payload.dart';
import '../print_routing/print_routing_engine.dart';
import '../printer_manager/printer_manager.dart';
import '../receipt_engine/receipt_renderer.dart';
import 'print_job_repository.dart';

/// Result of submitting a receipt into the persistent print queue.
class EnqueueJobResult {
  final PrintJobModel job;
  final bool isDuplicate;

  const EnqueueJobResult({required this.job, required this.isDuplicate});
}

/// Manages the persistent SQLite print queue with per-printer serialization,
/// duplicate job prevention, crash recovery, and safe retry/cancel/reprint.
class PrintQueueService extends ChangeNotifier {
  final PrintJobRepository repository;
  final PrinterManager printerManager;
  final PrintRoutingEngine routingEngine;
  final ReceiptRenderer receiptRenderer;
  final AppConfigService configService;
  final AppLogger logger;
  final Uuid _uuid = const Uuid();

  /// Active per-printer worker futures so each physical printer processes
  /// its queue sequentially while different printers run concurrently.
  final Map<String, Future<void>> _activePrinterWorkers = {};
  bool _isShuttingDown = false;

  PrintQueueService({
    required this.repository,
    required this.printerManager,
    required this.routingEngine,
    required this.configService,
    required this.logger,
    this.receiptRenderer = const ReceiptRenderer(),
  });

  /// Performs startup crash recovery:
  /// 1. Marks any uncertain in-flight (`rendering`, `printing`) jobs as `failed`
  ///    so they are never automatically resubmitted.
  /// 2. Resumes any jobs that were still in `queued` state.
  void recoverAfterRestart() {
    final interruptedCount = repository.markInterruptedJobsFailedOnStartup();
    if (interruptedCount > 0) {
      logger.warn(
        'PrintQueue',
        'Marked interrupted in-flight jobs as failed on startup',
        {'interruptedCount': interruptedCount},
      );
    }

    final queuedJobs = repository.listJobs(statuses: [PrintJobStatus.queued]);
    final printerIds = queuedJobs.map((j) => j.printerId).toSet();
    for (final printerId in printerIds) {
      _schedulePrinterWorker(printerId);
    }
    notifyListeners();
  }

  /// Enqueues a validated [ReceiptPayload].
  /// If a job with the same `jobId` already exists, returns the existing job
  /// with `isDuplicate = true` without creating or printing a duplicate.
  EnqueueJobResult enqueueReceipt(
    ReceiptPayload payload, {
    String? overridePrinterId,
  }) {
    final existing = repository.findById(payload.jobId);
    if (existing != null) {
      logger.info(
        'PrintQueue',
        'Duplicate jobId prevented; returning existing job status',
        {'jobId': payload.jobId, 'existingStatus': existing.status.value},
      );
      return EnqueueJobResult(job: existing, isDuplicate: true);
    }

    final resolvedPrinter = routingEngine.resolvePrinterForReceipt(
      payload,
      overridePrinterId: overridePrinterId,
    );

    final now = DateTime.now();
    if (resolvedPrinter == null) {
      final failedNoPrinter = PrintJobModel(
        id: payload.jobId,
        billId: payload.billId,
        billNumber: payload.billNumber,
        printerId: overridePrinterId ?? payload.targetPrinterId ?? 'unassigned',
        status: PrintJobStatus.failed,
        copyType: payload.copyType,
        retryCount: 0,
        receiptSnapshot: payload.toRawJson(),
        errorMessage: 'ไม่พบเครื่องพิมพ์ที่เปิดใช้งานสำหรับการพิมพ์ใบเสร็จนี้',
        createdAt: now,
        updatedAt: now,
      );
      repository.insert(failedNoPrinter);
      logger.error(
        'PrintQueue',
        'Failed to enqueue job: no printer configured',
        {'jobId': payload.jobId},
      );
      notifyListeners();
      return EnqueueJobResult(job: failedNoPrinter, isDuplicate: false);
    }

    final job = PrintJobModel(
      id: payload.jobId,
      billId: payload.billId,
      billNumber: payload.billNumber,
      printerId: resolvedPrinter.id,
      status: PrintJobStatus.queued,
      copyType: payload.copyType,
      retryCount: 0,
      receiptSnapshot: payload.toRawJson(),
      createdAt: now,
      updatedAt: now,
    );

    repository.insert(job);
    logger.info('PrintQueue', 'Enqueued print job', {
      'jobId': job.id,
      'billNumber': job.billNumber,
      'printerId': job.printerId,
    });
    notifyListeners();

    _schedulePrinterWorker(resolvedPrinter.id);
    return EnqueueJobResult(job: job, isDuplicate: false);
  }

  /// Safely retries a `failed` or `cancelled` job using its existing `jobId`.
  /// Rejects retry if the job is already `submitted`, `queued`, `rendering`, or `printing`.
  PrintJobModel retryJob(String jobId, {String? overridePrinterId}) {
    final existing = repository.findById(jobId);
    if (existing == null) {
      throw StateError('ไม่พบงานพิมพ์รหัส $jobId');
    }
    if (!existing.status.canRetry) {
      throw StateError(
        'ไม่สามารถสั่งลองใหม่ได้เนื่องจากสถานะปัจจุบันคือ "${existing.status.thaiLabel}" (${existing.status.value})',
      );
    }

    var targetPrinterId = overridePrinterId ?? existing.printerId;
    if (targetPrinterId == 'unassigned' ||
        printerManager.getPrinterById(targetPrinterId) == null) {
      final parsed = existing.parsedReceipt;
      if (parsed != null) {
        final resolved = routingEngine.resolvePrinterForReceipt(parsed);
        if (resolved != null) {
          targetPrinterId = resolved.id;
        }
      }
    }

    repository.updateStatus(
      jobId,
      status: PrintJobStatus.queued,
      retryCount: existing.retryCount + 1,
      printerId: targetPrinterId,
      clearError: true,
    );

    logger.info('PrintQueue', 'Manual retry scheduled for job', {
      'jobId': jobId,
      'retryCount': existing.retryCount + 1,
      'printerId': targetPrinterId,
    });
    notifyListeners();

    _schedulePrinterWorker(targetPrinterId);
    return repository.findById(jobId)!;
  }

  /// Cancels a `queued` or `failed` job.
  PrintJobModel cancelJob(String jobId) {
    final existing = repository.findById(jobId);
    if (existing == null) {
      throw StateError('ไม่พบงานพิมพ์รหัส $jobId');
    }
    if (!existing.status.canCancel) {
      throw StateError(
        'ไม่สามารถยกเลิกงานพิมพ์ที่มีสถานะ "${existing.status.thaiLabel}" (${existing.status.value}) ได้',
      );
    }

    repository.updateStatus(
      jobId,
      status: PrintJobStatus.cancelled,
      errorMessage: 'ยกเลิกคำสั่งพิมพ์โดยผู้ใช้',
    );
    logger.info('PrintQueue', 'Cancelled print job', {'jobId': jobId});
    notifyListeners();
    return repository.findById(jobId)!;
  }

  /// Creates an explicit manual reprint from an existing job snapshot.
  /// Always generates a NEW unique `jobId` with `copyType = 'reprint'` and
  /// preserves the original `billId` and `billNumber` (never creates a new bill).
  PrintJobModel reprintJob(String sourceJobId, {String? overridePrinterId}) {
    final sourceJob = repository.findById(sourceJobId);
    if (sourceJob == null) {
      throw StateError('ไม่พบงานพิมพ์ต้นฉบับรหัส $sourceJobId');
    }
    if (!sourceJob.status.canReprint) {
      throw StateError(
        'ไม่สามารถสั่งพิมพ์ซ้ำได้ในขณะที่งานต้นฉบับอยู่ในสถานะ "${sourceJob.status.thaiLabel}"',
      );
    }

    final originalPayload = sourceJob.parsedReceipt;
    if (originalPayload == null) {
      throw StateError('ข้อมูลใบเสร็จต้นฉบับเสียหาย ไม่สามารถพิมพ์ซ้ำได้');
    }

    final newJobId =
        'REPRINT-${DateTime.now().millisecondsSinceEpoch}-${_uuid.v4().substring(0, 6).toUpperCase()}';
    final reprintPayload = originalPayload.copyWith(
      jobId: newJobId,
      copyType: 'reprint',
      targetPrinterId: overridePrinterId ?? sourceJob.printerId,
    );

    final result = enqueueReceipt(
      reprintPayload,
      overridePrinterId: overridePrinterId ?? sourceJob.printerId,
    );
    logger.info('PrintQueue', 'Created manual reprint job', {
      'sourceJobId': sourceJobId,
      'newJobId': newJobId,
      'billId': sourceJob.billId,
    });
    return result.job;
  }

  PrintJobModel? getJob(String jobId) => repository.findById(jobId);

  List<PrintJobModel> listJobs({
    List<PrintJobStatus>? statuses,
    String? printerId,
    String? searchBillNumber,
    String? copyType,
    int limit = 200,
  }) {
    return repository.listJobs(
      statuses: statuses,
      printerId: printerId,
      searchBillNumber: searchBillNumber,
      copyType: copyType,
      limit: limit,
    );
  }

  Map<String, int> getQueueStatistics() => repository.getQueueCounts();

  bool get hasActivePrintingJobs => _activePrinterWorkers.isNotEmpty;

  /// Waits until all currently active per-printer queue workers finish.
  Future<void> waitForIdle({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (_activePrinterWorkers.isNotEmpty &&
        DateTime.now().isBefore(deadline)) {
      final currentFutures = _activePrinterWorkers.values.toList();
      if (currentFutures.isEmpty) break;
      await Future.wait(currentFutures);
    }
  }

  /// Prepares the queue for graceful application shutdown without killing
  /// an active job mid-transmission.
  Future<void> shutdownGracefully() async {
    _isShuttingDown = true;
    await waitForIdle(timeout: const Duration(seconds: 10));
  }

  void _schedulePrinterWorker(String printerId) {
    if (_isShuttingDown) return;
    if (_activePrinterWorkers.containsKey(printerId)) {
      // Worker for this printer is already active and will drain newly queued items
      return;
    }

    final future = _runPrinterWorkerLoop(printerId);
    _activePrinterWorkers[printerId] = future;
    future.whenComplete(() {
      _activePrinterWorkers.remove(printerId);
      notifyListeners();
    });
  }

  Future<void> _runPrinterWorkerLoop(String printerId) async {
    while (!_isShuttingDown) {
      final queued = repository.listQueuedForPrinter(printerId);
      if (queued.isEmpty) {
        break;
      }

      final job = queued.first;
      await _executeSingleJob(job);
    }
  }

  Future<void> _executeSingleJob(PrintJobModel job) async {
    // Verify job is still queued (not cancelled while waiting)
    final fresh = repository.findById(job.id);
    if (fresh == null || fresh.status != PrintJobStatus.queued) {
      return;
    }

    final printer = printerManager.getPrinterById(fresh.printerId);
    if (printer == null || !printer.enabled) {
      repository.updateStatus(
        fresh.id,
        status: PrintJobStatus.failed,
        errorMessage:
            'ไม่พบเครื่องพิมพ์ "${fresh.printerId}" หรือเครื่องพิมพ์ถูกปิดใช้งาน',
      );
      notifyListeners();
      return;
    }

    // Step 1: Transition to `rendering`
    repository.updateStatus(fresh.id, status: PrintJobStatus.rendering);
    notifyListeners();

    final payload = fresh.parsedReceipt;
    if (payload == null) {
      repository.updateStatus(
        fresh.id,
        status: PrintJobStatus.failed,
        errorMessage: 'ไม่สามารถอ่านข้อมูล JSON ของใบเสร็จได้',
      );
      notifyListeners();
      return;
    }

    final settings = configService.settings;
    late final RenderedReceiptDocument renderedDoc;
    try {
      final effectivePaperWidth =
          payload.paperWidth == 210 ? 210 : printer.paperWidth;
      renderedDoc = receiptRenderer.render(
        payload,
        overridePaperWidthMm: effectivePaperWidth,
        fontSize: settings.receiptFontSize * printer.configuration.fontScale,
        lineSpacing: printer.configuration.lineSpacing,
        marginMm: printer.configuration.marginMm,
        customHeaderNote: settings.customHeaderNote,
        customFooterNote: settings.customFooterNote,
      );
    } catch (e) {
      repository.updateStatus(
        fresh.id,
        status: PrintJobStatus.failed,
        errorMessage: 'เกิดข้อผิดพลาดขณะสร้างหน้าใบเสร็จ: $e',
      );
      notifyListeners();
      return;
    }

    // Step 2: Transition to `printing`
    repository.updateStatus(fresh.id, status: PrintJobStatus.printing);
    notifyListeners();

    final forwardToCoordinator =
        settings.lanOperatingMode == LanOperatingMode.coordinatorClient;
    final backend = printerManager.backendForPrinter(
      printer,
      forwardLanToCoordinator: forwardToCoordinator,
    );

    final result = await backend.submitReceipt(printer, renderedDoc);
    if (result.submitted) {
      repository.updateStatus(
        fresh.id,
        status: PrintJobStatus.submitted,
        clearError: true,
        submittedAt: DateTime.now(),
      );
      logger.info(
        'PrintQueue',
        'Print job accepted by print subsystem (submitted)',
        {
          'jobId': fresh.id,
          'billNumber': fresh.billNumber,
          'printerId': printer.id,
          'backend': result.backendName,
          'bytesSent': result.bytesSent,
        },
      );
    } else {
      repository.updateStatus(
        fresh.id,
        status: PrintJobStatus.failed,
        errorMessage: result.errorMessage ?? 'ส่งพิมพ์ไม่สำเร็จ',
      );
      logger.error('PrintQueue', 'Print job failed', {
        'jobId': fresh.id,
        'printerId': printer.id,
        'errorCode': result.errorCode,
        'errorMessage': result.errorMessage,
      });
    }
    notifyListeners();
  }
}
