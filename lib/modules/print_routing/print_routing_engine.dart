import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';
import '../../core/logging/app_logger.dart';
import '../../shared/models/printer_model.dart';
import '../../shared/models/receipt_payload.dart';
import '../../shared/models/routing_rule_model.dart';
import '../printer_manager/printer_manager.dart';
import 'routing_rule_repository.dart';

/// Resolves which configured [PrinterModel] should handle a given print request.
class PrintRoutingEngine extends ChangeNotifier {
  final RoutingRuleRepository ruleRepository;
  final PrinterManager printerManager;
  final AppLogger logger;
  final Uuid _uuid = const Uuid();

  PrintRoutingEngine({
    required this.ruleRepository,
    required this.printerManager,
    required this.logger,
  });

  List<RoutingRuleModel> listRules() => ruleRepository.listAll();

  RoutingRuleModel saveRule({
    String? id,
    required String jobType,
    required String printerId,
    int priority = 1,
    bool enabled = true,
  }) {
    final rule = RoutingRuleModel(
      id: id ?? _uuid.v4(),
      jobType: jobType.trim().toLowerCase(),
      printerId: printerId,
      priority: priority,
      enabled: enabled,
    );
    ruleRepository.upsert(rule);
    logger.info('RoutingEngine', 'Saved routing rule', rule.toJson());
    notifyListeners();
    return rule;
  }

  bool deleteRule(String id) {
    final ok = ruleRepository.delete(id);
    if (ok) {
      logger.info('RoutingEngine', 'Deleted routing rule', {'id': id});
      notifyListeners();
    }
    return ok;
  }

  /// Resolves the target printer for [payload] (or explicit [overridePrinterId]):
  /// 1. Explicit [overridePrinterId] or [payload.targetPrinterId] if enabled
  /// 2. Enabled routing rules matching [payload.jobType] ordered by priority
  /// 3. Backup printer (`printer.configuration.backupPrinterId`) if primary is disabled/offline
  /// 4. Default enabled printer (`isDefault == true`)
  /// 5. First enabled printer
  PrinterModel? resolvePrinterForReceipt(
    ReceiptPayload payload, {
    String? overridePrinterId,
  }) {
    final requestedId = overridePrinterId ?? payload.targetPrinterId;
    if (requestedId != null && requestedId.trim().isNotEmpty) {
      final explicit = printerManager.getPrinterById(requestedId.trim());
      if (explicit != null && explicit.enabled) {
        return _resolveOnlineOrBackup(explicit);
      }
    }

    final rules = ruleRepository.listForJobType(
      payload.jobType,
      onlyEnabled: true,
    );
    for (final rule in rules) {
      final candidate = printerManager.getPrinterById(rule.printerId);
      if (candidate != null && candidate.enabled) {
        return _resolveOnlineOrBackup(candidate);
      }
    }

    final defaultPrinter = printerManager.getDefaultPrinter();
    if (defaultPrinter != null && defaultPrinter.enabled) {
      return _resolveOnlineOrBackup(defaultPrinter);
    }

    return null;
  }

  PrinterModel _resolveOnlineOrBackup(PrinterModel primary) {
    if (primary.isOnline) {
      return primary;
    }
    final backupId = primary.configuration.backupPrinterId;
    if (backupId != null && backupId.trim().isNotEmpty) {
      final backup = printerManager.getPrinterById(backupId.trim());
      if (backup != null && backup.enabled && backup.isOnline) {
        logger.warn(
          'RoutingEngine',
          'Primary printer offline; failing over to backup printer',
          {'primaryPrinterId': primary.id, 'backupPrinterId': backup.id},
        );
        return backup;
      }
    }
    return primary;
  }
}
