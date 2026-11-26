import 'package:flutter/material.dart';
import '../shared/constants/app_constants.dart';
import '../shared/services/service_locator.dart';
import 'dashboard/dashboard_screen.dart';
import 'history/history_screen.dart';
import 'pairing/pairing_screen.dart';
import 'printers/printers_screen.dart';
import 'queue/queue_screen.dart';
import 'settings/settings_screen.dart';

/// Main Desktop User Interface Shell with Thai-language navigation rail,
/// live API status bar, background tray minimization, and safe shutdown.
class AppShell extends StatefulWidget {
  final AgentServiceContainer services;

  const AppShell({super.key, required this.services});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final screens = <Widget>[
      DashboardScreen(
        services: widget.services,
        onNavigateTab: (index) => setState(() => _selectedIndex = index),
      ),
      PrintersScreen(services: widget.services),
      QueueScreen(services: widget.services),
      HistoryScreen(services: widget.services),
      PairingScreen(services: widget.services),
      SettingsScreen(services: widget.services),
    ];

    return Scaffold(
      backgroundColor: Colors.grey.shade50,
      body: Row(
        children: [
          // Left Desktop Sidebar
          Container(
            width: 245,
            decoration: BoxDecoration(
              border: Border(right: BorderSide(color: Colors.grey.shade300)),
            ),
            child: Material(
              color: Colors.white,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Brand Header
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.indigo.shade600,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.print_rounded,
                            color: Colors.white,
                            size: 24,
                          ),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                AppConstants.appName,
                                style: TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                'บริการพิมพ์ใบเสร็จ POS',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.black54,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 12,
                      ),
                      children: [
                        _buildNavItem(
                          0,
                          Icons.dashboard_outlined,
                          'แดชบอร์ด (Dashboard)',
                        ),
                        _buildNavItem(
                          1,
                          Icons.print_outlined,
                          'เครื่องพิมพ์ (Printers)',
                        ),
                        _buildNavItem(
                          2,
                          Icons.queue_play_next,
                          'คิวงานพิมพ์ (Print Queue)',
                        ),
                        _buildNavItem(
                          3,
                          Icons.history,
                          'ประวัติการพิมพ์ (History)',
                        ),
                        _buildNavItem(
                          4,
                          Icons.phonelink_setup,
                          'การเชื่อมต่อ POS (Pairing)',
                        ),
                        _buildNavItem(
                          5,
                          Icons.settings_outlined,
                          'ตั้งค่าระบบ (Settings)',
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1),
                  // Bottom Tray & Safe Exit Actions
                  Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        ListenableBuilder(
                          listenable: widget.services.localApiServer,
                          builder: (context, _) {
                            final running =
                                widget.services.localApiServer.isRunning;
                            return Row(
                              children: [
                                Icon(
                                  Icons.circle,
                                  size: 10,
                                  color: running ? Colors.green : Colors.red,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    running
                                        ? widget
                                            .services
                                            .localApiServer
                                            .bindAddress
                                        : 'API หยุดทำงาน',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 10),
                        OutlinedButton.icon(
                          onPressed: () {
                            widget.services.systemTrayService.hideToTray();
                          },
                          icon: const Icon(Icons.minimize, size: 16),
                          label: const Text(
                            'ย่อลงถาดระบบ (Background)',
                            style: TextStyle(fontSize: 12),
                          ),
                        ),
                        const SizedBox(height: 6),
                        TextButton.icon(
                          onPressed: () => _confirmAndExitSafely(context),
                          icon: const Icon(
                            Icons.power_settings_new,
                            size: 16,
                            color: Colors.red,
                          ),
                          label: const Text(
                            'ปิดโปรแกรม (Quit Agent)',
                            style: TextStyle(fontSize: 12, color: Colors.red),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Active Screen Content
          Expanded(child: screens[_selectedIndex]),
        ],
      ),
    );
  }

  Widget _buildNavItem(int index, IconData icon, String label) {
    final selected = _selectedIndex == index;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: ListTile(
        dense: true,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        selected: selected,
        selectedTileColor: Colors.indigo.shade50,
        selectedColor: Colors.indigo.shade800,
        leading: Icon(icon, size: 20),
        title: Text(
          label,
          style: TextStyle(
            fontWeight: selected ? FontWeight.bold : FontWeight.w500,
            fontSize: 13.5,
          ),
        ),
        onTap: () => setState(() => _selectedIndex = index),
      ),
    );
  }

  Future<void> _confirmAndExitSafely(BuildContext context) async {
    final hasActive = widget.services.printQueueService.hasActivePrintingJobs;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          title: const Text('ยืนยันการปิดโปรแกรม POS Print Agent'),
          content: Text(
            hasActive
                ? 'ขณะนี้มีงานพิมพ์กำลังประมวลผลอยู่ ระบบจะรอให้งานปัจจุบันส่งพิมพ์เสร็จก่อนปิดโปรแกรมเพื่อป้องกันใบเสร็จขาดหาย'
                : 'เมื่อปิดโปรแกรม ระบบ Web POS จะไม่สามารถส่งคำสั่งพิมพ์มายังเครื่องนี้ได้จนกว่าจะเปิดโปรแกรมอีกครั้ง (หากต้องการทำงานเบื้องหลัง แนะนำให้กด "ย่อลงถาดระบบ")',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('ยกเลิก'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('ยืนยันปิดโปรแกรม'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await widget.services.systemTrayService.requestSafeExit();
    }
  }
}
