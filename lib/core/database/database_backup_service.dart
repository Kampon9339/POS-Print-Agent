import 'dart:io';
import 'package:path/path.dart' as p;
import 'app_database.dart';

/// Handles SQLite database backups and safe retention-policy cleanup.
class DatabaseBackupService {
  final AppDatabase db;

  const DatabaseBackupService(this.db);

  /// Creates a consistent SQLite backup snapshot at [destinationFilePath].
  Future<String> createBackup(String destinationDirectory) async {
    final dir = Directory(destinationDirectory);
    if (!dir.existsSync()) {
      dir.createSync(recursive: true);
    }

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .replaceAll('.', '-');
    final targetPath = p.join(
      destinationDirectory,
      'pos_print_agent_backup_$timestamp.sqlite',
    );

    final escapedPath = targetPath.replaceAll("'", "''");
    db.rawDb.execute("VACUUM INTO '$escapedPath';");

    db.logger.info('DatabaseBackup', 'Created database backup', {
      'backupPath': targetPath,
    });
    return targetPath;
  }

  /// Applies the retention policy for resolved historical print jobs.
  /// Never deletes pending (`queued`, `rendering`, `printing`) or unresolved
  /// (`failed`) jobs automatically.
  int applyRetentionPolicy({required int retentionDays}) {
    if (retentionDays <= 0) return 0;

    final cutoff =
        DateTime.now()
            .subtract(Duration(days: retentionDays))
            .toIso8601String();

    return db.transaction(() {
      final countRows = db.query(
        '''
        SELECT COUNT(*) AS cnt FROM print_jobs
        WHERE status IN ('submitted', 'cancelled')
          AND created_at < ?;
        ''',
        [cutoff],
      );
      final count = (countRows.first['cnt'] as int?) ?? 0;

      if (count > 0) {
        db.execute(
          '''
          DELETE FROM print_jobs
          WHERE status IN ('submitted', 'cancelled')
            AND created_at < ?;
          ''',
          [cutoff],
        );
        db.logger.info(
          'RetentionPolicy',
          'Purged expired resolved print jobs',
          {'purgedCount': count, 'retentionDays': retentionDays},
        );
      }
      return count;
    });
  }
}
