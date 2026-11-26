# Web POS Integration & Local HTTP API Reference

## 1. Overview & Security Model

- **Default Base URL**: `http://127.0.0.1:8765`
- **Localhost Isolation**: The Local Agent API binds strictly to `127.0.0.1` and validates the HTTP `Host` header (`127.0.0.1` or `localhost`) to block DNS rebinding attacks.
- **No Permanent Hardcoded Secrets**: Never embed static API secrets in Web POS frontend code. Instead, pair the browser session using the temporary 6-digit confirmation flow (`/api/pairing/start` → `/api/pairing/confirm`) and store the resulting scoped Bearer token (`ppa_...`) in local storage.
- **No Recalculation**: The Print Agent renders the exact financial values (`subtotal`, `discountTotal`, `vatRate`, `vatAmount`, `grandTotal`) provided by the Web POS.

---

## 2. Device Pairing Workflow

### Step 1: Request Temporary Pairing Session
`POST /api/pairing/start`

**Request Body:**
```json
{
  "deviceName": "Cashier POS Chrome #1",
  "permissions": ["status", "print", "printers", "jobs"]
}
```

**Response (`200 OK`):**
```json
{
  "success": true,
  "sessionId": "8f14e45f-ceea-467a-9538-9c6e80643b12",
  "deviceName": "Cashier POS Chrome #1",
  "expiresAt": "2026-11-09T07:35:00.000",
  "message": "Check the POS Print Agent desktop application for the 6-digit pairing confirmation code."
}
```

### Step 2: Confirm Pairing with 6-Digit Code from Desktop App
`POST /api/pairing/confirm`

**Request Body:**
```json
{
  "sessionId": "8f14e45f-ceea-467a-9538-9c6e80643b12",
  "pairingCode": "482910"
}
```

**Response (`200 OK`):**
```json
{
  "success": true,
  "deviceId": "3d594650-3436-4c32-9927-489573642191",
  "deviceName": "Cashier POS Chrome #1",
  "token": "ppa_9a8b7c6d5e4f3a2b1c0d9e8f7a6b5c4d_...",
  "permissions": ["status", "print", "printers", "jobs"]
}
```

### Step 3: Revoke Credential
`POST /api/pairing/revoke`
- Headers: `Authorization: Bearer <token>`
- Optional Body: `{"deviceId": "..."}`

---

## 3. Receipt JSON Schema (`schemaVersion: 1`)

`POST /api/print`

**Headers:**
- `Content-Type: application/json; charset=utf-8`
- `Authorization: Bearer <token>`

**Request Body:**
```json
{
  "schemaVersion": 1,
  "jobId": "PRINT-20261104-0001",
  "billId": "BILL-000125",
  "billNumber": "INV-000125",
  "copyType": "original",
  "paperWidth": 80,
  "jobType": "receipt",
  "store": {
    "name": "ร้านค้าตัวอย่าง",
    "address": "จังหวัดศรีสะเกษ",
    "phone": "0123456789",
    "taxId": "0105550000000",
    "footer": "ขอบคุณที่ใช้บริการ"
  },
  "cashier": {
    "name": "พนักงานขาย"
  },
  "issuedAt": "2026-11-04T10:30:00+07:00",
  "items": [
    {
      "productName": "น้ำดื่ม",
      "quantity": 3,
      "unit": "ขวด",
      "unitPrice": 10,
      "discount": 0,
      "total": 30
    }
  ],
  "subtotal": 30,
  "discountTotal": 0,
  "vatRate": 0,
  "vatAmount": 0,
  "grandTotal": 30,
  "payment": {
    "method": "cash",
    "received": 100,
    "change": 70
  }
}
```

### Validation Rules
- `schemaVersion`: Must be `1`.
- `jobId`, `billId`, `billNumber`: Non-empty strings (max 128 chars). `jobId` must be unique per print job.
- `paperWidth` (or `paperSize`): Must be `58`, `80`, or `210` (or `"A4"` for full-sheet 210 × 297 mm tax invoices/reports).
- `jobType`: Optional routing tag (`receipt`, `kitchen`, `report`, `backup`; defaults to `receipt`).
- `targetPrinterId`: Optional explicit internal printer ID override.
- `issuedAt`: Valid ISO-8601 timestamp string.
- `items`: Non-empty array of line items; `quantity > 0`, `unitPrice >= 0`, `total >= 0`.
- `subtotal`, `discountTotal`, `vatRate`, `vatAmount`, `grandTotal`: Finite numbers `>= 0`.
- Maximum payload size: `262,144` bytes (256 KB) for structured JSON, or `10,485,760` bytes (10 MB) for Base64 image receipts.
- Any executable HTML/JavaScript (`<script>`, `javascript:`, `onerror=`) is rejected with `422 Unprocessable Entity`.

