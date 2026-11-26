import 'package:flutter/foundation.dart';
import '../../shared/models/app_settings_model.dart';
import '../database/app_database.dart';

/// Manages application settings persisted in SQLite `print_settings`.
class AppConfigService extends ChangeNotifier {
  final AppDatabase db;
  late AppSettingsModel _settings;

  AppConfigService(this.db) {
    _settings = _loadFromDb();
  }

  AppSettingsModel get settings => _settings;

  AppSettingsModel _loadFromDb() {
    final rows = db.query(
      'SELECT setting_key, setting_value FROM print_settings;',
    );
    final map = <String, String>{};
    for (final row in rows) {
      final k = row['setting_key'] as String?;
      final v = row['setting_value'] as String?;
      if (k != null && v != null) {
        map[k] = v;
      }
    }
    return AppSettingsModel.fromKeyValueMap(map);
  }

  /// Updates and persists all settings inside a transaction.
  void updateSettings(AppSettingsModel newSettings) {
    final map = newSettings.toKeyValueMap();
    db.transaction(() {
      for (final entry in map.entries) {
        db.execute(
          '''
          INSERT INTO print_settings (setting_key, setting_value)
          VALUES (?, ?)
          ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value;
          ''',
          [entry.key, entry.value],
        );
      }
    });
    _settings = newSettings;
    db.logger.info('Config', 'Updated application settings');
    notifyListeners();
  }

  /// Sets an individual setting key/value pair.
  void setKey(String key, String value) {
    db.execute(
      '''
      INSERT INTO print_settings (setting_key, setting_value)
      VALUES (?, ?)
      ON CONFLICT(setting_key) DO UPDATE SET setting_value = excluded.setting_value;
      ''',
      [key, value],
    );
    _settings = _loadFromDb();
    notifyListeners();
  }
}
