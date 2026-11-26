import 'package:flutter/material.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/print_job_model.dart';
import '../../shared/services/service_locator.dart';
import '../../shared/utilities/format_utils.dart';
import '../pairing/receipt_preview_dialog.dart';

/// Main Thai-language Dashboard displaying Agent status, Local API status,
/// Pairing status, Printer count, Queue statistics, and Recent print activity.
class DashboardScreen extends StatelessWidget {
  final AgentServiceContainer services;
  final void Function(int tabIndex) onNavigateTab;

  const DashboardScreen({
    super.key,
    required this.services,
    required this.onNavigateTab,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.localApiServer,
        services.coordinatorServer,
        services.printerManager,
        services.printQueueService,
        services.pairingService,
        services.configService,
      ]),
      builder: (context, _) {
        final printers = services.printerManager.listPrinters();
        final connectedPrinters = printers.where((p) => p.isOnline).length;
        final defaultPrinter = services.printerManager.getDefaultPrinter();
        final queueStats = services.printQueueService.getQueueStatistics();
        final recentJobs = services.printQueueService.listJobs(limit: 8);
        final pairedDevices = services.pairingService.listDevices(
          includeRevoked: false,
        );
        final pendingPairings = services.pairingService.pendingSessions;
        final settings = services.configService.settings;

        final pendingCount =
            (queueStats['queued'] ?? 0) +
            (queueStats['rendering'] ?? 0) +
            (queueStats['printing'] ?? 0);
        final submittedCount = queueStats['submitted'] ?? 0;
        final failedCount = queueStats['failed'] ?? 0;
        final totalCount = queueStats['total'] ?? 0;

        return SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Top header bar
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'แผงควบคุมระบบพิมพ์ (POS Print Agent Dashboard)',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'เวอร์ชัน ${AppConstants.appVersion} • โหมดเครือข่าย: ${settings.lanOperatingMode.thaiLabel}',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Wrap(
                    spacing: 10,
                    children: [
                      OutlinedButton.icon(
                        onPressed: () {
                          services.printerManager.refreshAllPrinterStatuses();
                        },
                        icon: const Icon(Icons.refresh, size: 18),
                        label: const Text('ตรวจสอบสถานะเครื่องพิมพ์'),
                      ),
                      if (defaultPrinter != null)
                        FilledButton.icon(
                          onPressed: () async {
                            final payload = services.printerManager
                                .buildTestReceiptPayload(defaultPrinter);
                            final doc = services.receiptRenderer.render(
                              payload,
                              overridePaperWidthMm: defaultPrinter.paperWidth,
                              fontSize: settings.receiptFontSize,
                              lineSpacing: settings.receiptLineSpacing,
                              marginMm: settings.receiptMarginMm,
                            );
                            if (!context.mounted) return;
                            showDialog<void>(
                              context: context,
                              builder:
                                  (_) => ReceiptPreviewDialog(
                                    document: doc,
                                    onConfirmPrint: () {
                                      services.printQueueService.enqueueReceipt(
                                        payload,
                                        overridePrinterId: defaultPrinter.id,
                                      );
                                    },
                                  ),
                            );
                          },
                          icon: const Icon(Icons.print_outlined, size: 18),
                          label: const Text('พิมพ์ใบเสร็จทดสอบ'),
                        ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Alert banner if pairing request is waiting
              if (pendingPairings.isNotEmpty)
                Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.amber.shade50,
                    border: Border.all(color: Colors.amber.shade400),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.security_update_warning,
                        color: Colors.amber.shade900,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'มีคำขอเชื่อมต่อจากระบบ Web POS รอการยืนยัน ${pendingPairings.length} รายการ (รหัสยืนยัน: ${pendingPairings.first.pairingCode})',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: () => onNavigateTab(4),
                        child: const Text('ไปที่หน้าเชื่อมต่อ POS'),
                      ),
                    ],
                  ),
                ),

