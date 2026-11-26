import 'package:flutter/material.dart';
import '../../shared/models/app_settings_model.dart';
import '../../shared/services/service_locator.dart';

/// Settings screen in Thai covering Agent startup, Local API port,
/// Receipt rendering, Shared LAN Mode A / Mode B Coordinator, and DB backup.
class SettingsScreen extends StatefulWidget {
  final AgentServiceContainer services;

  const SettingsScreen({super.key, required this.services});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late TextEditingController _apiPortCtrl;
  late TextEditingController _originsCtrl;
  late TextEditingController _fontSizeCtrl;
  late TextEditingController _lineSpacingCtrl;
  late TextEditingController _marginCtrl;
  late TextEditingController _headerNoteCtrl;
  late TextEditingController _footerNoteCtrl;
  late TextEditingController _retentionCtrl;
  late TextEditingController _coordBindHostCtrl;
  late TextEditingController _coordPortCtrl;
  late TextEditingController _remoteCoordUrlCtrl;
  late TextEditingController _remoteCoordTokenCtrl;
  late TextEditingController _subnetCtrl;

  late int _defaultPaperWidth;
  late bool _autoStart;
  late bool _minimizeToTray;
  late LanOperatingMode _lanMode;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  void _loadCurrentSettings() {
    final s = widget.services.configService.settings;
    _apiPortCtrl = TextEditingController(text: s.localApiPort.toString());
    _originsCtrl = TextEditingController(text: s.allowedOrigins.join(', '));
    _fontSizeCtrl = TextEditingController(text: s.receiptFontSize.toString());
    _lineSpacingCtrl = TextEditingController(
      text: s.receiptLineSpacing.toString(),
    );
    _marginCtrl = TextEditingController(text: s.receiptMarginMm.toString());
    _headerNoteCtrl = TextEditingController(text: s.customHeaderNote);
    _footerNoteCtrl = TextEditingController(text: s.customFooterNote);
    _retentionCtrl = TextEditingController(text: s.retentionDays.toString());
    _coordBindHostCtrl = TextEditingController(text: s.coordinatorBindHost);
    _coordPortCtrl = TextEditingController(text: s.coordinatorPort.toString());
    _remoteCoordUrlCtrl = TextEditingController(text: s.remoteCoordinatorUrl);
    _remoteCoordTokenCtrl = TextEditingController(
      text: s.remoteCoordinatorToken,
    );
    _subnetCtrl = TextEditingController(text: s.discoverySubnetPrefix);

    _defaultPaperWidth = s.defaultPaperWidth;
    _autoStart = s.autoStartOnLogin;
    _minimizeToTray = s.minimizeToTrayOnClose;
    _lanMode = s.lanOperatingMode;
  }

