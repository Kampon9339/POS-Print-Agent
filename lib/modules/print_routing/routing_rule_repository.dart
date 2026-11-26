import '../../core/database/app_database.dart';
import '../../shared/models/routing_rule_model.dart';

/// SQLite repository for `routing_rules` table.
class RoutingRuleRepository {
  final AppDatabase db;

  const RoutingRuleRepository(this.db);

  List<RoutingRuleModel> listAll() {
    final rows = db.query(
      'SELECT * FROM routing_rules ORDER BY job_type ASC, priority ASC;',
    );
    return rows.map(RoutingRuleModel.fromDbRow).toList();
  }

  List<RoutingRuleModel> listForJobType(
    String jobType, {
    bool onlyEnabled = true,
  }) {
    final sql =
        onlyEnabled
            ? 'SELECT * FROM routing_rules WHERE job_type = ? AND enabled = 1 ORDER BY priority ASC;'
            : 'SELECT * FROM routing_rules WHERE job_type = ? ORDER BY priority ASC;';
    final rows = db.query(sql, [jobType.trim().toLowerCase()]);
    return rows.map(RoutingRuleModel.fromDbRow).toList();
  }

  RoutingRuleModel? findById(String id) {
    final rows = db.query('SELECT * FROM routing_rules WHERE id = ? LIMIT 1;', [
      id,
    ]);
    if (rows.isEmpty) return null;
    return RoutingRuleModel.fromDbRow(rows.first);
  }

  void upsert(RoutingRuleModel rule) {
    db.execute(
      '''
      INSERT INTO routing_rules (id, job_type, printer_id, priority, enabled)
      VALUES (?, ?, ?, ?, ?)
      ON CONFLICT(id) DO UPDATE SET
        job_type = excluded.job_type,
        printer_id = excluded.printer_id,
        priority = excluded.priority,
        enabled = excluded.enabled;
      ''',
      [
        rule.id,
        rule.jobType.trim().toLowerCase(),
        rule.printerId,
        rule.priority,
        rule.enabled ? 1 : 0,
      ],
    );
  }

  bool delete(String id) {
    final existing = findById(id);
    if (existing == null) return false;
    db.execute('DELETE FROM routing_rules WHERE id = ?;', [id]);
    return true;
  }
}