### Image Receipt Format (`POST /api/print-image` or `POST /api/print` with `imageBase64`)

In addition to structured JSON receipts, POS Print Agent supports printing pre-rendered receipt images (`PNG`, `JPEG`, `BMP`, `WebP`) sent as Base64 or Data URLs (`data:image/png;base64,...`). The agent automatically composites transparent backgrounds over white, scales the image to `384 dots` (`58mm`) or `576 dots` (`80mm`), and converts it into 1-bit monochrome thermal raster commands (`GS v 0`) or an OS Driver PDF.

```json
{
  "jobId": "IMG-20261109-0001",
  "billId": "BILL-000125",
  "billNumber": "INV-000125",
  "copyType": "original",
  "paperWidth": 80,
  "jobType": "receipt",
  "printerId": null,
  "dithering": false,
  "threshold": 160,
  "imageBase64": "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAA..."
}
```

---

## 4. Complete Endpoint Summary

| Method | Path | Description |
|---|---|---|
| `GET` | `/api/status` | Returns Agent health, version, printer count, pairing state, and queue counts |
| `GET` | `/api/printers` | Lists all configured printers and their online statuses |
| `POST` | `/api/printers` | Registers a new USB, LAN, Wi-Fi, or OS printer |
| `PATCH` | `/api/printers/:id` | Updates printer settings, IP, port, paper width, or default status |
| `DELETE` | `/api/printers/:id` | Deletes a printer and its associated routing rules |
| `POST` | `/api/printers/discover` | Discovers OS/USB printers and probes specified LAN IP or controlled subnet |
| `POST` | `/api/printers/:id/test` | Queues a Thai + English diagnostic test receipt for printer `:id` |
| `POST` | `/api/test-print` | Queues a test receipt for the default printer |
| `POST` | `/api/print` | Validates and enqueues a structured JSON receipt or `imageBase64` receipt |
| `POST` | `/api/print-image` | Validates and enqueues a Base64 image receipt (`PNG`/`JPEG`/`BMP`/`WebP`) |
| `GET` | `/api/jobs` | Lists print jobs (supports `?status=`, `?printerId=`, `?q=`, `?limit=`) |
| `GET` | `/api/jobs/:id` | Returns detailed status and receipt snapshot for job `:id` |
| `POST` | `/api/jobs/:id/retry` | Safely retries a `failed` or `cancelled` job (`409 Conflict` if already `submitted`) |
| `POST` | `/api/jobs/:id/cancel` | Cancels a `queued` or `failed` job |
| `POST` | `/api/jobs/:id/reprint` | Creates a manual reprint with a **new `jobId`** and `copyType: "reprint"` |

---

## 5. Safe Web POS Client Implementation Example (TypeScript)

```typescript
export class PosPrintAgentClient {
  constructor(
    private readonly baseUrl = 'http://127.0.0.1:8765',
    private token: string | null = null,
  ) {}

  private headers(): HeadersInit {
    const h: Record<string, string> = { 'Content-Type': 'application/json' };
    if (this.token) h['Authorization'] = `Bearer ${this.token}`;
    return h;
  }

  /**
   * Sends a receipt JSON payload and safely checks existing job status
   * if a network timeout occurs after submission.
   */
  async printReceipt(receiptPayload: Record<string, unknown>) {
    const jobId = String(receiptPayload.jobId);
    try {
      const res = await fetch(`${this.baseUrl}/api/print`, {
        method: 'POST',
        headers: this.headers(),
        body: JSON.stringify(receiptPayload),
      });
      return await res.json();
    } catch (networkErr) {
      // Never blindly resubmit with a new jobId on timeout!
      // First check whether the Agent already received and queued jobId:
      const existing = await this.getJobStatus(jobId).catch(() => null);
      if (existing && existing.success) {
        return existing;
      }
      throw networkErr;
    }
  }

  async getJobStatus(jobId: string) {
    const res = await fetch(`${this.baseUrl}/api/jobs/${encodeURIComponent(jobId)}`, {
      headers: this.headers(),
    });
    return await res.json();
  }
}
```
