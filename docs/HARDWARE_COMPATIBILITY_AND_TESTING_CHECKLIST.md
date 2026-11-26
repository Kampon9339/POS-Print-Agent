# Printer Hardware Compatibility & Manual Hardware Testing Checklist

## 1. Printer Hardware Compatibility Matrix

| Connection Type | Protocol | Backend | Windows Support | macOS Support | Thai Rendering Mode | Notes |
|---|---|---|---|---|---|---|
| **LAN (Ethernet)** | `raw_tcp` (Port 9100) | `EscPosTcpBackend` | Yes | Yes | 1-bit Raster (`GS v 0`) or TIS-620 (`ESC t`) | Compatible with Epson TM-T82/T88, Xprinter, Bixolon, Star (ESC/POS mode), Sunmi |
| **Wi-Fi** | `raw_tcp` (Port 9100) | `EscPosTcpBackend` | Yes | Yes | 1-bit Raster (`GS v 0`) | Recommend static IP / DHCP reservation on store router |
| **LAN / Wi-Fi** | `ipp` (Port 631) / `lpr` (Port 515) | `OsPrintBackend` / `EscPosTcpBackend` | Yes | Yes | PDF Roll / Raster | Use `OsPrintBackend` for non-ESC/POS office/laser printers |
| **USB** | `os_driver` | `UsbPrintBackend` → `OsPrintBackend` | Yes (Windows Spooler) | Yes (CUPS `lp`) | Vector Thai Font + Raster Fallback | Works with any printer that has an installed Windows or macOS driver |
| **USB** | `usb_raw` | `UsbPrintBackend` | Yes (`copy /b` to USB share) | Yes (`lp -o raw`) | 1-bit Raster (`GS v 0`) | Direct ESC/POS command pass-through over USB queue |
| **OS Driver** | `os_driver` | `OsPrintBackend` | Yes | Yes | Vector Thai Font + Raster Fallback | Supports both thermal roll (58mm/80mm) and standard printers |

### Printable Width vs. Nominal Paper Width
- **58mm Paper Roll**: Actual printable width is **48mm** (`384 dots` at 203 DPI), minus configurable left/right margins.
- **80mm Paper Roll**: Actual printable width is **72mm** (`576 dots` at 203 DPI), minus configurable left/right margins.

---

## 2. Manual Hardware Testing Checklist (USB & LAN Printers)

Use this checklist when validating physical receipt printers in a store or staging environment:

### A. USB Thermal Printer Checklist
- [ ] **1. OS Driver Registration**: Connect the USB printer, verify it appears in Windows **Printers & scanners** or macOS **Printers & Scanners**, and click **ค้นหาเครื่องพิมพ์อัตโนมัติ** in POS Print Agent to import it.
- [ ] **2. 58mm & 80mm Paper Sizing**: Set paper width to match the physical roll (`58mm` or `80mm`) and verify no right-edge text clipping occurs on currency amounts (`รวม (฿)`).
- [ ] **3. Thai Vowel & Tone Mark Alignment**: Print the built-in diagnostic test receipt (`ดูตัวอย่าง / พิมพ์ทดสอบ`) containing `น้ำดื่มบริสุทธิ์ (กิ่ง กุ้ง เก๋ง)` and verify upper vowels (`ิ ี ึ ื ั`) and tone marks (`่ ้ ๊ ๋`) do not overlap or float onto separate columns.
- [ ] **4. Long Product Name Wrapping**: Print a receipt with a 120-character Thai/English product name and confirm clean multi-line wrapping without splitting combining characters.
- [ ] **5. USB Cable Unplug Recovery**: Unplug the USB cable, submit a print job, verify the job transitions to `failed` (`พิมพ์ไม่สำเร็จ`) with a descriptive error message, reconnect the USB cable, and click **ลองพิมพ์ใหม่ (Retry)** in the Print Queue.

### B. LAN / Wi-Fi ESC/POS Printer Checklist
- [ ] **1. Static IP & Port 9100 Check**: Verify the LAN printer has a static IP or DHCP reservation and responds to **ตรวจสอบการเชื่อมต่อ** on port `9100`.
- [ ] **2. Raster (`GS v 0`) vs. Character Mode**: Test printing with **พิมพ์ภาษาไทยแบบภาพบิตแมป (Raster GS v 0)** enabled and verify crisp Thai output and automatic paper cutter (`GS V 66 0`) execution.
- [ ] **3. Long Receipt Banding (30+ Items)**: Send a receipt with 30+ line items and confirm the 128-row raster banding streams smoothly without overflowing the printer receive buffer.
- [ ] **4. Duplicate `jobId` Prevention**: Send the exact same `POST /api/print` request twice with the same `jobId`; verify the second request returns `isDuplicate: true` and the printer only prints once.
- [ ] **5. Manual Reprint Verification**: Click **พิมพ์ซ้ำ (New Job ID)** on a `submitted` job; verify the printed receipt displays `[ พิมพ์ซ้ำ (Reprint) ]`, uses a new `REPRINT-...` job ID, and preserves the original `billNumber` and financial totals.
- [ ] **6. Multi-Printer Independent Queues**: Configure one online LAN printer and one unreachable IP (`192.168.1.253`); send jobs to both and verify the online printer prints immediately while the unreachable printer times out independently.
- [ ] **7. Shared LAN Mode B (Central Coordinator)**: On Computer 1, enable **โหมด B (แม่ข่าย)** on port `8766` and issue a Bearer token. On Computer 2, enable **โหมด B (ลูกข่าย)** with Computer 1's LAN URL and token. Send concurrent print jobs from both computers and verify the shared LAN printer prints them sequentially without garbled interleaved bytes.
