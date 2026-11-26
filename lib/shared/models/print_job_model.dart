import 'dart:convert';
import 'receipt_payload.dart';

/// Statuses of a print job in the persistent SQLite queue.
enum PrintJobStatus {
  queued('queued', 'รอพิมพ์'),
  rendering('rendering', 'กำลังประมวลผลใบเสร็จ'),
  printing('printing', 'กำลังส่งพิมพ์'),
  submitted('submitted', 'ส่งเข้าเครื่องพิมพ์แล้ว'),
  failed('failed', 'พิมพ์ไม่สำเร็จ'),
  cancelled('cancelled', 'ยกเลิกแล้ว');

  final String value;
  final String thaiLabel;
  const PrintJobStatus(this.value, this.thaiLabel);

  static PrintJobStatus fromString(String value) {
    return PrintJobStatus.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => PrintJobStatus.queued,
    );
  }

  /// Whether a manual retry on the same job ID is safe.
  /// Only failed or cancelled jobs may be retried directly.
  bool get canRetry =>
      this == PrintJobStatus.failed || this == PrintJobStatus.cancelled;

  /// Whether the job can be cancelled before submission completes.
  bool get canCancel =>
      this == PrintJobStatus.queued || this == PrintJobStatus.failed;

  /// Whether a manual reprint (with a new Job ID & copyType='reprint') is allowed.
  bool get canReprint =>
      this == PrintJobStatus.submitted ||
      this == PrintJobStatus.failed ||
      this == PrintJobStatus.cancelled;
}

/// Persistent Print Job stored in SQLite `print_jobs` table.
class PrintJobModel {
  final String id;
  final String billId;
  final String billNumber;
  final String printerId;
  final PrintJobStatus status;
  final String copyType;
  final int retryCount;
  final String receiptSnapshot;
  final String? errorMessage;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? submittedAt;

  const PrintJobModel({
    required this.id,
    required this.billId,
    required this.billNumber,
    required this.printerId,
    required this.status,
    required this.copyType,
    required this.retryCount,
    required this.receiptSnapshot,
    this.errorMessage,
    required this.createdAt,
    required this.updatedAt,
    this.submittedAt,
  });

  factory PrintJobModel.fromDbRow(Map<String, Object?> row) {
    final submittedRaw = row['submitted_at'] as String?;
    return PrintJobModel(
      id: row['id'] as String,
      billId: row['bill_id'] as String,
      billNumber: row['bill_number'] as String,
      printerId: row['printer_id'] as String,
      status: PrintJobStatus.fromString((row['status'] as String?) ?? 'queued'),
      copyType: (row['copy_type'] as String?) ?? 'original',
      retryCount: (row['retry_count'] as int?) ?? 0,
      receiptSnapshot: (row['receipt_snapshot'] as String?) ?? '{}',
      errorMessage: row['error_message'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      submittedAt:
          submittedRaw != null && submittedRaw.isNotEmpty
              ? DateTime.parse(submittedRaw)
              : null,
    );
  }

  ReceiptPayload? get parsedReceipt {
    try {
      final decoded = jsonDecode(receiptSnapshot);
      if (decoded is Map<String, dynamic>) {
        return ReceiptPayload.fromJson(decoded);
      }
    } catch (_) {}
    return null;
  }

  Map<String, dynamic> toJson({bool includeSnapshot = false}) => {
    'id': id,
    'jobId': id,
    'billId': billId,
    'billNumber': billNumber,
    'printerId': printerId,
    'status': status.value,
    'statusLabel': status.thaiLabel,
    'statusNote':
        status == PrintJobStatus.submitted
            ? 'ระบบปฏิบัติการหรือเครื่องพิมพ์รับคำสั่งแล้ว (ไม่ได้การันตีว่ากระดาษถูกพิมพ์ออกมาจริง)'
            : null,
    'copyType': copyType,
    'retryCount': retryCount,
    'errorMessage': errorMessage,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'submittedAt': submittedAt?.toIso8601String(),
    if (includeSnapshot) 'receipt': parsedReceipt?.toJson(),
  };

  PrintJobModel copyWith({
    String? printerId,
    PrintJobStatus? status,
    String? copyType,
    int? retryCount,
    String? receiptSnapshot,
    String? errorMessage,
    bool clearError = false,
    DateTime? updatedAt,
    DateTime? submittedAt,
  }) {
    return PrintJobModel(
      id: id,
      billId: billId,
      billNumber: billNumber,
      printerId: printerId ?? this.printerId,
      status: status ?? this.status,
      copyType: copyType ?? this.copyType,
      retryCount: retryCount ?? this.retryCount,
      receiptSnapshot: receiptSnapshot ?? this.receiptSnapshot,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      submittedAt: submittedAt ?? this.submittedAt,
    );
  }
}
