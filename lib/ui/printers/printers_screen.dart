import 'package:flutter/material.dart';
import '../../modules/printer_discovery/printer_discovery_service.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/printer_model.dart';
import '../../shared/models/routing_rule_model.dart';
import '../../shared/services/service_locator.dart';
import '../pairing/receipt_preview_dialog.dart';
import 'printer_form_dialog.dart';

/// Printer Management screen in Thai supporting multiple USB/LAN/Wi-Fi/OS
/// printers, controlled printer discovery, test printing, and routing rules.
class PrintersScreen extends StatefulWidget {
  final AgentServiceContainer services;

  const PrintersScreen({super.key, required this.services});

  @override
  State<PrintersScreen> createState() => _PrintersScreenState();
}

class _PrintersScreenState extends State<PrintersScreen> {
  bool _isDiscovering = false;
  List<DiscoveredPrinterCandidate> _discovered = const [];

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.services.printerManager,
        widget.services.routingEngine,
      ]),
      builder: (context, _) {
        final printers = widget.services.printerManager.listPrinters();
        final rules = widget.services.routingEngine.listRules();

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'จัดการเครื่องพิมพ์และกฎการส่งพิมพ์ (Printer Management)',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'รองรับเครื่องพิมพ์ USB, LAN (ESC/POS Port 9100, IPP, LPR), Wi-Fi และไดรเวอร์ระบบปฏิบัติการ',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed:
                            _isDiscovering ? null : () => _showDiscoveryModal(),
                        icon: const Icon(Icons.radar, size: 18),
                        label: const Text('ค้นหาเครื่องพิมพ์อัตโนมัติ'),
                      ),
                      FilledButton.icon(
                        onPressed: () => _openAddOrEditDialog(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('เพิ่มเครื่องพิมพ์ใหม่'),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              if (printers.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(36),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.print_disabled_outlined,
                            size: 48,
                            color: Colors.grey.shade400,
                          ),
                          const SizedBox(height: 12),
                          const Text(
                            'ยังไม่มีเครื่องพิมพ์ในระบบ กดปุ่ม "เพิ่มเครื่องพิมพ์ใหม่" หรือ "ค้นหาเครื่องพิมพ์อัตโนมัติ"',
                            style: TextStyle(color: Colors.black54),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: printers.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final printer = printers[index];
                    return _buildPrinterCard(printer, printers);
                  },
                ),

              const SizedBox(height: 32),

              // Print Routing Rules Section
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'กฎการเลือกเครื่องพิมพ์ตามประเภทงาน (Print Routing Rules)',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 4),
                                Text(
                                  'กำหนดให้ใบเสร็จลูกค้า ใบสั่งครัว หรือรายงาน แยกพิมพ์ไปยังเครื่องพิมพ์ที่ต้องการโดยอัตโนมัติ',
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    color: Colors.black54,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          OutlinedButton.icon(
                            onPressed:
                                printers.isEmpty
                                    ? null
                                    : () => _openRoutingRuleDialog(printers),
                            icon: const Icon(Icons.alt_route, size: 18),
                            label: const Text('เพิ่มกฎการส่งพิมพ์'),
                          ),
                        ],
                      ),
                      const Divider(height: 24),
                      if (rules.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 16),
                          child: Text(
                            'ยังไม่ได้กำหนดกฎพิเศษ — ระบบจะส่งงานพิมพ์ทั้งหมดไปยังเครื่องพิมพ์ค่าเริ่มต้น (Default Printer)',
                            style: TextStyle(color: Colors.black54),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: rules.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final rule = rules[idx];
                            final targetPrinter = widget.services.printerManager
                                .getPrinterById(rule.printerId);
                            final typeLabel =
                                PrintJobType.fromString(rule.jobType).thaiLabel;
                            return ListTile(
                              leading: CircleAvatar(
                                backgroundColor: Colors.indigo.shade50,
                                child: Text(
                                  '#${rule.priority}',
                                  style: TextStyle(
                                    color: Colors.indigo.shade800,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              title: Text(
                                '$typeLabel → ${targetPrinter?.name ?? "ไม่พบเครื่องพิมพ์ (${rule.printerId})"}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'รหัสประเภทงาน: "${rule.jobType}" • ลำดับความสำคัญ: ${rule.priority}',
                              ),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Switch(
                                    value: rule.enabled,
                                    onChanged: (val) {
                                      widget.services.routingEngine.saveRule(
                                        id: rule.id,
                                        jobType: rule.jobType,
                                        printerId: rule.printerId,
                                        priority: rule.priority,
                                        enabled: val,
                                      );
                                    },
                                  ),
                                  IconButton(
                                    tooltip: 'ลบกฎนี้',
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                    ),
                                    onPressed: () {
                                      widget.services.routingEngine.deleteRule(
                                        rule.id,
                                      );
                                    },
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPrinterCard(
    PrinterModel printer,
    List<PrinterModel> allPrinters,
  ) {
    final connectionDetail =
        (printer.host != null && printer.host!.isNotEmpty)
            ? '${printer.host}:${printer.port ?? 9100} (${printer.protocol.label})'
            : '${printer.protocol.label} (${printer.configuration.osDriverName ?? printer.name})';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color:
              printer.isDefault ? Colors.indigo.shade400 : Colors.grey.shade300,
          width: printer.isDefault ? 1.5 : 1.0,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color:
                    printer.isOnline
                        ? Colors.green.shade50
                        : Colors.red.shade50,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                printer.connectionType == PrinterConnectionType.lan ||
                        printer.connectionType == PrinterConnectionType.wifi
                    ? Icons.router_outlined
                    : Icons.print_outlined,
                color:
                    printer.isOnline
                        ? Colors.green.shade700
                        : Colors.red.shade700,
                size: 28,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        printer.name,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (printer.isDefault)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade50,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'ค่าเริ่มต้น (Default)',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.bold,
                              color: Colors.indigo.shade800,
                            ),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.grey.shade200,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          'กระดาษ ${AppConstants.formatPaperWidthLabel(printer.paperWidth)}',
                          style: const TextStyle(fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${printer.connectionType.thaiLabel} • $connectionDetail',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Wrap(
              spacing: 8,
              children: [
                if (!printer.isDefault)
                  TextButton(
                    onPressed: () {
                      widget.services.printerManager.setDefaultPrinter(
                        printer.id,
                      );
                    },
                    child: const Text('ตั้งเป็นค่าเริ่มต้น'),
                  ),
                OutlinedButton.icon(
                  onPressed: () => _previewAndTestPrinter(printer),
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text('ดูตัวอย่าง / พิมพ์ทดสอบ'),
                ),
                IconButton(
                  tooltip: 'ตรวจสอบการเชื่อมต่อ',
                  icon: const Icon(Icons.network_check),
                  onPressed: () async {
                    final online = await widget.services.printerManager
                        .checkPrinterOnline(printer);
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          online
                              ? 'เครื่องพิมพ์ "${printer.name}" พร้อมใช้งาน'
                              : 'ไม่สามารถติดต่อเครื่องพิมพ์ "${printer.name}" ได้',
                        ),
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: 'แก้ไขเครื่องพิมพ์',
                  icon: const Icon(Icons.edit_outlined),
                  onPressed:
                      () => _openAddOrEditDialog(
                        existing: printer,
                        allPrinters: allPrinters,
                      ),
                ),
                IconButton(
                  tooltip: 'ลบเครื่องพิมพ์',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () {
                    widget.services.printerManager.removePrinter(printer.id);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openAddOrEditDialog({
    PrinterModel? existing,
    List<PrinterModel>? allPrinters,
  }) async {
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder:
          (_) => PrinterFormDialog(
            existing: existing,
            allPrinters:
                allPrinters ?? widget.services.printerManager.listPrinters(),
          ),
    );
    if (result == null) return;

    if (existing == null) {
      widget.services.printerManager.addPrinter(
        name: result['name'] as String,
        connectionType: result['connectionType'] as PrinterConnectionType,
        protocol: result['protocol'] as PrinterProtocol,
        host: result['host'] as String?,
        port: result['port'] as int?,
        paperWidth: result['paperWidth'] as int,
        isDefault: result['isDefault'] as bool,
        enabled: result['enabled'] as bool,
        configuration: result['configuration'] as PrinterConfiguration,
      );
    } else {
      widget.services.printerManager.updatePrinter(
        existing.copyWith(
          name: result['name'] as String,
          connectionType: result['connectionType'] as PrinterConnectionType,
          protocol: result['protocol'] as PrinterProtocol,
          host: result['host'] as String?,
          port: result['port'] as int?,
          paperWidth: result['paperWidth'] as int,
          isDefault: result['isDefault'] as bool,
          enabled: result['enabled'] as bool,
          configuration: result['configuration'] as PrinterConfiguration,
        ),
      );
    }
  }

  void _previewAndTestPrinter(PrinterModel printer) {
    final payload = widget.services.printerManager.buildTestReceiptPayload(
      printer,
    );
    final settings = widget.services.configService.settings;
    final doc = widget.services.receiptRenderer.render(
      payload,
      overridePaperWidthMm: printer.paperWidth,
      fontSize: settings.receiptFontSize * printer.configuration.fontScale,
      lineSpacing: printer.configuration.lineSpacing,
      marginMm: printer.configuration.marginMm,
    );

    showDialog<void>(
      context: context,
      builder:
          (_) => ReceiptPreviewDialog(
            document: doc,
            onConfirmPrint: () {
              widget.services.printQueueService.enqueueReceipt(
                payload,
                overridePrinterId: printer.id,
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    'ส่งงานพิมพ์ทดสอบไปยังคิวของ "${printer.name}" แล้ว',
                  ),
                ),
              );
            },
          ),
    );
  }

  Future<void> _showDiscoveryModal() async {
    final subnetCtrl = TextEditingController(
      text: widget.services.configService.settings.discoverySubnetPrefix,
    );
    setState(() {
      _isDiscovering = true;
      _discovered = const [];
    });

    final osPrinters =
        await widget.services.discoveryService.discoverOsAndUsbPrinters();
    if (!mounted) return;
    setState(() {
      _isDiscovering = false;
      _discovered = osPrinters;
    });

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text(
                'ค้นหาเครื่องพิมพ์ในระบบและเครือข่าย (Printer Discovery)',
              ),
              content: SizedBox(
                width: 600,
                height: 440,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'แนะนำให้กำหนด Static IP หรือ DHCP Reservation สำหรับเครื่องพิมพ์ LAN ที่ใช้งานร่วมกัน',
                      style: TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: subnetCtrl,
                            decoration: const InputDecoration(
                              labelText:
                                  'วงเครือข่าย Subnet (3 ชุดแรก เช่น 192.168.1)',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.tonalIcon(
                          onPressed: () async {
                            setModalState(() => _isDiscovering = true);
                            try {
                              final lanFound = await widget
                                  .services
                                  .discoveryService
                                  .discoverControlledSubnet(
                                    subnetPrefix: subnetCtrl.text.trim(),
                                    startHost: 1,
                                    endHost: 60,
                                  );
                              setModalState(() {
                                _discovered = [...osPrinters, ...lanFound];
                                _isDiscovering = false;
                              });
                            } catch (_) {
                              setModalState(() => _isDiscovering = false);
                            }
                          },
                          icon: const Icon(Icons.lan_outlined, size: 18),
                          label: const Text('สแกนเครื่องพิมพ์ LAN (Port 9100)'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    if (_isDiscovering)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_discovered.isEmpty)
                      const Expanded(
                        child: Center(
                          child: Text('ไม่พบเครื่องพิมพ์เพิ่มเติม'),
                        ),
                      )
                    else
                      Expanded(
                        child: ListView.separated(
                          itemCount: _discovered.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (_, idx) {
                            final cand = _discovered[idx];
                            return ListTile(
                              leading: const Icon(Icons.print),
                              title: Text(cand.name),
                              subtitle: Text(
                                '${cand.connectionType.thaiLabel} • ${cand.protocol.label}'
                                '${cand.host != null ? " (${cand.host}:${cand.port})" : ""}',
                              ),
                              trailing: FilledButton(
                                onPressed: () {
                                  widget.services.printerManager.addPrinter(
                                    name: cand.name,
                                    connectionType: cand.connectionType,
                                    protocol: cand.protocol,
                                    host: cand.host,
                                    port: cand.port,
                                    configuration: PrinterConfiguration(
                                      osDriverName: cand.osDriverName,
                                    ),
                                  );
                                  Navigator.of(ctx).pop();
                                },
                                child: const Text('เพิ่มเครื่องพิมพ์นี้'),
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('ปิด'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _openRoutingRuleDialog(List<PrinterModel> printers) async {
    PrintJobType selectedType = PrintJobType.receipt;
    String selectedPrinterId = printers.first.id;
    final priorityCtrl = TextEditingController(text: '1');

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              title: const Text('เพิ่มกฎการเลือกเครื่องพิมพ์ (Routing Rule)'),
              content: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<PrintJobType>(
                      isExpanded: true,
                      initialValue: selectedType,
                      decoration: const InputDecoration(
                        labelText: 'ประเภทงานพิมพ์ (Job Type)',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          PrintJobType.values
                              .map(
                                (t) => DropdownMenuItem(
                                  value: t,
                                  child: Text(
                                    t.thaiLabel,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => selectedType = v);
                      },
                    ),
                    const SizedBox(height: 14),
                    DropdownButtonFormField<String>(
                      isExpanded: true,
                      initialValue: selectedPrinterId,
                      decoration: const InputDecoration(
                        labelText: 'ส่งไปยังเครื่องพิมพ์ (Target Printer)',
                        border: OutlineInputBorder(),
                      ),
                      items:
                          printers
                              .map(
                                (p) => DropdownMenuItem(
                                  value: p.id,
                                  child: Text(
                                    '${p.name} (${AppConstants.formatPaperWidthLabel(p.paperWidth)})',
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setModalState(() => selectedPrinterId = v);
                        }
                      },
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: priorityCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText:
                            'ลำดับความสำคัญ (Priority — ตัวเลขน้อยทำงานก่อน)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: const Text('ยกเลิก'),
                ),
                FilledButton(
                  onPressed: () {
                    final prio = int.tryParse(priorityCtrl.text.trim()) ?? 1;
                    widget.services.routingEngine.saveRule(
                      jobType: selectedType.value,
                      printerId: selectedPrinterId,
                      priority: prio,
                    );
                    Navigator.of(ctx).pop();
                  },
                  child: const Text('บันทึกกฎ'),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
