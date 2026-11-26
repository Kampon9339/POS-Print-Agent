import 'package:flutter/material.dart';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/printer_model.dart';

/// Dialog for adding or editing a USB, LAN, Wi-Fi, or OS Printer.
class PrinterFormDialog extends StatefulWidget {
  final PrinterModel? existing;
  final List<PrinterModel> allPrinters;

  const PrinterFormDialog({
    super.key,
    this.existing,
    this.allPrinters = const [],
  });

  @override
  State<PrinterFormDialog> createState() => _PrinterFormDialogState();
}

class _PrinterFormDialogState extends State<PrinterFormDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameCtrl;
  late TextEditingController _hostCtrl;
  late TextEditingController _portCtrl;
  late TextEditingController _osDriverCtrl;
  late TextEditingController _marginCtrl;

  late PrinterConnectionType _connectionType;
  late PrinterProtocol _protocol;
  late int _paperWidth;
  late bool _isDefault;
  late bool _enabled;
  late bool _autoCut;
  late bool _useRaster;
  String? _backupPrinterId;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameCtrl = TextEditingController(text: e?.name ?? '');
    _hostCtrl = TextEditingController(text: e?.host ?? '');
    _portCtrl = TextEditingController(
      text: (e?.port ?? AppConstants.defaultRawTcpPort).toString(),
    );
    _osDriverCtrl = TextEditingController(
      text: e?.configuration.osDriverName ?? '',
    );
    _marginCtrl = TextEditingController(
      text: (e?.configuration.marginMm ?? 4.0).toString(),
    );

    _connectionType = e?.connectionType ?? PrinterConnectionType.lan;
    _protocol = e?.protocol ?? PrinterProtocol.rawTcp;
    _paperWidth = e?.paperWidth ?? 80;
    _isDefault = e?.isDefault ?? false;
    _enabled = e?.enabled ?? true;
    _autoCut = e?.configuration.autoCut ?? true;
    _useRaster = e?.configuration.useRasterForEscPos ?? true;
    _backupPrinterId = e?.configuration.backupPrinterId;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _hostCtrl.dispose();
    _portCtrl.dispose();
    _osDriverCtrl.dispose();
    _marginCtrl.dispose();
    super.dispose();
  }

  bool get _isNetworkPrinter =>
      _connectionType == PrinterConnectionType.lan ||
      _connectionType == PrinterConnectionType.wifi;

  @override
  Widget build(BuildContext context) {
    final backupCandidates =
        widget.allPrinters.where((p) => p.id != widget.existing?.id).toList();

    return AlertDialog(
      title: Text(
        widget.existing == null
            ? 'เพิ่มเครื่องพิมพ์ใหม่ (Add Printer)'
            : 'แก้ไขการตั้งค่าเครื่องพิมพ์ (${widget.existing!.name})',
      ),
      content: SizedBox(
        width: 600,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8, bottom: 4),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameCtrl,
                  decoration: const InputDecoration(
                    labelText:
                        'ชื่อเครื่องพิมพ์ (เช่น เครื่องพิมพ์แคชเชียร์ 1, เครื่องพิมพ์ครัว)',
                    border: OutlineInputBorder(),
                  ),
                  validator:
                      (v) =>
                          v == null || v.trim().isEmpty
                              ? 'กรุณาระบุชื่อเครื่องพิมพ์'
                              : null,
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PrinterConnectionType>(
                  isExpanded: true,
                  initialValue: _connectionType,
                  decoration: const InputDecoration(
                    labelText: 'ประเภทการเชื่อมต่อ (Connection Type)',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      PrinterConnectionType.values
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
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _connectionType = val;
                      if (_isNetworkPrinter &&
                          _protocol == PrinterProtocol.osDriver) {
                        _protocol = PrinterProtocol.rawTcp;
                      } else if (!_isNetworkPrinter &&
                          _protocol == PrinterProtocol.rawTcp) {
                        _protocol = PrinterProtocol.osDriver;
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<PrinterProtocol>(
                  isExpanded: true,
                  initialValue: _protocol,
                  decoration: const InputDecoration(
                    labelText: 'โปรโตคอลการพิมพ์ (Protocol)',
                    border: OutlineInputBorder(),
                  ),
                  items:
                      PrinterProtocol.values
                          .map(
                            (p) => DropdownMenuItem(
                              value: p,
                              child: Text(
                                p.label,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    if (val == null) return;
                    setState(() {
                      _protocol = val;
                      if (val == PrinterProtocol.rawTcp) {
                        _portCtrl.text =
                            AppConstants.defaultRawTcpPort.toString();
                      } else if (val == PrinterProtocol.ipp) {
                        _portCtrl.text = AppConstants.defaultIppPort.toString();
                      } else if (val == PrinterProtocol.lpr) {
                        _portCtrl.text = AppConstants.defaultLprPort.toString();
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (_isNetworkPrinter)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: TextFormField(
                          controller: _hostCtrl,
                          decoration: const InputDecoration(
                            labelText:
                                'IP Address / Hostname (เช่น 192.168.1.200)',
                            border: OutlineInputBorder(),
                          ),
                          validator: (v) {
                            if (_isNetworkPrinter &&
                                (v == null || v.trim().isEmpty)) {
                              return 'กรุณาระบุ IP Address ของเครื่องพิมพ์เครือข่าย';
                            }
                            return null;
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        flex: 1,
                        child: TextFormField(
                          controller: _portCtrl,
                          keyboardType: TextInputType.number,
                          decoration: const InputDecoration(
                            labelText: 'Port',
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                    ],
                  )
                else
                  TextFormField(
                    controller: _osDriverCtrl,
                    decoration: const InputDecoration(
                      labelText:
                          'ชื่อเครื่องพิมพ์ในระบบปฏิบัติการ / พอร์ต USB (เว้นว่างเพื่อใช้ชื่อเดียวกับด้านบน)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: _paperWidth,
                        decoration: const InputDecoration(
                          labelText: 'ขนาดหน้ากระดาษ (Paper Width)',
                          border: OutlineInputBorder(),
                        ),
                        items: const [
                          DropdownMenuItem(
                            value: 80,
                            child: Text(
                              '80 มม. (พื้นที่พิมพ์จริง ~72 มม.)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 58,
                            child: Text(
                              '58 มม. (พื้นที่พิมพ์จริง ~48 มม.)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          DropdownMenuItem(
                            value: 210,
                            child: Text(
                              'A4 (210 × 297 มม. — ใบกำกับภาษี / รายงาน)',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              _paperWidth = v;
                              if (v == 210) {
                                _marginCtrl.text = '10.0';
                                _autoCut = false;
                              }
                            });
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: TextFormField(
                        controller: _marginCtrl,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'ระยะขอบซ้าย/ขวา (มม.)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String?>(
                  isExpanded: true,
                  initialValue:
                      backupCandidates.any((p) => p.id == _backupPrinterId)
                          ? _backupPrinterId
                          : null,
                  decoration: const InputDecoration(
                    labelText:
                        'เครื่องพิมพ์สำรองกรณีเครื่องหลักออฟไลน์ (Backup Printer)',
                    border: OutlineInputBorder(),
                  ),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text(
                        '— ไม่กำหนดเครื่องพิมพ์สำรอง —',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...backupCandidates.map(
                      (p) => DropdownMenuItem<String?>(
                        value: p.id,
                        child: Text(
                          '${p.name} (${p.connectionType.value})',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                  onChanged: (v) => setState(() => _backupPrinterId = v),
                ),
                const SizedBox(height: 10),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'ตั้งเป็นเครื่องพิมพ์ค่าเริ่มต้น (Default Printer)',
                  ),
                  value: _isDefault,
                  onChanged: (v) => setState(() => _isDefault = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('เปิดใช้งานเครื่องพิมพ์นี้ (Enabled)'),
                  value: _enabled,
                  onChanged: (v) => setState(() => _enabled = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'พิมพ์ภาษาไทยแบบภาพบิตแมป (Raster GS v 0 — แนะนำสำหรับ ESC/POS)',
                  ),
                  subtitle: const Text(
                    'ป้องกันปัญหาสระลอยและวรรณยุกต์เพี้ยนบนเครื่องพิมพ์ความร้อน',
                    style: TextStyle(fontSize: 12),
                  ),
                  value: _useRaster,
                  onChanged: (v) => setState(() => _useRaster = v),
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'ตัดกระดาษอัตโนมัติหลังพิมพ์เสร็จ (Auto Cut)',
                  ),
                  value: _autoCut,
                  onChanged: (v) => setState(() => _autoCut = v),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ยกเลิก'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('บันทึกข้อมูลเครื่องพิมพ์'),
        ),
      ],
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    final port = int.tryParse(_portCtrl.text.trim()) ?? 9100;
    final margin = double.tryParse(_marginCtrl.text.trim()) ?? 4.0;
    final osDriver = _osDriverCtrl.text.trim();

    final config = (widget.existing?.configuration ??
            const PrinterConfiguration())
        .copyWith(
          osDriverName: osDriver.isEmpty ? null : osDriver,
          marginMm: margin.clamp(0.0, 12.0),
          autoCut: _autoCut,
          useRasterForEscPos: _useRaster,
          backupPrinterId: _backupPrinterId,
        );

    final result = <String, dynamic>{
      'name': _nameCtrl.text.trim(),
      'connectionType': _connectionType,
      'protocol': _protocol,
      'host': _isNetworkPrinter ? _hostCtrl.text.trim() : null,
      'port': _isNetworkPrinter ? port : null,
      'paperWidth': _paperWidth,
      'isDefault': _isDefault,
      'enabled': _enabled,
      'configuration': config,
    };
    Navigator.of(context).pop(result);
  }
}
