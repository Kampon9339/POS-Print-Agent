/// Job types supported by the Print Routing Engine.
enum PrintJobType {
  receipt('receipt', 'ใบเสร็จลูกค้า (Customer Receipt)'),
  kitchen('kitchen', 'ใบสั่งครัว / บาร์น้ำ (Kitchen Order)'),
  report('report', 'รายงานสรุปยอด (Report)'),
  backup('backup', 'ใบเสร็จสำรอง (Backup Receipt)');

  final String value;
  final String thaiLabel;
  const PrintJobType(this.value, this.thaiLabel);

  static PrintJobType fromString(String value) {
    return PrintJobType.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => PrintJobType.receipt,
    );
  }
}

/// Persistent routing rule stored in SQLite `routing_rules` table.
class RoutingRuleModel {
  final String id;
  final String jobType;
  final String printerId;
  final int priority;
  final bool enabled;

  const RoutingRuleModel({
    required this.id,
    required this.jobType,
    required this.printerId,
    required this.priority,
    required this.enabled,
  });

  factory RoutingRuleModel.fromDbRow(Map<String, Object?> row) {
    return RoutingRuleModel(
      id: row['id'] as String,
      jobType: row['job_type'] as String,
      printerId: row['printer_id'] as String,
      priority: (row['priority'] as int?) ?? 1,
      enabled: ((row['enabled'] as int?) ?? 1) == 1,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobType': jobType,
    'jobTypeLabel': PrintJobType.fromString(jobType).thaiLabel,
    'printerId': printerId,
    'priority': priority,
    'enabled': enabled,
  };

  RoutingRuleModel copyWith({
    String? jobType,
    String? printerId,
    int? priority,
    bool? enabled,
  }) {
    return RoutingRuleModel(
      id: id,
      jobType: jobType ?? this.jobType,
      printerId: printerId ?? this.printerId,
      priority: priority ?? this.priority,
      enabled: enabled ?? this.enabled,
    );
  }
}
