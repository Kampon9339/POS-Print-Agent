import '../../core/database/app_database.dart';
import '../../shared/models/printer_model.dart';

/// SQLite repository for `printers` table.
class PrinterRepository {
  final AppDatabase db;

  const PrinterRepository(this.db);

  List<PrinterModel> listAll({Map<String, bool>? onlineStatuses}) {
    final rows = db.query(
      'SELECT * FROM printers ORDER BY is_default DESC, created_at ASC;',
    );
    return rows.map((row) {
      final id = row['id'] as String;
      final online =
          onlineStatuses?[id] ?? (((row['enabled'] as int?) ?? 1) == 1);
      return PrinterModel.fromDbRow(row, isOnline: online);
    }).toList();
  }

  PrinterModel? findById(String id, {bool? isOnline}) {
    final rows = db.query('SELECT * FROM printers WHERE id = ? LIMIT 1;', [id]);
    if (rows.isEmpty) return null;
    final row = rows.first;
    return PrinterModel.fromDbRow(
      row,
      isOnline: isOnline ?? (((row['enabled'] as int?) ?? 1) == 1),
    );
  }

  PrinterModel? findDefaultPrinter() {
    final defaultRows = db.query(
      'SELECT * FROM printers WHERE is_default = 1 AND enabled = 1 LIMIT 1;',
    );
    if (defaultRows.isNotEmpty) {
      return PrinterModel.fromDbRow(defaultRows.first);
    }
    final fallbackRows = db.query(
      'SELECT * FROM printers WHERE enabled = 1 ORDER BY created_at ASC LIMIT 1;',
    );
    if (fallbackRows.isNotEmpty) {
      return PrinterModel.fromDbRow(fallbackRows.first);
    }
    return null;
  }

  void insert(PrinterModel printer) {
    db.transaction(() {
      if (printer.isDefault) {
        db.execute('UPDATE printers SET is_default = 0;');
      }
      db.execute(
        '''
        INSERT INTO printers (
          id, name, connection_type, protocol, host, port,
          paper_width, is_default, enabled, configuration_json,
          created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?);
        ''',
        [
          printer.id,
          printer.name,
          printer.connectionType.value,
          printer.protocol.value,
          printer.host,
          printer.port,
          printer.paperWidth,
          printer.isDefault ? 1 : 0,
          printer.enabled ? 1 : 0,
          printer.configuration.toRawJson(),
          printer.createdAt.toIso8601String(),
          printer.updatedAt.toIso8601String(),
        ],
      );
    });
  }

  bool update(PrinterModel printer) {
    return db.transaction(() {
      final existing = findById(printer.id);
      if (existing == null) return false;

      if (printer.isDefault) {
        db.execute('UPDATE printers SET is_default = 0 WHERE id != ?;', [
          printer.id,
        ]);
      }

      db.execute(
        '''
        UPDATE printers SET
          name = ?,
          connection_type = ?,
          protocol = ?,
          host = ?,
          port = ?,
          paper_width = ?,
          is_default = ?,
          enabled = ?,
          configuration_json = ?,
          updated_at = ?
        WHERE id = ?;
        ''',
        [
          printer.name,
          printer.connectionType.value,
          printer.protocol.value,
          printer.host,
          printer.port,
          printer.paperWidth,
          printer.isDefault ? 1 : 0,
          printer.enabled ? 1 : 0,
          printer.configuration.toRawJson(),
          DateTime.now().toIso8601String(),
          printer.id,
        ],
      );
      return true;
    });
  }

  bool setDefault(String printerId) {
    return db.transaction(() {
      final existing = findById(printerId);
      if (existing == null) return false;
      final now = DateTime.now().toIso8601String();
      db.execute('UPDATE printers SET is_default = 0, updated_at = ?;', [now]);
      db.execute(
        'UPDATE printers SET is_default = 1, enabled = 1, updated_at = ? WHERE id = ?;',
        [now, printerId],
      );
      return true;
    });
  }

  bool delete(String printerId) {
    return db.transaction(() {
      final existing = findById(printerId);
      if (existing == null) return false;
      db.execute('DELETE FROM routing_rules WHERE printer_id = ?;', [
        printerId,
      ]);
      db.execute('DELETE FROM printers WHERE id = ?;', [printerId]);

      if (existing.isDefault) {
        final remaining = db.query(
          'SELECT id FROM printers WHERE enabled = 1 ORDER BY created_at ASC LIMIT 1;',
        );
        if (remaining.isNotEmpty) {
          final nextId = remaining.first['id'] as String;
          db.execute('UPDATE printers SET is_default = 1 WHERE id = ?;', [
            nextId,
          ]);
        }
      }
      return true;
    });
  }
}
