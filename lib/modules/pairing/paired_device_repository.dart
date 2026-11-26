import 'dart:convert';
import '../../core/database/app_database.dart';
import '../../shared/models/paired_device_model.dart';

/// Repository for managing `paired_devices` in SQLite.
class PairedDeviceRepository {
  final AppDatabase db;

  const PairedDeviceRepository(this.db);

  List<PairedDeviceModel> listAll({bool includeRevoked = true}) {
    final sql =
        includeRevoked
            ? 'SELECT * FROM paired_devices ORDER BY created_at DESC;'
            : 'SELECT * FROM paired_devices WHERE revoked_at IS NULL ORDER BY created_at DESC;';
    final rows = db.query(sql);
    return rows.map(PairedDeviceModel.fromDbRow).toList();
  }

  PairedDeviceModel? findById(String id) {
    final rows = db.query(
      'SELECT * FROM paired_devices WHERE id = ? LIMIT 1;',
      [id],
    );
    if (rows.isEmpty) return null;
    return PairedDeviceModel.fromDbRow(rows.first);
  }

  PairedDeviceModel? findByCredentialHash(String credentialHash) {
    final rows = db.query(
      '''
      SELECT * FROM paired_devices
      WHERE credential_hash = ? AND revoked_at IS NULL
      LIMIT 1;
      ''',
      [credentialHash],
    );
    if (rows.isEmpty) return null;
    return PairedDeviceModel.fromDbRow(rows.first);
  }

  void insert(PairedDeviceModel device) {
    db.execute(
      '''
      INSERT INTO paired_devices (
        id, device_name, credential_hash, permissions, created_at, last_seen_at, revoked_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?);
      ''',
      [
        device.id,
        device.deviceName,
        device.credentialHash,
        jsonEncode(device.permissions),
        device.createdAt.toIso8601String(),
        device.lastSeenAt.toIso8601String(),
        device.revokedAt?.toIso8601String(),
      ],
    );
  }

  void updateLastSeen(String id) {
    db.execute('UPDATE paired_devices SET last_seen_at = ? WHERE id = ?;', [
      DateTime.now().toIso8601String(),
      id,
    ]);
  }

  bool revokeDevice(String id) {
    final existing = findById(id);
    if (existing == null) return false;
    db.execute('UPDATE paired_devices SET revoked_at = ? WHERE id = ?;', [
      DateTime.now().toIso8601String(),
      id,
    ]);
    return true;
  }

  bool revokeByCredentialHash(String credentialHash) {
    final existing = findByCredentialHash(credentialHash);
    if (existing == null) return false;
    db.execute('UPDATE paired_devices SET revoked_at = ? WHERE id = ?;', [
      DateTime.now().toIso8601String(),
      existing.id,
    ]);
    return true;
  }
}
