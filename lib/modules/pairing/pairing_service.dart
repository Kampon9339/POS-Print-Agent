import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/paired_device_model.dart';
import 'paired_device_repository.dart';

/// Result returned when a pairing session is confirmed.
class PairingConfirmationResult {
  final PairedDeviceModel device;
  final String plainTextToken;

  const PairingConfirmationResult({
    required this.device,
    required this.plainTextToken,
  });
}

/// Manages device pairing, temporary confirmation codes, credential hashing,
/// and revocation.
class PairingService extends ChangeNotifier {
  final PairedDeviceRepository repository;
  final AppLogger logger;
  final Uuid _uuid = const Uuid();
  final Random _secureRandom = Random.secure();

  final Map<String, PendingPairingSession> _pendingSessions = {};

  PairingService({required this.repository, required this.logger});

  List<PendingPairingSession> get pendingSessions {
    _cleanupExpiredSessions();
    return _pendingSessions.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  List<PairedDeviceModel> listDevices({bool includeRevoked = true}) {
    return repository.listAll(includeRevoked: includeRevoked);
  }

  /// Computes the SHA-256 hex digest of a raw credential token.
  static String hashToken(String rawToken) {
    final bytes = utf8.encode(rawToken.trim());
    return sha256.convert(bytes).toString();
  }

  /// Starts a temporary pairing session (`POST /api/pairing/start`).
  PendingPairingSession startPairing({
    required String deviceName,
    List<String>? permissions,
    String? origin,
  }) {
    _cleanupExpiredSessions();
    final trimmedName = deviceName.trim();
    if (trimmedName.isEmpty) {
      throw ArgumentError('deviceName is required');
    }

    final sessionId = _uuid.v4();
    final codeInt = 100000 + _secureRandom.nextInt(900000);
    final pairingCode = codeInt.toString();
    final now = DateTime.now();

    final allowedScopes = _sanitizePermissions(
      permissions ?? const ['status', 'print', 'printers', 'jobs'],
    );

    final session = PendingPairingSession(
      sessionId: sessionId,
      deviceName: trimmedName,
      pairingCode: pairingCode,
      requestedPermissions: allowedScopes,
      origin: origin,
      createdAt: now,
      expiresAt: now.add(AppConstants.pairingCodeTtl),
    );

    _pendingSessions[sessionId] = session;
    logger.security('Pairing', 'Started temporary pairing session', {
      'sessionId': sessionId,
      'deviceName': trimmedName,
    });
    notifyListeners();
    return session;
  }

  /// Allows a store operator in the Desktop UI to approve a pending session.
  bool approveSessionInUi(String sessionId) {
    _cleanupExpiredSessions();
    final session = _pendingSessions[sessionId];
    if (session == null || session.isExpired) {
      return false;
    }
    session.approvedByUser = true;
    logger.security('Pairing', 'Pairing session approved in desktop UI', {
      'sessionId': sessionId,
      'deviceName': session.deviceName,
    });
    notifyListeners();
    return true;
  }

  /// Rejects/cancels a pending session from the Desktop UI.
  bool rejectSessionInUi(String sessionId) {
    final removed = _pendingSessions.remove(sessionId);
    if (removed != null) {
      logger.security('Pairing', 'Pairing session rejected in desktop UI', {
        'sessionId': sessionId,
      });
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Confirms a pairing session using [sessionId] and [pairingCode].
  /// Returns the newly issued scoped token (only shown once).
  PairingConfirmationResult confirmPairing({
    required String sessionId,
    required String pairingCode,
    bool requireUiApproval = false,
  }) {
    _cleanupExpiredSessions();
    final session = _pendingSessions[sessionId];
    if (session == null || session.isExpired) {
      logger.security(
        'Pairing',
        'Pairing confirmation failed: invalid/expired',
        {'sessionId': sessionId},
      );
      throw StateError('Pairing session not found or has expired.');
    }

    if (requireUiApproval && !session.approvedByUser) {
      throw StateError(
        'Pairing session awaits operator approval in POS Print Agent desktop app.',
      );
    }

    if (!_constantTimeEquals(session.pairingCode, pairingCode.trim())) {
      logger.security('Pairing', 'Pairing confirmation failed: wrong code', {
        'sessionId': sessionId,
      });
      throw ArgumentError('Invalid pairing confirmation code.');
    }

    _pendingSessions.remove(sessionId);

    final rawToken = _generateRandomToken();
    final tokenHash = hashToken(rawToken);
    final now = DateTime.now();

    final device = PairedDeviceModel(
      id: _uuid.v4(),
      deviceName: session.deviceName,
      credentialHash: tokenHash,
      permissions: session.requestedPermissions,
      createdAt: now,
      lastSeenAt: now,
    );

    repository.insert(device);
    logger.security('Pairing', 'Device paired successfully', {
      'deviceId': device.id,
      'deviceName': device.deviceName,
    });
    notifyListeners();

    return PairingConfirmationResult(device: device, plainTextToken: rawToken);
  }

  /// Creates a paired device directly from the Desktop UI (e.g., for a remote
  /// Agent connecting to the Central Coordinator or manual POS token issuance).
  PairingConfirmationResult createDeviceDirectlyFromUi({
    required String deviceName,
    List<String> permissions = const [
      'status',
      'print',
      'printers',
      'jobs',
      'coordinator',
    ],
  }) {
    final rawToken = _generateRandomToken();
    final tokenHash = hashToken(rawToken);
    final now = DateTime.now();

    final device = PairedDeviceModel(
      id: _uuid.v4(),
      deviceName: deviceName.trim(),
      credentialHash: tokenHash,
      permissions: _sanitizePermissions(permissions),
      createdAt: now,
      lastSeenAt: now,
    );

    repository.insert(device);
    logger.security('Pairing', 'Created paired device credential from UI', {
      'deviceId': device.id,
      'deviceName': device.deviceName,
    });
    notifyListeners();
    return PairingConfirmationResult(device: device, plainTextToken: rawToken);
  }

  /// Revokes a paired device by [deviceId] or [rawToken].
  bool revoke({String? deviceId, String? rawToken}) {
    bool revoked = false;
    if (deviceId != null && deviceId.trim().isNotEmpty) {
      revoked = repository.revokeDevice(deviceId.trim());
    } else if (rawToken != null && rawToken.trim().isNotEmpty) {
      revoked = repository.revokeByCredentialHash(hashToken(rawToken.trim()));
    }

    if (revoked) {
      logger.security('Pairing', 'Revoked paired device credential', {
        if (deviceId != null) 'deviceId': deviceId,
      });
      notifyListeners();
    }
    return revoked;
  }

  /// Verifies a bearer token and checks whether it has [requiredPermission].
  PairedDeviceModel? verifyToken(
    String? rawToken, {
    String? requiredPermission,
  }) {
    if (rawToken == null || rawToken.trim().isEmpty) {
      return null;
    }
    final hash = hashToken(rawToken.trim());
    final device = repository.findByCredentialHash(hash);
    if (device == null || device.isRevoked) {
      return null;
    }
    if (requiredPermission != null &&
        !device.hasPermission(requiredPermission)) {
      return null;
    }
    repository.updateLastSeen(device.id);
    return device;
  }

  void _cleanupExpiredSessions() {
    _pendingSessions.removeWhere((_, session) => session.isExpired);
  }

  List<String> _sanitizePermissions(List<String> input) {
    const validScopes = {
      'status',
      'print',
      'printers',
      'jobs',
      'coordinator',
      '*',
    };
    final filtered =
        input
            .map((e) => e.trim().toLowerCase())
            .where((e) => validScopes.contains(e))
            .toSet()
            .toList();
    return filtered.isEmpty
        ? const ['status', 'print', 'printers', 'jobs']
        : filtered;
  }

  String _generateRandomToken() {
    final randomBytes = List<int>.generate(
      32,
      (_) => _secureRandom.nextInt(256),
    );
    final hex =
        randomBytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return 'ppa_${_uuid.v4().replaceAll('-', '')}_$hex';
  }

  bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return diff == 0;
  }
}
