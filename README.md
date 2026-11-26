# POS Print Agent (Flutter Desktop — Windows & macOS)

**POS Print Agent** is a standalone, production-ready desktop printing service built with Flutter Desktop and Dart for **Windows** and **macOS**. It connects an existing Web-based POS application to local **USB**, **LAN**, **Wi-Fi**, and **OS-installed** receipt printers via a secure Local HTTP API (`http://127.0.0.1:8765`).

> **Important Architecture Boundaries**
> - Receives **structured JSON receipt data** (`schemaVersion: 1`) — never PNGs, screenshots, or Base64 images.
> - **Never recalculates** financial totals (`subtotal`, `discountTotal`, `vatRate`, `vatAmount`, `grandTotal`). The Web POS is the single authoritative source for all calculations.
> - **Zero Firebase / Cloud dependencies**: Operates 100% locally with embedded SQLite persistence (`WAL` mode).
> - **Accurate Status Reporting**: A job status of `submitted` (`ส่งเข้าเครื่องพิมพ์แล้ว`) confirms that the OS spooler or network/USB printer transport accepted the job; it does not claim physical paper verification unless hardware reports it.

---

## 1. Project Folder Structure

```text
lib/
  main.dart                                  # Application entry point & root widget
  core/
    api_server/
      local_api_server.dart                  # Localhost HTTP API (bound to 127.0.0.1:8765)
    configuration/
      app_config_service.dart                # Persistent settings service (SQLite print_settings)
    database/
      app_database.dart                      # Transactional SQLite wrapper (WAL mode)
      migrations.dart                        # Versioned schema migrations & indexes
      database_backup_service.dart           # Online VACUUM INTO backup & retention policy
    logging/
      app_logger.dart                        # Structured logger with automatic token/PII redaction
    security/
      origin_validator.dart                  # Loopback Host (DNS rebinding guard) & Origin checks
      rate_limiter.dart                      # Sliding-window per-client rate limiter
    system_tray/
      auto_start_service.dart                # Windows Registry Run & macOS LaunchAgent login startup
      system_tray_service.dart               # System tray / macOS Menu Bar & safe exit handler
  modules/
    pairing/
      paired_device_repository.dart          # SQLite repository for paired_devices
      pairing_service.dart                   # 6-digit temporary pairing code & SHA-256 token hashing
    print_coordinator/
      central_coordinator_server.dart        # Mode B Central Print Coordinator LAN server
      coordinator_client.dart                # Mode B client forwarding backend
    print_engine/
      print_backend.dart                     # Abstract IPrintBackend contract
      os_print_backend.dart                  # Native OS driver backend (Windows Spooler / macOS CUPS)
      esc_pos_tcp_backend.dart               # Network ESC/POS backend (RAW TCP 9100 / IPP / LPR)
      usb_print_backend.dart                 # USB printer backend (OS USB queue & raw pass-through)
      mock_print_backend.dart                # Mock backend strictly for automated tests
    print_history/
      print_history_service.dart             # Historical job search & multi-criteria filtering
    print_queue/
      print_job_repository.dart              # SQLite repository for print_jobs
      print_queue_service.dart               # Per-printer serialized queue, duplicate guard & recovery
    print_routing/
      routing_rule_repository.dart           # SQLite repository for routing_rules
      print_routing_engine.dart              # Configurable routing by jobType + backup failover
    printer_discovery/
      printer_discovery_service.dart         # OS/USB discovery & controlled subnet LAN discovery
    printer_manager/
      printer_repository.dart                # SQLite repository for printers
      printer_manager.dart                   # Multi-printer management, health checks & test print
    receipt_engine/
      receipt_validator.dart                 # Strict schema v1 & security validator
      receipt_renderer.dart                  # 58mm & 80mm Thai/English layout renderer
      thai_raster_renderer.dart              # 4-level Thai glyph vertical compositor & 1-bit rasterizer
      esc_pos_encoder.dart                   # ESC/POS GS v 0 raster & TIS-620 command encoder
      pdf_receipt_builder.dart               # Roll-paper PDF generator for native OS printing
  platform/
    macos/
      macos_printer_adapter.dart             # macOS CUPS (lpstat / lp) native adapter
    windows/
      windows_printer_adapter.dart           # Windows Spooler (Get-Printer) native adapter
  shared/
    constants/
      app_constants.dart                     # Application constants & printable width definitions
    models/                                  # Immutable domain & database models
    services/
      service_locator.dart                   # Dependency injection container
    utilities/
      thai_text_utils.dart                   # Thai vowel/tone normalization & grapheme line wrapping
      format_utils.dart                      # Currency, quantity, and Thai date/time formatting
  ui/                                        # Thai-language responsive desktop interface
    app_shell.dart
    dashboard/dashboard_screen.dart
    printers/printers_screen.dart
    printers/printer_form_dialog.dart
    queue/queue_screen.dart
    history/history_screen.dart
    pairing/pairing_screen.dart
    pairing/receipt_preview_dialog.dart
    settings/settings_screen.dart
```

---

## 2. Installing Dependencies & Running Locally

### Prerequisites
- **Flutter SDK**: 3.24+ (Dart 3.7+)
- **macOS**: Xcode 15+ with macOS Desktop support enabled (`flutter config --enable-macos-desktop`)
- **Windows**: Visual Studio 2022 with "Desktop development with C++" workload (`flutter config --enable-windows-desktop`)

### Install Dependencies
```bash
flutter pub get
```

### Run in Development Mode
```bash
# Run on macOS
flutter run -d macos

# Run on Windows
flutter run -d windows
```

