import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../shared/services/service_locator.dart';
import '../../shared/utilities/format_utils.dart';

/// POS Connection and Device Pairing screen in Thai.
/// Displays pending temporary pairing codes, authorized POS/Agent devices,
/// and supports credential creation and revocation.
class PairingScreen extends StatelessWidget {
  final AgentServiceContainer services;

  const PairingScreen({super.key, required this.services});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        services.pairingService,
        services.configService,
      ]),
      builder: (context, _) {
        final pendingSessions = services.pairingService.pendingSessions;
        final devices = services.pairingService.listDevices(
          includeRevoked: true,
        );
        final settings = services.configService.settings;

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
                          'การเชื่อมต่อ Web POS และการจับคู่อุปกรณ์ (POS Pairing & Security)',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'จัดการรหัสยืนยันการจับคู่ชั่วคราว (Temporary Pairing Code) และเพิกถอนสิทธิ์อุปกรณ์',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: () => _openCreateTokenDialog(context),
                    icon: const Icon(Icons.key_outlined, size: 18),
                    label: const Text('สร้าง Token เชื่อมต่อใหม่'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // Security Mode Banner
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child: SwitchListTile(
                  title: const Text(
                    'บังคับใช้การยืนยันตัวตนด้วย Bearer Token สำหรับทุกคำสั่งพิมพ์ (Require Pairing Auth)',
                    style: TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(
                    'Local HTTP API รับเฉพาะการเชื่อมต่อจาก ${services.localApiServer.bindAddress} และป้องกัน DNS Rebinding เสมอ',
                  ),
                  value: settings.requirePairingAuth,
                  onChanged: (val) {
                    services.configService.updateSettings(
                      settings.copyWith(requirePairingAuth: val),
                    );
                  },
                ),
              ),

              const SizedBox(height: 24),

              // Pending Pairing Requests
              const Text(
                'คำขอจับคู่ที่รอการยืนยัน (Pending Pairing Sessions)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              if (pendingSessions.isEmpty)
                Card(
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'ไม่มีคำขอจับคู่ที่รอการยืนยันในขณะนี้ (เมื่อ Web POS เรียก POST /api/pairing/start รหัส 6 หลักจะแสดงที่นี่)',
                      style: TextStyle(color: Colors.black54),
                    ),
                  ),
                )
              else
                ...pendingSessions.map(
                  (s) => Card(
                    elevation: 0,
                    color: Colors.amber.shade50,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: Colors.amber.shade400),
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.phonelink_lock,
                        color: Colors.amber,
                        size: 32,
                      ),
                      title: Text(
                        'อุปกรณ์: ${s.deviceName}  —  รหัสยืนยัน 6 หลัก: ${s.pairingCode}',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      subtitle: Text(
                        'สิทธิ์ที่ร้องขอ: ${s.requestedPermissions.join(", ")} • หมดอายุ: ${FormatUtils.formatReceiptDateTime(s.expiresAt.toIso8601String())}',
                      ),
                      trailing: Wrap(
                        spacing: 8,
                        children: [
                          OutlinedButton.icon(
                            onPressed: () {
                              Clipboard.setData(
                                ClipboardData(text: s.pairingCode),
                              );
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('คัดลอกรหัสยืนยัน 6 หลักแล้ว'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy, size: 16),
                            label: const Text('คัดลอกรหัส'),
                          ),
                          TextButton(
                            onPressed: () {
                              services.pairingService.rejectSessionInUi(
                                s.sessionId,
                              );
                            },
                            child: const Text(
                              'ปฏิเสธ',
                              style: TextStyle(color: Colors.red),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              const SizedBox(height: 24),

              // Paired Devices Table
              const Text(
                'อุปกรณ์ที่จับคู่แล้ว (Paired POS & Remote Agent Devices)',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Card(
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: Colors.grey.shade300),
                ),
                child:
                    devices.isEmpty
                        ? const Padding(
                          padding: EdgeInsets.all(24),
                          child: Center(
                            child: Text(
                              'ยังไม่มีอุปกรณ์ที่จับคู่ในระบบ',
                              style: TextStyle(color: Colors.black54),
                            ),
                          ),
                        )
                        : ListView.separated(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: devices.length,
                          separatorBuilder: (_, _) => const Divider(height: 1),
                          itemBuilder: (context, idx) {
                            final dev = devices[idx];
                            return ListTile(
                              leading: Icon(
                                dev.isRevoked
                                    ? Icons.block
                                    : Icons.verified_user,
                                color:
                                    dev.isRevoked ? Colors.red : Colors.green,
                              ),
                              title: Text(
                                '${dev.deviceName} ${dev.isRevoked ? "(เพิกถอนแล้ว)" : "(ใช้งานอยู่)"}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              subtitle: Text(
                                'รหัสอุปกรณ์: ${dev.id}\nสิทธิ์: ${dev.permissions.join(", ")} • ใช้งานล่าสุด: ${FormatUtils.formatReceiptDateTime(dev.lastSeenAt.toIso8601String())}',
                              ),
                              isThreeLine: true,
                              trailing:
                                  dev.isRevoked
                                      ? const Text(
                                        'เพิกถอนแล้ว',
                                        style: TextStyle(color: Colors.red),
                                      )
                                      : OutlinedButton.icon(
                                        onPressed: () {
                                          services.pairingService.revoke(
                                            deviceId: dev.id,
                                          );
                                        },
                                        icon: const Icon(
                                          Icons.link_off,
                                          size: 16,
                                          color: Colors.red,
                                        ),
                                        label: const Text(
                                          'เพิกถอนสิทธิ์ (Revoke)',
                                          style: TextStyle(color: Colors.red),
                                        ),
                                      ),
                            );
                          },
                        ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _openCreateTokenDialog(BuildContext context) async {
    final nameCtrl = TextEditingController(text: 'Web POS Terminal 1');
    final created = await showDialog<String>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text(
            'สร้าง Token สำหรับเชื่อมต่อ POS หรือ Agent ลูกข่าย',
          ),
          content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(
              labelText:
                  'ชื่ออุปกรณ์ (เช่น เครื่องแคชเชียร์ 1, Agent เครื่องที่ 2)',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameCtrl.text.trim();
                if (name.isEmpty) return;
                final res = services.pairingService.createDeviceDirectlyFromUi(
                  deviceName: name,
                );
                Navigator.of(ctx).pop(res.plainTextToken);
              },
              child: const Text('สร้าง Token'),
            ),
          ],
        );
      },
    );

    if (created != null && context.mounted) {
      await showDialog<void>(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('สร้างรหัสรับรองสิทธิ์ (Bearer Token) สำเร็จ'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'โปรดคัดลอก Token นี้เก็บไว้ในระบบตั้งค่าของ Web POS หรือ Agent ลูกข่าย (ระบบจะเก็บเฉพาะค่า Hash และจะไม่แสดงรหัสเต็มอีก):',
                  style: TextStyle(fontSize: 13),
                ),
                const SizedBox(height: 12),
                SelectableText(
                  created,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            actions: [
              OutlinedButton.icon(
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: created));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('คัดลอก Token แล้ว')),
                  );
                },
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('คัดลอก Token'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('เสร็จสิ้น'),
              ),
            ],
          );
        },
      );
    }
  }
}
