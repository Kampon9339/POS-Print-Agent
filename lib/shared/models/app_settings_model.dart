/// Operating mode for shared LAN printers (Section 6).
enum LanOperatingMode {
  direct(
    'direct',
    'โหมด A: พิมพ์ตรงไปยังเครื่องพิมพ์ LAN (Direct LAN Printing)',
  ),
  coordinatorClient(
    'coordinator_client',
    'โหมด B (ลูกข่าย): ส่งงานผ่านเครื่องแม่ข่าย (Forward to Central Coordinator)',
  ),
  coordinatorHost(
    'coordinator_host',
    'โหมด B (แม่ข่าย): เปิดบริการศูนย์กลางคิวพิมพ์ (Run Central Print Coordinator)',
  );

  final String value;
  final String thaiLabel;
  const LanOperatingMode(this.value, this.thaiLabel);

  static LanOperatingMode fromString(String value) {
    return LanOperatingMode.values.firstWhere(
      (e) => e.value == value.toLowerCase(),
      orElse: () => LanOperatingMode.direct,
    );
  }
}

/// Strongly-typed application settings persisted in SQLite `print_settings`.
class AppSettingsModel {
  final int localApiPort;
  final bool requirePairingAuth;
  final List<String> allowedOrigins;
  final int defaultPaperWidth;
  final double receiptFontSize;
  final double receiptLineSpacing;
  final double receiptMarginMm;
  final bool showStoreLogo;
  final String storeLogoPath;
  final String customHeaderNote;
  final String customFooterNote;
  final bool autoStartOnLogin;
  final bool minimizeToTrayOnClose;
  final int retentionDays;
  final LanOperatingMode lanOperatingMode;
  final String coordinatorBindHost;
  final int coordinatorPort;
  final String remoteCoordinatorUrl;
  final String remoteCoordinatorToken;
  final String discoverySubnetPrefix;

  const AppSettingsModel({
    this.localApiPort = 8765,
    this.requirePairingAuth = false,
    this.allowedOrigins = const [
      'http://localhost:3000',
      'http://localhost:5173',
      'http://localhost:8080',
      'http://127.0.0.1:3000',
      'http://127.0.0.1:5173',
    ],
    this.defaultPaperWidth = 80,
    this.receiptFontSize = 14.0,
    this.receiptLineSpacing = 1.25,
    this.receiptMarginMm = 4.0,
    this.showStoreLogo = false,
    this.storeLogoPath = '',
    this.customHeaderNote = '',
    this.customFooterNote = '',
    this.autoStartOnLogin = false,
    this.minimizeToTrayOnClose = true,
    this.retentionDays = 30,
    this.lanOperatingMode = LanOperatingMode.direct,
    this.coordinatorBindHost = '0.0.0.0',
    this.coordinatorPort = 8766,
    this.remoteCoordinatorUrl = '',
    this.remoteCoordinatorToken = '',
    this.discoverySubnetPrefix = '192.168.1',
  });

  factory AppSettingsModel.fromKeyValueMap(Map<String, String> map) {
    final originsRaw = map['allowed_origins'];
    final origins =
        originsRaw != null && originsRaw.trim().isNotEmpty
            ? originsRaw
                .split(',')
                .map((e) => e.trim())
                .where((e) => e.isNotEmpty)
                .toList()
            : const [
              'http://localhost:3000',
              'http://localhost:5173',
              'http://localhost:8080',
              'http://127.0.0.1:3000',
              'http://127.0.0.1:5173',
            ];

    return AppSettingsModel(
      localApiPort: int.tryParse(map['local_api_port'] ?? '') ?? 8765,
      requirePairingAuth: (map['require_pairing_auth'] ?? 'false') == 'true',
      allowedOrigins: origins,
      defaultPaperWidth: int.tryParse(map['default_paper_width'] ?? '') ?? 80,
      receiptFontSize: double.tryParse(map['receipt_font_size'] ?? '') ?? 14.0,
      receiptLineSpacing:
          double.tryParse(map['receipt_line_spacing'] ?? '') ?? 1.25,
      receiptMarginMm: double.tryParse(map['receipt_margin_mm'] ?? '') ?? 4.0,
      showStoreLogo: (map['show_store_logo'] ?? 'false') == 'true',
      storeLogoPath: map['store_logo_path'] ?? '',
      customHeaderNote: map['custom_header_note'] ?? '',
      customFooterNote: map['custom_footer_note'] ?? '',
      autoStartOnLogin: (map['auto_start_on_login'] ?? 'false') == 'true',
      minimizeToTrayOnClose:
          (map['minimize_to_tray_on_close'] ?? 'true') == 'true',
      retentionDays: int.tryParse(map['retention_days'] ?? '') ?? 30,
      lanOperatingMode: LanOperatingMode.fromString(
        map['lan_operating_mode'] ?? 'direct',
      ),
      coordinatorBindHost: map['coordinator_bind_host'] ?? '0.0.0.0',
      coordinatorPort: int.tryParse(map['coordinator_port'] ?? '') ?? 8766,
      remoteCoordinatorUrl: map['remote_coordinator_url'] ?? '',
      remoteCoordinatorToken: map['remote_coordinator_token'] ?? '',
      discoverySubnetPrefix: map['discovery_subnet_prefix'] ?? '192.168.1',
    );
  }

