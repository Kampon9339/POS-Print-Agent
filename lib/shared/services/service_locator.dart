import 'dart:io';
import 'package:path/path.dart' as p;
import '../../core/api_server/local_api_server.dart';
import '../../core/configuration/app_config_service.dart';
import '../../core/database/app_database.dart';
import '../../core/database/database_backup_service.dart';
import '../../core/logging/app_logger.dart';
import '../../core/system_tray/auto_start_service.dart';
import '../../core/system_tray/system_tray_service.dart';
import '../../modules/pairing/paired_device_repository.dart';
import '../../modules/pairing/pairing_service.dart';
import '../../modules/print_coordinator/central_coordinator_server.dart';
import '../../modules/print_coordinator/coordinator_client.dart';
import '../../modules/print_engine/print_backend.dart';
import '../../modules/print_history/print_history_service.dart';
import '../../modules/print_queue/print_job_repository.dart';
import '../../modules/print_queue/print_queue_service.dart';
import '../../modules/print_routing/print_routing_engine.dart';
import '../../modules/print_routing/routing_rule_repository.dart';
import '../../modules/printer_discovery/printer_discovery_service.dart';
import '../../modules/printer_manager/printer_manager.dart';
import '../../modules/printer_manager/printer_repository.dart';
import '../../modules/receipt_engine/pdf_receipt_builder.dart';
import '../../modules/receipt_engine/receipt_renderer.dart';
import '../models/app_settings_model.dart';

/// Dependency injection container holding all initialized services for the
/// POS Print Agent desktop application.
class AgentServiceContainer {
  final AppLogger logger;
  final AppDatabase db;
  final DatabaseBackupService backupService;
  final AppConfigService configService;
  final PrinterRepository printerRepository;
  final PrinterDiscoveryService discoveryService;
  final PrinterManager printerManager;
  final RoutingRuleRepository routingRuleRepository;
  final PrintRoutingEngine routingEngine;
  final PrintJobRepository printJobRepository;
  final PrintQueueService printQueueService;
  final PrintHistoryService printHistoryService;
  final PairedDeviceRepository pairedDeviceRepository;
  final PairingService pairingService;
  final LocalApiServer localApiServer;
  final CentralCoordinatorServer coordinatorServer;
  final AutoStartService autoStartService;
  late final SystemTrayService systemTrayService;
  final ReceiptRenderer receiptRenderer;
  final PdfReceiptBuilder pdfReceiptBuilder;
  final String dataDirectoryPath;

  AgentServiceContainer._({
    required this.logger,
    required this.db,
    required this.backupService,
    required this.configService,
    required this.printerRepository,
    required this.discoveryService,
    required this.printerManager,
    required this.routingRuleRepository,
    required this.routingEngine,
    required this.printJobRepository,
    required this.printQueueService,
    required this.printHistoryService,
    required this.pairedDeviceRepository,
    required this.pairingService,
    required this.localApiServer,
    required this.coordinatorServer,
    required this.autoStartService,
    required this.receiptRenderer,
    required this.pdfReceiptBuilder,
    required this.dataDirectoryPath,
  }) {
    systemTrayService = SystemTrayService(
      logger: logger,
      onQuitRequested: shutdown,
    );
  }

  /// Initializes the production container using the OS application support directory.
  static Future<AgentServiceContainer> initializeProduction() async {
    final supportPath = _resolveDesktopAppSupportPath();

    final dbPath = p.join(supportPath, 'pos_print_agent.sqlite');
    final logger = AppLogger(printToStdout: false);
    final db = AppDatabase.openFile(dbPath, logger: logger);

    final container = _buildFromDatabase(
      db: db,
      logger: logger,
      dataDirectoryPath: supportPath,
    );

    // 1. Run startup recovery & retention policy
    container.printQueueService.recoverAfterRestart();
    container.backupService.applyRetentionPolicy(
      retentionDays: container.configService.settings.retentionDays,
    );

    // 2. Start Local HTTP API (bound to 127.0.0.1)
    try {
      await container.localApiServer.start(
        port: container.configService.settings.localApiPort,
      );
    } catch (e) {
      logger.error('Startup', 'Failed to bind default Local API port: $e');
    }

    // 3. Start Central Coordinator if configured in coordinatorHost mode
    if (container.configService.settings.lanOperatingMode ==
        LanOperatingMode.coordinatorHost) {
      try {
        await container.coordinatorServer.start(
          host: container.configService.settings.coordinatorBindHost,
          port: container.configService.settings.coordinatorPort,
        );
      } catch (e) {
        logger.error('Startup', 'Failed to start Central Coordinator: $e');
      }
    }

    // 4. Initialize System Tray
    await container.systemTrayService.initialize(
      statusText: 'สถานะ: ออนไลน์ (${container.localApiServer.bindAddress})',
    );

    return container;
  }

