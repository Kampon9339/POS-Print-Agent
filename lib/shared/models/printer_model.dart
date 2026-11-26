import 'dart:convert';

/// Connection type of a configured printer.
enum PrinterConnectionType {
  os('os', 'ไดรเวอร์ระบบปฏิบัติการ (OS)'),
  usb('usb', 'สาย USB'),
  lan('lan', 'เครือข่ายสายแลน (LAN)'),
  wifi('wifi', 'เครือข่ายไร้สาย (Wi-Fi)');

  final String value;
  final String thaiLabel;
  const PrinterConnectionType(this.value, this.thaiLabel);

  static PrinterConnectionType fromString(String value) {
    return PrinterConnectionType.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => PrinterConnectionType.os,
    );
  }
}

/// Communication protocol used to talk to the printer.
enum PrinterProtocol {
  osDriver('os_driver', 'OS Spooler / CUPS Driver'),
  rawTcp('raw_tcp', 'RAW TCP / ESC-POS (Port 9100)'),
  ipp('ipp', 'IPP (Port 631)'),
  lpr('lpr', 'LPR / LPD (Port 515)'),
  usbRaw('usb_raw', 'USB Print Interface');

  final String value;
  final String label;
  const PrinterProtocol(this.value, this.label);

  static PrinterProtocol fromString(String value) {
    return PrinterProtocol.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => PrinterProtocol.osDriver,
    );
  }
}

/// Extra printer-specific settings stored in `configuration_json`.
class PrinterConfiguration {
  final String? osDriverName;
  final int? usbVendorId;
  final int? usbProductId;
  final double marginMm;
  final double fontScale;
  final double lineSpacing;
  final bool autoCut;
  final bool openCashDrawer;
  final bool useRasterForEscPos;
  final String? backupPrinterId;
  final int timeoutMs;

  const PrinterConfiguration({
    this.osDriverName,
    this.usbVendorId,
    this.usbProductId,
    this.marginMm = 4.0,
    this.fontScale = 1.0,
    this.lineSpacing = 1.25,
    this.autoCut = true,
    this.openCashDrawer = false,
    this.useRasterForEscPos = true,
    this.backupPrinterId,
    this.timeoutMs = 8000,
  });

  factory PrinterConfiguration.fromJson(Map<String, dynamic> json) {
    return PrinterConfiguration(
      osDriverName: json['osDriverName'] as String?,
      usbVendorId: json['usbVendorId'] as int?,
      usbProductId: json['usbProductId'] as int?,
      marginMm: (json['marginMm'] as num?)?.toDouble() ?? 4.0,
      fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
      lineSpacing: (json['lineSpacing'] as num?)?.toDouble() ?? 1.25,
      autoCut: (json['autoCut'] as bool?) ?? true,
      openCashDrawer: (json['openCashDrawer'] as bool?) ?? false,
      useRasterForEscPos: (json['useRasterForEscPos'] as bool?) ?? true,
      backupPrinterId: json['backupPrinterId'] as String?,
      timeoutMs: (json['timeoutMs'] as int?) ?? 8000,
    );
  }

