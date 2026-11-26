import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart';
import '../logging/app_logger.dart';
import 'migrations.dart';

/// Core SQLite database wrapper supporting transactions, WAL mode,
/// schema migrations, and in-memory mode for automated tests.
class AppDatabase {
  final Database _db;
  final String? dbFilePath;
  final AppLogger logger;
  bool _inTransaction = false;

  AppDatabase._(this._db, this.dbFilePath, this.logger);

  /// Opens a persistent SQLite database at [filePath] and runs migrations.
  factory AppDatabase.openFile(String filePath, {required AppLogger logger}) {
    final parentDir = Directory(p.dirname(filePath));
    if (!parentDir.existsSync()) {
      parentDir.createSync(recursive: true);
    }

    final db = sqlite3.open(filePath);
    db.execute('PRAGMA journal_mode = WAL;');
    db.execute('PRAGMA synchronous = NORMAL;');
    db.execute('PRAGMA foreign_keys = ON;');
    db.execute('PRAGMA busy_timeout = 5000;');

    DatabaseMigrations.runMigrations(db);
    logger.info('Database', 'Opened SQLite database', {'path': filePath});
    return AppDatabase._(db, filePath, logger);
  }

  /// Opens an isolated in-memory SQLite database for automated testing.
  factory AppDatabase.openInMemory({AppLogger? logger}) {
    final log = logger ?? AppLogger();
    final db = sqlite3.openInMemory();
    db.execute('PRAGMA foreign_keys = ON;');
    DatabaseMigrations.runMigrations(db);
    return AppDatabase._(db, null, log);
  }

  Database get rawDb => _db;

  /// Executes [action] inside a SQLite IMMEDIATE transaction.
  /// Supports nested calls safely.
  T transaction<T>(T Function() action) {
    if (_inTransaction) {
      return action();
    }
    _inTransaction = true;
    _db.execute('BEGIN IMMEDIATE TRANSACTION;');
    try {
      final result = action();
      _db.execute('COMMIT;');
      return result;
    } catch (e, st) {
      try {
        _db.execute('ROLLBACK;');
      } catch (_) {}
      logger.error('Database', 'Transaction rolled back: $e', {
        'stack': st.toString(),
      });
      rethrow;
    } finally {
      _inTransaction = false;
    }
  }

  /// Executes a write SQL statement (`INSERT`, `UPDATE`, `DELETE`).
  void execute(String sql, [List<Object?> parameters = const []]) {
    final stmt = _db.prepare(sql);
    try {
      stmt.execute(parameters);
    } finally {
      stmt.dispose();
    }
  }

  /// Executes a `SELECT` query and returns rows as `List<Map<String, Object?>>`.
  List<Map<String, Object?>> query(
    String sql, [
    List<Object?> parameters = const [],
  ]) {
    final stmt = _db.prepare(sql);
    try {
      final resultSet = stmt.select(parameters);
      return resultSet.map((row) {
        final map = <String, Object?>{};
        for (final col in resultSet.columnNames) {
          map[col] = row[col];
        }
        return map;
      }).toList();
    } finally {
      stmt.dispose();
    }
  }

  ///Closes the database connection cleanly.
  void close() {
    _db.dispose();
  }
}