  static String _resolveDesktopAppSupportPath() {
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'];
      if (home != null && home.isNotEmpty) {
        return p.join(home, 'Library', 'Application Support', 'POSPrintAgent');
      }
    } else if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        return p.join(appData, 'POSPrintAgent');
      }
    }
    final fallbackHome =
        Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'] ??
        Directory.systemTemp.path;
    return p.join(fallbackHome, '.pos_print_agent');
  }

  /// Creates an in-memory container for automated tests with optional mock backends.
  static AgentServiceContainer createForTest({
    IPrintBackend? osBackend,
    IPrintBackend? tcpBackend,
    IPrintBackend? usbBackend,
  }) {
    final logger = AppLogger(printToStdout: false);
    final db = AppDatabase.openInMemory(logger: logger);
    return _buildFromDatabase(
      db: db,
      logger: logger,
      dataDirectoryPath: Directory.systemTemp.path,
      osBackend: osBackend,
      tcpBackend: tcpBackend,
      usbBackend: usbBackend,
    );
  }

  static AgentServiceContainer _buildFromDatabase({
    required AppDatabase db,
    required AppLogger logger,
    required String dataDirectoryPath,
    IPrintBackend? osBackend,
    IPrintBackend? tcpBackend,
    IPrintBackend? usbBackend,
  }) {
    final backupService = DatabaseBackupService(db);
    final configService = AppConfigService(db);
    final printerRepository = PrinterRepository(db);
    const discoveryService = PrinterDiscoveryService();
    const receiptRenderer = ReceiptRenderer();
    const pdfReceiptBuilder = PdfReceiptBuilder();

    final coordClient = CoordinatorForwardBackend(
      configService: configService,
      logger: logger,
    );

    final printerManager = PrinterManager(
      repository: printerRepository,
      logger: logger,
      discoveryService: discoveryService,
      receiptRenderer: receiptRenderer,
      osBackend: osBackend,
      tcpBackend: tcpBackend,
      usbBackend: usbBackend,
      coordinatorForwardBackend: coordClient,
    );

    final routingRuleRepository = RoutingRuleRepository(db);
    final routingEngine = PrintRoutingEngine(
      ruleRepository: routingRuleRepository,
      printerManager: printerManager,
      logger: logger,
    );

    final printJobRepository = PrintJobRepository(db);
    final printQueueService = PrintQueueService(
      repository: printJobRepository,
      printerManager: printerManager,
      routingEngine: routingEngine,
      configService: configService,
      logger: logger,
      receiptRenderer: receiptRenderer,
    );

    final printHistoryService = PrintHistoryService(printJobRepository);
    final pairedDeviceRepository = PairedDeviceRepository(db);
    final pairingService = PairingService(
      repository: pairedDeviceRepository,
      logger: logger,
    );

    final localApiServer = LocalApiServer(
      configService: configService,
      printerManager: printerManager,
      printQueueService: printQueueService,
      pairingService: pairingService,
      logger: logger,
      discoveryService: discoveryService,
    );

    final coordinatorServer = CentralCoordinatorServer(
      pairingService: pairingService,
      printerManager: printerManager,
      printQueueService: printQueueService,
      logger: logger,
    );

    final autoStartService = AutoStartService(logger: logger);

    return AgentServiceContainer._(
      logger: logger,
      db: db,
      backupService: backupService,
      configService: configService,
      printerRepository: printerRepository,
      discoveryService: discoveryService,
      printerManager: printerManager,
      routingRuleRepository: routingRuleRepository,
      routingEngine: routingEngine,
      printJobRepository: printJobRepository,
      printQueueService: printQueueService,
      printHistoryService: printHistoryService,
      pairedDeviceRepository: pairedDeviceRepository,
      pairingService: pairingService,
      localApiServer: localApiServer,
      coordinatorServer: coordinatorServer,
      autoStartService: autoStartService,
      receiptRenderer: receiptRenderer,
      pdfReceiptBuilder: pdfReceiptBuilder,
      dataDirectoryPath: dataDirectoryPath,
    );
  }

  /// Gracefully waits for active print jobs, stops servers, and closes SQLite.
  Future<void> shutdown() async {
    logger.info('Shutdown', 'Shutting down POS Print Agent services');
    await printQueueService.shutdownGracefully();
    await localApiServer.stop();
    await coordinatorServer.stop();
    db.close();
  }
}
