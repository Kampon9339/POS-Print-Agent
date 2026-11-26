import '../../core/database/app_database.dart';
import '../../shared/models/print_job_model.dart';

/// SQLite repository for `print_jobs` table.
class PrintJobRepository {
  final AppDatabase db;

  const PrintJobRepository(this.db);

  PrintJobModel? findById(String id) {
    final rows = db.query('SELECT * FROM print_jobs WHERE id = ? LIMIT 1;', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return PrintJobModel.fromDbRow(rows.first);
  }

  List<PrintJobModel> listJobs({
    List<PrintJobStatus>? statuses,
    String? printerId,
    String? searchBillNumber,
    String? copyType,
    int limit = 200,
  }) {
    final whereClauses = <String>[];
    final params = <Object?>[];

    if (statuses != null && statuses.isNotEmpty) {
      final placeholders = List.filled(statuses.length, '?').join(', ');
      whereClauses.add('status IN ($placeholders)');
      params.addAll(statuses.map((s) => s.value));
    }

    if (printerId != null && printerId.trim().isNotEmpty) {
      whereClauses.add('printer_id = ?');
      params.add(printerId.trim());
    }

    if (searchBillNumber != null && searchBillNumber.trim().isNotEmpty) {
      whereClauses.add('(bill_number LIKE ? OR id LIKE ? OR bill_id LIKE ?)');
      final pattern = '%${searchBillNumber.trim()}%';
      params.addAll([pattern, pattern, pattern]);
    }

    if (copyType != null && copyType.trim().isNotEmpty) {
      whereClauses.add('copy_type = ?');
      params.add(copyType.trim());
    }

    final whereSql =
        whereClauses.isEmpty ? '' : 'WHERE ${whereClauses.join(' AND ')}';
    params.add(limit);

    final rows = db.query(
      'SELECT * FROM print_jobs $whereSql ORDER BY created_at DESC LIMIT ?;',
      params,
    );
    return rows.map(PrintJobModel.fromDbRow).toList();
  }

  List<PrintJobModel> listQueuedForPrinter(String printerId) {
    final rows = db.query(
      '''
      SELECT * FROM print_jobs
      WHERE printer_id = ? AND status = 'queued'
      ORDER BY created_at ASC;
      ''',
      [printerId],
    );
    return rows.map(PrintJobModel.fromDbRow).toList();
  }

  void insert(PrintJobModel job) {
    db.execute(
      '''
      INSERT INTO print_jobs (
        id, bill_id, bill_number, printer_id, status, copy_type,
        retry_count, receipt_snapshot, error_message,
        created_at, updated_at, submitted_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        job.id,
        job.billId,
        job.billNumber,
        job.printerId,
        job.status.value,
        job.copyType,
        job.retryCount,
        job.receiptSnapshot,
        job.errorMessage,
        job.createdAt.toIso8601String(),
        job.updatedAt.toIso8601String(),
        job.submittedAt?.toIso8601String(),
      ],
    );
  }

  void updateStatus(
    String jobId, {
    required PrintJobStatus status,
    String? errorMessage,
    bool clearError = false,
    int? retryCount,
    String? printerId,
    DateTime? submittedAt,
  }) {
    db.transaction(() {
      final existing = findById(jobId);
      if (existing == null) return;

      final now = DateTime.now().toIso8601String();
      final nextError =
          clearError ? null : (errorMessage ?? existing.errorMessage);
      final nextRetry = retryCount ?? existing.retryCount;
      final nextPrinter = printerId ?? existing.printerId;
      final nextSubmitted =
          submittedAt?.toIso8601String() ??
          existing.submittedAt?.toIso8601String();

      db.execute(
        '''
        UPDATE print_jobs SET
          printer_id = ?,
          status = ?,
          retry_count = ?,
          error_message = ?,
          updated_at = ?,
          submitted_at = ?
        WHERE id = ?;
        ''',
        [
          nextPrinter,
          status.value,
          nextRetry,
          nextError,
          now,
          nextSubmitted,
          jobId,
        ],
      );
    });
  }

  /// Marks any in-flight jobs (`rendering`, `printing`) left from a previous
  /// abnormal termination as `failed` so they are never blindly resubmitted.
  int markInterruptedJobsFailedOnStartup() {
    return db.transaction(() {
      final rows = db.query(
        "SELECT id FROM print_jobs WHERE status IN ('rendering', 'printing');",
      );
      if (rows.isEmpty) return 0;

      final now = DateTime.now().toIso8601String();
      db.execute(
        '''
        UPDATE print_jobs
        SET status = 'failed',
            error_message = 'แอปพลิเคชันถูกปิดหรือเริ่มใหม่ขณะกำลังส่งพิมพ์ โปรดตรวจสอบเครื่องพิมพ์ก่อนสั่งพิมพ์ซ้ำ (Uncertain submission state)',
            updated_at = ?
        WHERE status IN ('rendering', 'printing');
        ''',
        [now],
      );
      return rows.length;
    });
  }

  Map<String, int> getQueueCounts() {
    final rows = db.query(
      'SELECT status, COUNT(*) AS cnt FROM print_jobs GROUP BY status;',
    );
    final counts = <String, int>{
      for (final s in PrintJobStatus.values) s.value: 0,
    };
    var total = 0;
    for (final row in rows) {
      final st = row['status'] as String?;
      final cnt = (row['cnt'] as int?) ?? 0;
      if (st != null) {
        counts[st] = cnt;
        total += cnt;
      }
    }
    counts['total'] = total;
    return counts;
  }
}