### Run Formatting, Static Analysis, and Automated Tests
```bash
dart format lib test
flutter analyze
flutter test
```

---

## 3. Building Production Desktop Installers

### Build for macOS (`.app` Bundle & `.dmg`)
```bash
flutter build macos --release
```
The compiled macOS application bundle is generated at:
`build/macos/Build/Products/Release/pos_print_agent.app`

To package into a distributable `.dmg` on macOS:
```bash
hdiutil create -volname "POS Print Agent" \
  -srcfolder "build/macos/Build/Products/Release/pos_print_agent.app" \
  -ov -format UDZO "build/macos/POS-Print-Agent-macOS.dmg"
```

### Build for Windows (`.exe` Release Bundle)
```bash
flutter build windows --release
```
The compiled Windows executable and required DLLs (`sqlite3.dll`, `flutter_windows.dll`, `printing_plugin.dll`) are generated at:
`build/windows/x64/runner/Release/`

---

## 4. Configuring Printers

### A. USB Printers
1. Connect the thermal receipt printer via USB and install the vendor driver (or add it in macOS **System Settings → Printers & Scanners** / Windows **Printers & scanners**).
2. Open **POS Print Agent** → **เครื่องพิมพ์ (Printers)**.
3. Click **ค้นหาเครื่องพิมพ์อัตโนมัติ (Discover Printers)** to import the detected USB/OS printer, or click **เพิ่มเครื่องพิมพ์ใหม่ (Add Printer)** and choose:
   - **Connection Type**: `สาย USB (usb)` or `ไดรเวอร์ระบบปฏิบัติการ (os)`
   - **Paper Width**: `80 มม.` (72mm printable width) or `58 มม.` (48mm printable width).
4. Click **ดูตัวอย่าง / พิมพ์ทดสอบ** to preview the Thai receipt and send a test print.

### B. LAN & Wi-Fi Printers
1. Assign a **Static IP** or **DHCP Reservation** to your LAN/Wi-Fi receipt printer (e.g. `192.168.1.200`).
2. In **เครื่องพิมพ์ (Printers)**, click **เพิ่มเครื่องพิมพ์ใหม่**:
   - **Connection Type**: `เครือข่ายสายแลน (LAN)` or `เครือข่ายไร้สาย (Wi-Fi)`
   - **Protocol**: `RAW TCP / ESC-POS (Port 9100)` (or `IPP (Port 631)` / `LPR (Port 515)`)
   - **IP Address**: Enter the printer IP (e.g. `192.168.1.200`) and Port (`9100`).
   - Enable **พิมพ์ภาษาไทยแบบภาพบิตแมป (Raster GS v 0)** so Thai vowels and tone marks render cleanly regardless of printer firmware ROM.

### C. Shared LAN Printers Across Multiple POS Computers
Go to **ตั้งค่าระบบ (Settings)** → **สถาปัตยกรรมเครื่องพิมพ์ LAN ที่ใช้ร่วมกันหลายเครื่อง**:
- **Mode A: Direct LAN Printing (`direct`)**:
  Each POS computer runs its own POS Print Agent and connects directly to the LAN printer (`192.168.1.200:9100`). Jobs are serialized per Agent, with connection timeouts and retry support.
- **Mode B: Central Print Coordinator (`coordinator_host` & `coordinator_client`)**:
  - On the **designated Coordinator computer**: Select **โหมด B (แม่ข่าย): เปิดบริการศูนย์กลางคิวพิมพ์**, bind to the computer's LAN IP (e.g., `192.168.1.100:8766`), and go to **การเชื่อมต่อ POS (Pairing)** → **สร้าง Token เชื่อมต่อใหม่** to issue a unique Bearer token for each POS computer.
  - On **other POS computers**: Select **โหมด B (ลูกข่าย): ส่งงานผ่านเครื่องแม่ข่าย**, enter `http://192.168.1.100:8766` and the issued Bearer token. All shared LAN jobs are now centrally queued and serialized by the Coordinator.

---

## 5. How the Web POS Communicates with the Agent

The Web POS communicates with the Local HTTP API at `http://127.0.0.1:8765`:

1. **Check Status**: `GET http://127.0.0.1:8765/api/status`
2. **Pair Device (First Time)**:
   - `POST http://127.0.0.1:8765/api/pairing/start` with `{"deviceName": "Cashier POS 1"}`
   - Read the 6-digit confirmation code shown in the **POS Print Agent** desktop window (`การเชื่อมต่อ POS`).
   - `POST http://127.0.0.1:8765/api/pairing/confirm` with `{"sessionId": "...", "pairingCode": "123456"}` to receive a scoped Bearer token (`ppa_...`).
3. **Send Receipt JSON**:
   - `POST http://127.0.0.1:8765/api/print` with header `Authorization: Bearer <token>` and the structured JSON receipt body.
4. **Track Job Status / Retry / Reprint**:
   - `GET http://127.0.0.1:8765/api/jobs/<jobId>`
   - `POST http://127.0.0.1:8765/api/jobs/<jobId>/retry` (only when `failed` or `cancelled`)
   - `POST http://127.0.0.1:8765/api/jobs/<jobId>/reprint` (creates a new `jobId` with `copyType: "reprint"` without creating a new sales bill).

See full API documentation and hardware checklists in:
- [`docs/WEB_POS_INTEGRATION_AND_API.md`](docs/WEB_POS_INTEGRATION_AND_API.md)
- [`docs/HARDWARE_COMPATIBILITY_AND_TESTING_CHECKLIST.md`](docs/HARDWARE_COMPATIBILITY_AND_TESTING_CHECKLIST.md)
