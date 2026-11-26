import 'dart:convert';
import 'dart:io';

/// Log severity levels.
enum LogLevel {
  info('INFO'),
  warn('WARN'),
  error('ERROR'),
  security('SECURITY');

  final String label;
  const LogLevel(this.label);
}

/// Structured log entry with automatic sensitive-field redaction.
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String module;
  final String message;
  final Map<String, Object?> context;

  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.module,
    required this.message,
    this.context = const {},
  });

  Map<String, Object?> toJson() => {
    'timestamp': timestamp.toIso8601String(),
    'level': level.label,
    'module': module,
    'message': message,
    if (context.isNotEmpty) 'context': context,
  };
}

/// Application structured logger that redacts authentication tokens and
/// sensitive customer data.
class AppLogger {
  final List<LogEntry> _entries = [];
  final int maxEntries;
  final bool printToStdout;

  static const Set<String> _redactedKeys = {
    'token',
    'authorization',
    'credential',
    'credential_hash',
    'secret',
    'password',
    'pairingCode',
    'phone',
    'taxId',
    'address',
  };

  AppLogger({this.maxEntries = 500, this.printToStdout = false});

  List<LogEntry> get recentEntries => List.unmodifiable(_entries.reversed);

  void info(String module, String message, [Map<String, Object?>? context]) {
    _log(LogLevel.info, module, message, context);
  }

  void warn(String module, String message, [Map<String, Object?>? context]) {
    _log(LogLevel.warn, module, message, context);
  }

  void error(String module, String message, [Map<String, Object?>? context]) {
    _log(LogLevel.error, module, message, context);
  }

  void security(
    String module,
    String message, [
    Map<String, Object?>? context,
  ]) {
    _log(LogLevel.security, module, message, context);
  }

  void _log(
    LogLevel level,
    String module,
    String message,
    Map<String, Object?>? rawContext,
  ) {
    final sanitized = _sanitizeMap(rawContext ?? const {});
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      module: module,
      message: _sanitizeMessage(message),
      context: sanitized,
    );

    _entries.add(entry);
    if (_entries.length > maxEntries) {
      _entries.removeAt(0);
    }

    if (printToStdout) {
      stdout.writeln(jsonEncode(entry.toJson()));
    }
  }

  Map<String, Object?> _sanitizeMap(Map<String, Object?> input) {
    final output = <String, Object?>{};
    for (final entry in input.entries) {
      final lowerKey = entry.key.toLowerCase();
      final shouldRedact = _redactedKeys.any(
        (rk) => lowerKey.contains(rk.toLowerCase()),
      );
      if (shouldRedact) {
        output[entry.key] = '[REDACTED]';
      } else {
        output[entry.key] = entry.value;
      }
    }
    return output;
  }

  String _sanitizeMessage(String message) {
    return message.replaceAll(
      RegExp(r'Bearer\s+[A-Za-z0-9\-_\.]+', caseSensitive: false),
      'Bearer [REDACTED]',
    );
  }
}
