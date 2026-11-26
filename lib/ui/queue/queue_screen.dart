import 'package:flutter/material.dart';
import '../../shared/models/print_job_model.dart';
import '../../shared/services/service_locator.dart';
import '../../shared/utilities/format_utils.dart';
import '../pairing/receipt_preview_dialog.dart';

/// Print Queue screen displaying active and recent jobs with safe retry,
/// cancellation, manual reprinting, and receipt preview.
class QueueScreen extends StatefulWidget {
  final AgentServiceContainer services;

  const QueueScreen({super.key, required this.services});

  @override
  State<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends State<QueueScreen> {
  PrintJobStatus? _selectedStatus;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.services.printQueueService,
        widget.services.printerManager,
      ]),
      builder: (context, _) {
        final jobs = widget.services.printQueueService.listJobs(
          statuses: _selectedStatus != null ? [_selectedStatus!] : null,
          limit: 150,
        );
        final settings = widget.services.configService.settings;

        return Padding(
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
                          'คิวงานพิมพ์ใบเสร็จ (Print Queue)',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'แต่ละเครื่องพิมพ์มีคิวแยกอิสระ เครื่องพิมพ์ที่ช้าจะไม่บล็อกเครื่องพิมพ์อื่น',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  DropdownButton<PrintJobStatus?>(
                    value: _selectedStatus,
                    hint: const Text('กรองตามสถานะ'),
                    items: [
                      const DropdownMenuItem<PrintJobStatus?>(
                        value: null,
                        child: Text('แสดงทุกสถานะ (All Statuses)'),
                      ),
                      ...PrintJobStatus.values.map(
                        (s) => DropdownMenuItem<PrintJobStatus?>(
                          value: s,
                          child: Text('${s.thaiLabel} (${s.value})'),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedStatus = v),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child:
                      jobs.isEmpty
                          ? const Center(
                            child: Text(
                              'ไม่มีรายการงานพิมพ์ในคิวตามเงื่อนไขที่เลือก',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                          : ListView.separated(
                            itemCount: jobs.length,
                            separatorBuilder:
                                (_, _) => const Divider(height: 1),
                            itemBuilder: (context, index) {
                              final job = jobs[index];
                              final printerName =
                                  widget.services.printerManager
                                      .getPrinterById(job.printerId)
                                      ?.name ??
                                  job.printerId;

                              return ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                leading: _buildStatusBadge(job.status),
                                title: Text(
                                  'เลขที่บิล: ${job.billNumber} • รหัสงาน: ${job.id}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 4),
                                    Text(
                                      'เครื่องพิมพ์: $printerName • ประเภท: ${FormatUtils.formatCopyTypeThai(job.copyType)} • ลองซ้ำ: ${job.retryCount} ครั้ง • เวลาสร้าง: ${FormatUtils.formatReceiptDateTime(job.createdAt.toIso8601String())}',
                                    ),
                                    if (job.errorMessage != null)
                                      Padding(
                                        padding: const EdgeInsets.only(top: 4),
                                        child: Text(
                                          'สาเหตุ: ${job.errorMessage}',
                                          style: TextStyle(
                                            color: Colors.red.shade700,
                                            fontWeight: FontWeight.w500,
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                                trailing: Wrap(
                                  spacing: 6,
                                  children: [
                                    IconButton(
                                      tooltip: 'ดูตัวอย่างใบเสร็จ',
                                      icon: const Icon(
                                        Icons.visibility_outlined,
                                      ),
                                      onPressed: () {
                                        final payload = job.parsedReceipt;
                                        if (payload == null) return;
                                        final doc = widget
                                            .services
                                            .receiptRenderer
                                            .render(
                                              payload,
                                              fontSize:
                                                  settings.receiptFontSize,
                                              lineSpacing:
                                                  settings.receiptLineSpacing,
                                              marginMm:
                                                  settings.receiptMarginMm,
                                            );
                                        showDialog<void>(
                                          context: context,
                                          builder:
                                              (_) => ReceiptPreviewDialog(
                                                document: doc,
                                              ),
                                        );
                                      },
                                    ),
                                    if (job.status.canRetry)
                                      OutlinedButton.icon(
                                        onPressed: () {
                                          try {
                                            widget.services.printQueueService
                                                .retryJob(job.id);
                                          } catch (e) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(content: Text('$e')),
                                            );
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.replay,
                                          size: 16,
                                        ),
                                        label: const Text('ลองพิมพ์ใหม่'),
                                      ),
                                    if (job.status.canCancel)
                                      TextButton.icon(
                                        onPressed: () {
                                          try {
                                            widget.services.printQueueService
                                                .cancelJob(job.id);
                                          } catch (e) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(content: Text('$e')),
                                            );
                                          }
                                        },
                                        icon: const Icon(
                                          Icons.cancel_outlined,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                        label: const Text(
                                          'ยกเลิก',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                                    if (job.status.canReprint)
                                      FilledButton.tonalIcon(
                                        onPressed: () {
                                          try {
                                            final reprinted = widget
                                                .services
                                                .printQueueService
                                                .reprintJob(job.id);
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(
                                                content: Text(
                                                  'สร้างงานพิมพ์ซ้ำรหัสใหม่ ${reprinted.id} (ไม่สร้างบิลขายใหม่)',
                                                ),
                                              ),
                                            );
                                          } catch (e) {
                                            ScaffoldMessenger.of(
                                              context,
                                            ).showSnackBar(
                                              SnackBar(content: Text('$e')),
                                            );
                                          }
                                        },
                                        icon: const Icon(Icons.copy, size: 16),
                                        label: const Text(
                                          'พิมพ์ซ้ำ (New Job ID)',
                                        ),
                                      ),
                                  ],
                                ),
                              );
                            },
                          ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatusBadge(PrintJobStatus status) {
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
        fg = Colors.grey.shade700;
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