  Map<String, String> toKeyValueMap() => {
    'local_api_port': localApiPort.toString(),
    'require_pairing_auth': requirePairingAuth.toString(),
    'allowed_origins': allowedOrigins.join(','),
    'default_paper_width': defaultPaperWidth.toString(),
    'receipt_font_size': receiptFontSize.toString(),
    'receipt_line_spacing': receiptLineSpacing.toString(),
    'receipt_margin_mm': receiptMarginMm.toString(),
    'show_store_logo': showStoreLogo.toString(),
    'store_logo_path': storeLogoPath,
    'custom_header_note': customHeaderNote,
    'custom_footer_note': customFooterNote,
    'auto_start_on_login': autoStartOnLogin.toString(),
    'minimize_to_tray_on_close': minimizeToTrayOnClose.toString(),
    'retention_days': retentionDays.toString(),
    'lan_operating_mode': lanOperatingMode.value,
    'coordinator_bind_host': coordinatorBindHost,
    'coordinator_port': coordinatorPort.toString(),
    'remote_coordinator_url': remoteCoordinatorUrl,
    'remote_coordinator_token': remoteCoordinatorToken,
    'discovery_subnet_prefix': discoverySubnetPrefix,
  };

  AppSettingsModel copyWith({
    int? localApiPort,
    bool? requirePairingAuth,
    List<String>? allowedOrigins,
    int? defaultPaperWidth,
    double? receiptFontSize,
    double? receiptLineSpacing,
    double? receiptMarginMm,
    bool? showStoreLogo,
    String? storeLogoPath,
    String? customHeaderNote,
    String? customFooterNote,
    bool? autoStartOnLogin,
    bool? minimizeToTrayOnClose,
    int? retentionDays,
    LanOperatingMode? lanOperatingMode,
    String? coordinatorBindHost,
    int? coordinatorPort,
    String? remoteCoordinatorUrl,
    String? remoteCoordinatorToken,
    String? discoverySubnetPrefix,
  }) {
    return AppSettingsModel(
      localApiPort: localApiPort ?? this.localApiPort,
      requirePairingAuth: requirePairingAuth ?? this.requirePairingAuth,
      allowedOrigins: allowedOrigins ?? this.allowedOrigins,
      defaultPaperWidth: defaultPaperWidth ?? this.defaultPaperWidth,
      receiptFontSize: receiptFontSize ?? this.receiptFontSize,
      receiptLineSpacing: receiptLineSpacing ?? this.receiptLineSpacing,
      receiptMarginMm: receiptMarginMm ?? this.receiptMarginMm,
      showStoreLogo: showStoreLogo ?? this.showStoreLogo,
      storeLogoPath: storeLogoPath ?? this.storeLogoPath,
      customHeaderNote: customHeaderNote ?? this.customHeaderNote,
      customFooterNote: customFooterNote ?? this.customFooterNote,
      autoStartOnLogin: autoStartOnLogin ?? this.autoStartOnLogin,
      minimizeToTrayOnClose:
          minimizeToTrayOnClose ?? this.minimizeToTrayOnClose,
      retentionDays: retentionDays ?? this.retentionDays,
      lanOperatingMode: lanOperatingMode ?? this.lanOperatingMode,
      coordinatorBindHost: coordinatorBindHost ?? this.coordinatorBindHost,
      coordinatorPort: coordinatorPort ?? this.coordinatorPort,
      remoteCoordinatorUrl: remoteCoordinatorUrl ?? this.remoteCoordinatorUrl,
      remoteCoordinatorToken:
          remoteCoordinatorToken ?? this.remoteCoordinatorToken,
      discoverySubnetPrefix:
          discoverySubnetPrefix ?? this.discoverySubnetPrefix,
    );
  }
}
