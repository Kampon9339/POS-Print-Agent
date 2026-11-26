import 'package:sqlite3/sqlite3.dart';

/// Database migration definition.
class DbMigration {
  final int version;
  final String description;
  final List<String> statements;

  const DbMigration({
    required this.version,
    required this.description,
    required this.statements,
  });
}

/// Manages schema migrations for the POS Print Agent SQLite database.
class DatabaseMigrations {
  DatabaseMigrations._();

  static const List<DbMigration> migrations = [
    DbMigration(
      version: 1,
      description:
          'Initial schema: printers, print_jobs, print_settings, paired_devices, routing_rules',
      statements: [
        '''
        CREATE TABLE IF NOT EXISTS printers (
          id TEXT PRIMARY KEY NOT NULL,
          name TEXT NOT NULL,
          connection_type TEXT NOT NULL,
          protocol TEXT NOT NULL,
          host TEXT,
          port INTEGER,
          paper_width INTEGER NOT NULL DEFAULT 80,
          is_default INTEGER NOT NULL DEFAULT 0,
          enabled INTEGER NOT NULL DEFAULT 1,
          configuration_json TEXT NOT NULL DEFAULT '{}',
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        );
        ''',
        '''
        CREATE INDEX IF NOT EXISTS idx_printers_default
          ON printers(is_default, enabled);
        ''',
        '''
        CREATE TABLE IF NOT EXISTS print_jobs (
          id TEXT PRIMARY KEY NOT NULL,
          bill_id TEXT NOT NULL,
          bill_number TEXT NOT NULL,
          printer_id TEXT NOT NULL,
          status TEXT NOT NULL,
          copy_type TEXT NOT NULL DEFAULT 'original',
          retry_count INTEGER NOT NULL DEFAULT 0,
          receipt_snapshot TEXT NOT NULL,
          error_message TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL,
          submitted_at TEXT
        );
        ''',
        '''
        CREATE INDEX IF NOT EXISTS idx_print_jobs_printer_status
          ON print_jobs(printer_id, status, created_at);
        ''',
        '''
        CREATE INDEX IF NOT EXISTS idx_print_jobs_bill_number
          ON print_jobs(bill_number);
        ''',
        '''
        CREATE INDEX IF NOT EXISTS idx_print_jobs_created_at
          ON print_jobs(created_at DESC);
        ''',
        '''
        CREATE TABLE IF NOT EXISTS print_settings (
          setting_key TEXT PRIMARY KEY NOT NULL,
          setting_value TEXT NOT NULL
        );
        ''',
        '''
        CREATE TABLE IF NOT EXISTS paired_devices (
          id TEXT PRIMARY KEY NOT NULL,
          device_name TEXT NOT NULL,
          credential_hash TEXT NOT NULL,
          permissions TEXT NOT NULL,
          created_at TEXT NOT NULL,
          last_seen_at TEXT NOT NULL,
          revoked_at TEXT
        );
        ''',
        '''
        CREATE INDEX IF NOT EXISTS idx_paired_devices_credential
          ON paired_devices(credential_hash);
        ''',
        '''
        CREATE TABLE IF NOT EXISTS routing_rules (
          id TEXT PRIMARY KEY NOT NULL,
          job_type TEXT NOT NULL,
          printer_id TEXT NOT NULL,
          priority INTEGER NOT NULL DEFAULT 1,
          enabled INTEGER NOT NULL DEFAULT 1
        );
        ''',
        '''
        CREATE INDEX IF NOT EXISTS idx_routing_rules_type_priority
          ON routing_rules(job_type, enabled, priority ASC);
        ''',
      ],
    ),
  ];

  /// Applies pending migrations inside a transaction.
  static void runMigrations(Database db) {
    db.execute('''
      CREATE TABLE IF NOT EXISTS schema_migrations (
        version INTEGER PRIMARY KEY NOT NULL,
        description TEXT NOT NULL,
        applied_at TEXT NOT NULL
      );
    ''');

    final appliedRows = db.select('SELECT version FROM schema_migrations;');
    final appliedVersions =
        appliedRows.map((row) => row['version'] as int).toSet();

    for (final migration in migrations) {
      if (appliedVersions.contains(migration.version)) {
        continue;
      }

      db.execute('BEGIN IMMEDIATE TRANSACTION;');
      try {
        for (final sql in migration.statements) {
          db.execute(sql);
        }
        final stmt = db.prepare(
          'INSERT INTO schema_migrations (version, description, applied_at) VALUES (?, ?, ?);',
        );
        try {
          stmt.execute([
            migration.version,
            migration.description,
            DateTime.now().toIso8601String(),
          ]);
        } finally {
          stmt.dispose();
        }
        db.execute('COMMIT;');
      } catch (e) {
        db.execute('ROLLBACK;');
        rethrow;
      }
    }
  }
}