  factory PrinterConfiguration.fromRawJson(String? raw) {
    if (raw == null || raw.trim().isEmpty) {
      return const PrinterConfiguration();
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return PrinterConfiguration.fromJson(decoded);
      }
    } catch (_) {}
    return const PrinterConfiguration();
  }

  Map<String, dynamic> toJson() => {
    if (osDriverName != null) 'osDriverName': osDriverName,
    if (usbVendorId != null) 'usbVendorId': usbVendorId,
    if (usbProductId != null) 'usbProductId': usbProductId,
    'marginMm': marginMm,
    'fontScale': fontScale,
    'lineSpacing': lineSpacing,
    'autoCut': autoCut,
    'openCashDrawer': openCashDrawer,
    'useRasterForEscPos': useRasterForEscPos,
    if (backupPrinterId != null) 'backupPrinterId': backupPrinterId,
    'timeoutMs': timeoutMs,
  };

  String toRawJson() => jsonEncode(toJson());

  PrinterConfiguration copyWith({
    String? osDriverName,
    int? usbVendorId,
    int? usbProductId,
    double? marginMm,
    double? fontScale,
    double? lineSpacing,
    bool? autoCut,
    bool? openCashDrawer,
    bool? useRasterForEscPos,
    String? backupPrinterId,
    int? timeoutMs,
  }) {
    return PrinterConfiguration(
      osDriverName: osDriverName ?? this.osDriverName,
      usbVendorId: usbVendorId ?? this.usbVendorId,
      usbProductId: usbProductId ?? this.usbProductId,
      marginMm: marginMm ?? this.marginMm,
      fontScale: fontScale ?? this.fontScale,
      lineSpacing: lineSpacing ?? this.lineSpacing,
      autoCut: autoCut ?? this.autoCut,
      openCashDrawer: openCashDrawer ?? this.openCashDrawer,
      useRasterForEscPos: useRasterForEscPos ?? this.useRasterForEscPos,
      backupPrinterId: backupPrinterId ?? this.backupPrinterId,
      timeoutMs: timeoutMs ?? this.timeoutMs,
    );
  }
}

/// Represents a configured printer persisted in SQLite `printers` table.
class PrinterModel {
  final String id;
  final String name;
  final PrinterConnectionType connectionType;
  final PrinterProtocol protocol;
  final String? host;
  final int? port;
  final int paperWidth;
  final bool isDefault;
  final bool enabled;
  final PrinterConfiguration configuration;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isOnline;

  const PrinterModel({
    required this.id,
    required this.name,
    required this.connectionType,
    required this.protocol,
    this.host,
    this.port,
    required this.paperWidth,
    required this.isDefault,
    required this.enabled,
    required this.configuration,
    required this.createdAt,
    required this.updatedAt,
    this.isOnline = true,
  });

  factory PrinterModel.fromDbRow(
    Map<String, Object?> row, {
    bool isOnline = true,
  }) {
    return PrinterModel(
      id: row['id'] as String,
      name: row['name'] as String,
      connectionType: PrinterConnectionType.fromString(
        (row['connection_type'] as String?) ?? 'os',
      ),
      protocol: PrinterProtocol.fromString(
        (row['protocol'] as String?) ?? 'os_driver',
      ),
      host: row['host'] as String?,
      port: row['port'] as int?,
      paperWidth: (row['paper_width'] as int?) ?? 80,
      isDefault: ((row['is_default'] as int?) ?? 0) == 1,
      enabled: ((row['enabled'] as int?) ?? 1) == 1,
      configuration: PrinterConfiguration.fromRawJson(
        row['configuration_json'] as String?,
      ),
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
      isOnline: isOnline,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'connectionType': connectionType.value,
    'connectionTypeLabel': connectionType.thaiLabel,
    'protocol': protocol.value,
    'protocolLabel': protocol.label,
    'host': host,
    'port': port,
    'paperWidth': paperWidth,
    'isDefault': isDefault,
    'enabled': enabled,
    'configuration': configuration.toJson(),
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
    'isOnline': isOnline,
  };

  PrinterModel copyWith({
    String? id,
    String? name,
    PrinterConnectionType? connectionType,
    PrinterProtocol? protocol,
    String? host,
    int? port,
    int? paperWidth,
    bool? isDefault,
    bool? enabled,
    PrinterConfiguration? configuration,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isOnline,
  }) {
    return PrinterModel(
      id: id ?? this.id,
      name: name ?? this.name,
      connectionType: connectionType ?? this.connectionType,
      protocol: protocol ?? this.protocol,
      host: host ?? this.host,
      port: port ?? this.port,
      paperWidth: paperWidth ?? this.paperWidth,
      isDefault: isDefault ?? this.isDefault,
      enabled: enabled ?? this.enabled,
      configuration: configuration ?? this.configuration,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isOnline: isOnline ?? this.isOnline,
    );
  }
}