              // Status metrics grid
              LayoutBuilder(
                builder: (context, constraints) {
                  final cardWidth =
                      constraints.maxWidth > 900
                          ? (constraints.maxWidth - 36) / 4
                          : (constraints.maxWidth - 12) / 2;
                  return Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      SizedBox(
                        width: cardWidth,
                        child: _StatusMetricCard(
                          title: 'สถานะตัวแทนพิมพ์ (Agent & API)',
                          value:
                              services.localApiServer.isRunning
                                  ? 'พร้อมใช้งาน (ออนไลน์)'
                                  : 'หยุดทำงาน',
                          subtitle:
                              'Local API: ${services.localApiServer.bindAddress}',
                          icon: Icons.dns_rounded,
                          color:
                              services.localApiServer.isRunning
                                  ? Colors.teal
                                  : Colors.red,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _StatusMetricCard(
                          title: 'เครื่องพิมพ์ที่ตั้งค่าแล้ว',
                          value:
                              'เชื่อมต่อ $connectedPrinters / ${printers.length} เครื่อง',
                          subtitle:
                              defaultPrinter != null
                                  ? 'ค่าเริ่มต้น: ${defaultPrinter.name} (${defaultPrinter.paperWidth}mm)'
                                  : 'ยังไม่ได้ตั้งค่าเครื่องพิมพ์เริ่มต้น',
                          icon: Icons.print_rounded,
                          color: Colors.indigo,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _StatusMetricCard(
                          title: 'สถานะการจับคู่ Web POS',
                          value: '${pairedDevices.length} อุปกรณ์ที่อนุญาต',
                          subtitle:
                              settings.requirePairingAuth
                                  ? 'บังคับใช้การยืนยันตัวตนด้วย Token'
                                  : 'เปิดรับคำสั่งพิมพ์ผ่าน Localhost',
                          icon: Icons.verified_user_rounded,
                          color: Colors.blue.shade700,
                        ),
                      ),
                      SizedBox(
                        width: cardWidth,
                        child: _StatusMetricCard(
                          title: 'สรุปงานพิมพ์ทั้งหมด',
                          value: '$totalCount งาน (สำเร็จ $submittedCount)',
                          subtitle:
                              'กำลังรอคิว: $pendingCount • ล้มเหลว: $failedCount',
                          icon: Icons.receipt_long_rounded,
                          color:
                              failedCount > 0
                                  ? Colors.deepOrange
                                  : Colors.green.shade700,
                        ),
                      ),
                    ],
                  );
                },
              ),

              const SizedBox(height: 24),

              // Important physical printing disclaimer banner
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  color: Colors.blueGrey.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blueGrey.shade200),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Colors.blueGrey.shade700,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'หมายเหตุสำคัญ: สถานะ "ส่งเข้าเครื่องพิมพ์แล้ว (submitted)" หมายถึงระบบปฏิบัติการหรือเครื่องพิมพ์รับคำสั่งพิมพ์เรียบร้อยแล้ว ไม่ได้การันตีว่ากระดาษถูกพิมพ์ออกมาจริงหากกระดาษหมดหรือฝาเครื่องเปิด',
                        style: TextStyle(
                          fontSize: 12.5,
                          color: Colors.blueGrey.shade800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Recent print jobs table
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'รายการพิมพ์ล่าสุด (Recent Print Activity)',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () => onNavigateTab(2),
                            icon: const Icon(Icons.arrow_forward, size: 16),
                            label: const Text('ดูคิวพิมพ์ทั้งหมด'),
                          ),
                        ],
                      ),
                      const Divider(),
                      if (recentJobs.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 32),
                          child: Center(
                            child: Text(
                              'ยังไม่มีประวัติการพิมพ์ใบเสร็จ',
                              style: TextStyle(color: Colors.grey),
                            ),
                          ),
                        )
                      else
                        ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: recentJobs.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final job = recentJobs[idx];
                            final printerName =
                                services.printerManager
                                    .getPrinterById(job.printerId)
                                    ?.name ??
                                job.printerId;
                            return ListTile(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              leading: _buildStatusChip(job.status),
                              title: Text(
                                'บิล: ${job.billNumber} (${FormatUtils.formatCopyTypeThai(job.copyType)})',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'รหัสงาน: ${job.id} • เครื่องพิมพ์: $printerName • เวลา: ${FormatUtils.formatReceiptDateTime(job.createdAt.toIso8601String())}'
                                '${job.errorMessage != null ? "\nข้อผิดพลาด: ${job.errorMessage}" : ""}',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color:
                                      job.errorMessage != null
                                          ? Colors.red.shade700
                                          : Colors.grey.shade700,
                                ),
                              ),
                              trailing: IconButton(
                                tooltip: 'ดูตัวอย่างใบเสร็จ',
                                icon: const Icon(Icons.visibility_outlined),
                                onPressed: () {
                                  final payload = job.parsedReceipt;
                                  if (payload == null) return;
                                  final doc = services.receiptRenderer.render(
                                    payload,
                                    fontSize: settings.receiptFontSize,
                                    lineSpacing: settings.receiptLineSpacing,
                                    marginMm: settings.receiptMarginMm,
                                  );
                                  showDialog<void>(
                                    context: context,
                                    builder:
                                        (_) =>
                                            ReceiptPreviewDialog(document: doc),
                                  );
                                },
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

  Widget _buildStatusChip(PrintJobStatus status) {
    Color bg;
    Color fg;
    switch (status) {
      case PrintJobStatus.submitted:
        bg = Colors.green.shade50;
        fg = Colors.green.shade800;
        break;
      case PrintJobStatus.failed:
        bg = Colors.red.shade50;
        fg = Colors.red.shade800;
        break;
      case PrintJobStatus.cancelled:
        bg = Colors.grey.shade200;
        fg = Colors.grey.shade800;
        break;
      default:
        bg = Colors.blue.shade50;
        fg = Colors.blue.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        status.thaiLabel,
        style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: fg),
      ),
    );
  }
}

class _StatusMetricCard extends StatelessWidget {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _StatusMetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: Colors.grey.shade300),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 13,
                      color: Colors.grey.shade700,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }
}
