import 'dart:convert';

/// Represents a paired POS client or remote Agent stored in `paired_devices`.
class PairedDeviceModel {
  final String id;
  final String deviceName;
  final String credentialHash;
  final List<String> permissions;
  final DateTime createdAt;
  final DateTime lastSeenAt;
  final DateTime? revokedAt;

  const PairedDeviceModel({
    required this.id,
    required this.deviceName,
    required this.credentialHash,
    required this.permissions,
    required this.createdAt,
    required this.lastSeenAt,
    this.revokedAt,
  });

  bool get isRevoked => revokedAt != null;

  bool hasPermission(String permission) =>
      !isRevoked &&
      (permissions.contains('*') || permissions.contains(permission));

  factory PairedDeviceModel.fromDbRow(Map<String, Object?> row) {
    final permsRaw = (row['permissions'] as String?) ?? '["print","status"]';
    List<String> parsedPerms = const ['print', 'status'];
    try {
      final decoded = jsonDecode(permsRaw);
      if (decoded is List) {
        parsedPerms = decoded.map((e) => e.toString()).toList();
      }
    } catch (_) {
      parsedPerms = permsRaw.split(',').map((e) => e.trim()).toList();
    }

    final revokedRaw = row['revoked_at'] as String?;

    return PairedDeviceModel(
      id: row['id'] as String,
      deviceName: row['device_name'] as String,
      credentialHash: row['credential_hash'] as String,
      permissions: parsedPerms,
      createdAt: DateTime.parse(row['created_at'] as String),
      lastSeenAt: DateTime.parse(row['last_seen_at'] as String),
      revokedAt:
          revokedRaw != null && revokedRaw.isNotEmpty
              ? DateTime.parse(revokedRaw)
              : null,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'deviceName': deviceName,
    'permissions': permissions,
    'createdAt': createdAt.toIso8601String(),
    'lastSeenAt': lastSeenAt.toIso8601String(),
    'revokedAt': revokedAt?.toIso8601String(),
    'isRevoked': isRevoked,
  };
}

/// Active temporary pairing session awaiting confirmation in the desktop UI.
class PendingPairingSession {
  final String sessionId;
  final String deviceName;
  final String pairingCode;
  final List<String> requestedPermissions;
  final String? origin;
  final DateTime createdAt;
  final DateTime expiresAt;
  bool approvedByUser;

  PendingPairingSession({
    required this.sessionId,
    required this.deviceName,
    required this.pairingCode,
    required this.requestedPermissions,
    this.origin,
    required this.createdAt,
    required this.expiresAt,
    this.approvedByUser = false,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);

  Map<String, dynamic> toJson() => {
    'sessionId': sessionId,
    'deviceName': deviceName,
    'pairingCode': pairingCode,
    'requestedPermissions': requestedPermissions,
    'origin': origin,
    'createdAt': createdAt.toIso8601String(),
    'expiresAt': expiresAt.toIso8601String(),
    'approvedByUser': approvedByUser,
    'isExpired': isExpired,
  };
}
