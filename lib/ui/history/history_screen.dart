import 'package:flutter/material.dart';
import '../../shared/models/print_job_model.dart';
import '../../shared/services/service_locator.dart';
import '../../shared/utilities/format_utils.dart';
import '../pairing/receipt_preview_dialog.dart';

/// Print History screen with search by bill number/job ID and multi-criteria filtering.
class HistoryScreen extends StatefulWidget {
  final AgentServiceContainer services;

  const HistoryScreen({super.key, required this.services});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final _searchCtrl = TextEditingController();
  String? _selectedPrinterId;
  PrintJobStatus? _selectedStatus;
  String? _selectedCopyType;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.services.printQueueService,
        widget.services.printerManager,
      ]),
      builder: (context, _) {
        final printers = widget.services.printerManager.listPrinters();
        final jobs = widget.services.printHistoryService.queryHistory(
          searchQuery: _searchCtrl.text,
          printerId: _selectedPrinterId,
          status: _selectedStatus,
          copyType: _selectedCopyType,
          limit: 300,
        );
        final settings = widget.services.configService.settings;

        return Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'ประวัติการพิมพ์ใบเสร็จ (Print History)',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 4),
              const Text(
                'ค้นหาประวัติการพิมพ์ย้อนหลังตามเลขที่บิล เครื่องพิมพ์ สถานะ หรือประเภทสำเนา',
                style: TextStyle(fontSize: 13, color: Colors.black54),
              ),
              const SizedBox(height: 16),

              // Search & Filter Bar
              Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 280,
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: InputDecoration(
                        prefixIcon: const Icon(Icons.search),
                        labelText: 'ค้นหาเลขที่บิล / รหัสงานพิมพ์',
                        border: const OutlineInputBorder(),
                        isDense: true,
                        suffixIcon:
                            _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() {});
                                  },
                                )
                                : null,
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  DropdownButton<String?>(
                    value:
                        printers.any((p) => p.id == _selectedPrinterId)
                            ? _selectedPrinterId
                            : null,
                    hint: const Text('ทุกเครื่องพิมพ์'),
                    items: [
                      const DropdownMenuItem<String?>(
                        value: null,
                        child: Text('ทุกเครื่องพิมพ์ (All Printers)'),
                      ),
                      ...printers.map(
                        (p) => DropdownMenuItem<String?>(
                          value: p.id,
                          child: Text(p.name),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedPrinterId = v),
                  ),
                  DropdownButton<PrintJobStatus?>(
                    value: _selectedStatus,
                    hint: const Text('ทุกสถานะ'),
                    items: [
                      const DropdownMenuItem<PrintJobStatus?>(
                        value: null,
                        child: Text('ทุกสถานะ (All Statuses)'),
                      ),
                      ...PrintJobStatus.values.map(
                        (s) => DropdownMenuItem<PrintJobStatus?>(
                          value: s,
                          child: Text(s.thaiLabel),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedStatus = v),
                  ),
                  DropdownButton<String?>(
                    value: _selectedCopyType,
                    hint: const Text('ทุกประเภทสำเนา'),
                    items: const [
                      DropdownMenuItem<String?>(
                        value: null,
                        child: Text('ทุกประเภทสำเนา (All Copy Types)'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'original',
                        child: Text('ต้นฉบับ (Original)'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'copy',
                        child: Text('สำเนา (Copy)'),
                      ),
                      DropdownMenuItem<String?>(
                        value: 'reprint',
                        child: Text('พิมพ์ซ้ำ (Reprint)'),
                      ),
                    ],
                    onChanged: (v) => setState(() => _selectedCopyType = v),
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
                              'ไม่พบประวัติการพิมพ์ที่ตรงกับเงื่อนไขการค้นหา',
                              style: TextStyle(color: Colors.black54),
                            ),
                          )
                          : ListView.separated(
                            itemCount: jobs.length,
                            separatorBuilder:
                                (_, _) => const Divider(height: 1),
                            itemBuilder: (context, idx) {
                              final job = jobs[idx];
                              final printerName =
                                  widget.services.printerManager
                                      .getPrinterById(job.printerId)
                                      ?.name ??
                                  job.printerId;

                              return ListTile(
                                title: Text(
                                  'เลขที่บิล: ${job.billNumber} (${FormatUtils.formatCopyTypeThai(job.copyType)})',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                subtitle: Text(
                                  'เครื่องพิมพ์: $printerName • วันที่พิมพ์: ${FormatUtils.formatReceiptDateTime(job.createdAt.toIso8601String())} • สถานะ: ${job.status.thaiLabel}'
                                  '${job.errorMessage != null ? "\nข้อผิดพลาด: ${job.errorMessage}" : ""}',
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      tooltip: 'ดูใบเสร็จ',
                                      icon: const Icon(
                                        Icons.receipt_long_outlined,
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
                                    if (job.status.canReprint)
                                      TextButton.icon(
                                        onPressed: () {
                                          final reprinted = widget
                                              .services
                                              .printQueueService
                                              .reprintJob(job.id);
                                          ScaffoldMessenger.of(
                                            context,
                                          ).showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                'ส่งพิมพ์ซ้ำด้วยรหัสงานใหม่: ${reprinted.id}',
                                              ),
                                            ),
                                          );
                                        },
                                        icon: const Icon(Icons.print, size: 16),
                                        label: const Text('พิมพ์ซ้ำ'),
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
}