  @override
  void dispose() {
    _apiPortCtrl.dispose();
    _originsCtrl.dispose();
    _fontSizeCtrl.dispose();
    _lineSpacingCtrl.dispose();
    _marginCtrl.dispose();
    _headerNoteCtrl.dispose();
    _footerNoteCtrl.dispose();
    _retentionCtrl.dispose();
    _coordBindHostCtrl.dispose();
    _coordPortCtrl.dispose();
    _remoteCoordUrlCtrl.dispose();
    _remoteCoordTokenCtrl.dispose();
    _subnetCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.services.configService,
        widget.services.localApiServer,
        widget.services.coordinatorServer,
      ]),
      builder: (context, _) {
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
                          'ตั้งค่าระบบและรูปแบบใบเสร็จ (Application & Receipt Settings)',
                          style: TextStyle(
                            fontSize: 22,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 4),
                        Text(
                          'กำหนดค่าการเริ่มทำงานอัตโนมัติ ขนาดตัวอักษร โหมดแชร์เครื่องพิมพ์ LAN และการสำรองฐานข้อมูล',
                          style: TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.icon(
                    onPressed: _saveAllSettings,
                    icon: const Icon(Icons.save_outlined, size: 18),
                    label: const Text('บันทึกการตั้งค่าทั้งหมด'),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 1. Receipt Rendering Settings
              _buildSectionCard(
                title:
                    '1. ตั้งค่ารูปแบบใบเสร็จภาษาไทย (Thai Receipt Rendering)',
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          initialValue: _defaultPaperWidth,
                          decoration: const InputDecoration(
                            labelText: 'ขนาดหน้ากระดาษเริ่มต้น',
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 80,
                              child: Text('80 มม. (พื้นที่พิมพ์จริง 72 มม.)'),
                            ),
                            DropdownMenuItem(
                              value: 58,
                              child: Text('58 มม. (พื้นที่พิมพ์จริง 48 มม.)'),
                            ),
                            DropdownMenuItem(
                              value: 210,
                              child: Text(
                                'A4 (210 × 297 มม. — ใบกำกับภาษี / รายงาน)',
                              ),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _defaultPaperWidth = v);
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _fontSizeCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ขนาดตัวอักษร (Font Size pt)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _lineSpacingCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ระยะห่างบรรทัด (Line Spacing)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _marginCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'ระยะขอบซ้าย/ขวา (Margin มม.)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _headerNoteCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'ข้อความส่วนหัวเพิ่มเติม (Custom Header)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _footerNoteCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'ข้อความส่วนท้ายเพิ่มเติม (Custom Footer)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 2. Shared LAN Printer Mode (Mode A vs Mode B)
              _buildSectionCard(
                title:
                    '2. สถาปัตยกรรมเครื่องพิมพ์ LAN ที่ใช้ร่วมกันหลายเครื่อง (Shared LAN Printer Mode)',
                children: [
                  DropdownButtonFormField<LanOperatingMode>(
                    isExpanded: true,
                    initialValue: _lanMode,
                    decoration: const InputDecoration(
                      labelText:
                          'โหมดการทำงานของเครื่องพิมพ์เครือข่าย (Mode A / Mode B)',
                      border: OutlineInputBorder(),
                    ),
                    items:
                        LanOperatingMode.values
                            .map(
                              (m) => DropdownMenuItem(
                                value: m,
                                child: Text(m.thaiLabel),
                              ),
                            )
                            .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _lanMode = v);
                    },
                  ),
                  const SizedBox(height: 12),
                  if (_lanMode == LanOperatingMode.direct)
                    const Text(
                      'คำอธิบาย โหมด A: คอมพิวเตอร์แต่ละเครื่องส่งคำสั่งพิมพ์ไปยังเครื่องพิมพ์ LAN โดยตรง (แต่ละเครื่องมีคิวของตัวเอง ไม่รับประกันลำดับงานข้ามเครื่อง)',
                      style: TextStyle(fontSize: 12.5, color: Colors.black54),
                    )
                  else if (_lanMode == LanOperatingMode.coordinatorClient) ...[
                    const Text(
                      'คำอธิบาย โหมด B (ลูกข่าย): ส่งคำสั่งพิมพ์ของเครื่องพิมพ์ LAN ไปเข้าคิวกลางที่เครื่องแม่ข่าย (Central Coordinator) เพื่อป้องกันการแย่งพิมพ์ชนกัน',
                      style: TextStyle(fontSize: 12.5, color: Colors.black54),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _remoteCoordUrlCtrl,
                            decoration: const InputDecoration(
                              labelText:
                                  'URL ของ Central Coordinator (เช่น http://192.168.1.100:8766)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _remoteCoordTokenCtrl,
                            decoration: const InputDecoration(
                              labelText:
                                  'Bearer Token ที่ออกโดยเครื่องแม่ข่าย Coordinator',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ] else if (_lanMode == LanOperatingMode.coordinatorHost) ...[
                    Text(
                      'คำอธิบาย โหมด B (แม่ข่าย): เครื่องนี้ทำหน้าที่เป็นศูนย์กลางคิวพิมพ์ (Central Coordinator) สถานะปัจจุบัน: '
                      '${widget.services.coordinatorServer.isRunning ? "กำลังทำงานที่ ${widget.services.coordinatorServer.boundHost}:${widget.services.coordinatorServer.boundPort}" : "หยุดทำงาน"}',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _coordBindHostCtrl,
                            decoration: const InputDecoration(
                              labelText:
                                  'LAN IP ที่เปิดรับการเชื่อมต่อ (แนะนำระบุ IP ภายในวง LAN เช่น 192.168.1.100)',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        SizedBox(
                          width: 160,
                          child: TextField(
                            controller: _coordPortCtrl,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(
                              labelText: 'Coordinator Port',
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 20),

              // 3. Startup, System Tray & Local API
              _buildSectionCard(
                title:
                    '3. การทำงานเบื้องหลัง ถาดระบบ (System Tray) และ Local HTTP API',
                children: [
                  Row(
                    children: [
                      SizedBox(
                        width: 200,
                        child: TextField(
                          controller: _apiPortCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Local API Port (127.0.0.1)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _subnetCtrl,
                          decoration: const InputDecoration(
                            labelText: 'ค่าเริ่มต้นวง LAN (Subnet 3 ชุดแรก)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _originsCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'Allowed POS Origins (คั่นด้วยเครื่องหมายจุลภาค)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'เปิดโปรแกรมอัตโนมัติเมื่อเข้าสู่ระบบ Windows / macOS (Start on Login)',
                    ),
                    value: _autoStart,
                    onChanged: (v) => setState(() => _autoStart = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text(
                      'ย่อลงถาดระบบ (System Tray / Menu Bar) เมื่อปิดหน้าต่างหลัก โดยให้ Local API ทำงานต่อเบื้องหลัง',
                    ),
                    value: _minimizeToTray,
                    onChanged: (v) => setState(() => _minimizeToTray = v),
                  ),
                ],
              ),
              const SizedBox(height: 20),

              // 4. Database Retention & Backup
              _buildSectionCard(
                title:
                    '4. การเก็บรักษาประวัติและการสำรองฐานข้อมูล (SQLite Backup & Retention)',
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 280,
                        child: TextField(
                          controller: _retentionCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText:
                                'จำนวนวันเก็บประวัติงานพิมพ์ที่เสร็จสิ้นแล้ว (วัน)',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          final days =
                              int.tryParse(_retentionCtrl.text.trim()) ?? 30;
                          final purged = widget.services.backupService
                              .applyRetentionPolicy(retentionDays: days);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'ล้างประวัติงานที่เสร็จสิ้นเกินกำหนดแล้ว $purged รายการ (ไม่ลบงานค้างหรือล้มเหลว)',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.cleaning_services_outlined),
                        label: const Text('ทำความสะอาดข้อมูลเก่าทันที'),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: () async {
                          final backupPath = await widget.services.backupService
                              .createBackup(widget.services.dataDirectoryPath);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'สำรองฐานข้อมูล SQLite สำเร็จที่: $backupPath',
                              ),
                            ),
                          );
                        },
                        icon: const Icon(Icons.backup_outlined),
                        label: const Text('สำรองฐานข้อมูล SQLite (Backup)'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSectionCard({
    required String title,
    required List<Widget> children,
  }) {
    return Card(
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
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const Divider(height: 24),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _saveAllSettings() async {
    final current = widget.services.configService.settings;
    final newPort =
        int.tryParse(_apiPortCtrl.text.trim()) ?? current.localApiPort;
    final origins =
        _originsCtrl.text
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();

    final updated = current.copyWith(
      localApiPort: newPort.clamp(1024, 65535),
      allowedOrigins: origins,
      defaultPaperWidth: _defaultPaperWidth,
      receiptFontSize: (double.tryParse(_fontSizeCtrl.text.trim()) ?? 14.0)
          .clamp(9.0, 24.0),
      receiptLineSpacing: (double.tryParse(_lineSpacingCtrl.text.trim()) ??
              1.25)
          .clamp(1.0, 2.5),
      receiptMarginMm: (double.tryParse(_marginCtrl.text.trim()) ?? 4.0).clamp(
        0.0,
        15.0,
      ),
      customHeaderNote: _headerNoteCtrl.text.trim(),
      customFooterNote: _footerNoteCtrl.text.trim(),
      autoStartOnLogin: _autoStart,
      minimizeToTrayOnClose: _minimizeToTray,
      retentionDays: (int.tryParse(_retentionCtrl.text.trim()) ?? 30).clamp(
        1,
        3650,
      ),
      lanOperatingMode: _lanMode,
      coordinatorBindHost: _coordBindHostCtrl.text.trim(),
      coordinatorPort: (int.tryParse(_coordPortCtrl.text.trim()) ?? 8766).clamp(
        1024,
        65535,
      ),
      remoteCoordinatorUrl: _remoteCoordUrlCtrl.text.trim(),
      remoteCoordinatorToken: _remoteCoordTokenCtrl.text.trim(),
      discoverySubnetPrefix: _subnetCtrl.text.trim(),
    );

    widget.services.configService.updateSettings(updated);
    await widget.services.autoStartService.setAutoStart(_autoStart);

    if (newPort != widget.services.localApiServer.boundPort) {
      await widget.services.localApiServer.start(port: updated.localApiPort);
    }

    if (updated.lanOperatingMode == LanOperatingMode.coordinatorHost) {
      await widget.services.coordinatorServer.start(
        host: updated.coordinatorBindHost,
        port: updated.coordinatorPort,
      );
    } else {
      await widget.services.coordinatorServer.stop();
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('บันทึกการตั้งค่าทั้งหมดเรียบร้อยแล้ว')),
    );
  }
}
