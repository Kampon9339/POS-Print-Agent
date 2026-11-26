import 'dart:convert';
import 'dart:typed_data';
import '../constants/app_constants.dart';

/// Store metadata supplied in the receipt JSON.
class StoreInfo {
  final String name;
  final String address;
  final String phone;
  final String taxId;
  final String footer;

  const StoreInfo({
    required this.name,
    this.address = '',
    this.phone = '',
    this.taxId = '',
    this.footer = '',
  });

  factory StoreInfo.fromJson(Map<String, dynamic> json) {
    return StoreInfo(
      name: (json['name'] as String?) ?? '',
      address: (json['address'] as String?) ?? '',
      phone: (json['phone'] as String?) ?? '',
      taxId: (json['taxId'] as String?) ?? '',
      footer: (json['footer'] as String?) ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
    'name': name,
    'address': address,
    'phone': phone,
    'taxId': taxId,
    'footer': footer,
  };
}

/// Cashier metadata supplied in the receipt JSON.
class CashierInfo {
  final String name;

  const CashierInfo({required this.name});

  factory CashierInfo.fromJson(Map<String, dynamic> json) {
    return CashierInfo(name: (json['name'] as String?) ?? '');
  }

  Map<String, dynamic> toJson() => {'name': name};
}

/// Line item in the receipt JSON.
/// Values are preserved as supplied by the Web POS without recalculation.
class ReceiptItem {
  final String productName;
  final num quantity;
  final String unit;
  final num unitPrice;
  final num discount;
  final num total;
  final String? note;

  const ReceiptItem({
    required this.productName,
    required this.quantity,
    required this.unit,
    required this.unitPrice,
    required this.discount,
    required this.total,
    this.note,
  });

  factory ReceiptItem.fromJson(Map<String, dynamic> json) {
    return ReceiptItem(
      productName: json['productName'] as String,
      quantity: json['quantity'] as num,
      unit: (json['unit'] as String?) ?? '',
      unitPrice: json['unitPrice'] as num,
      discount: (json['discount'] as num?) ?? 0,
      total: json['total'] as num,
      note: json['note'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'productName': productName,
    'quantity': quantity,
    'unit': unit,
    'unitPrice': unitPrice,
    'discount': discount,
    'total': total,
    if (note != null) 'note': note,
  };
}

/// Payment details supplied in the receipt JSON.
class PaymentInfo {
  final String method;
  final num received;
  final num change;
  final String? reference;

  const PaymentInfo({
    required this.method,
    required this.received,
    required this.change,
    this.reference,
  });

  factory PaymentInfo.fromJson(Map<String, dynamic> json) {
    return PaymentInfo(
      method: json['method'] as String,
      received: json['received'] as num,
      change: json['change'] as num,
      reference: json['reference'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
    'method': method,
    'received': received,
    'change': change,
    if (reference != null) 'reference': reference,
  };
}

/// Authoritative structured JSON receipt payload received from the Web POS.
/// Financial totals (subtotal, discountTotal, vatRate, vatAmount, grandTotal)
/// are never recalculated by the Print Agent.
class ReceiptPayload {
  final int schemaVersion;
  final String jobId;
  final String billId;
  final String billNumber;
  final String copyType;
  final int paperWidth;
  final String jobType;
  final String? targetPrinterId;
  final StoreInfo store;
  final CashierInfo cashier;
  final String issuedAt;
  final List<ReceiptItem> items;
  final num subtotal;
  final num discountTotal;
  final num vatRate;
  final num vatAmount;
  final num grandTotal;
  final PaymentInfo payment;

  /// Optional Base64-encoded receipt image (PNG/JPEG/BMP/WebP), either raw Base64
  /// or a Data URL (`data:image/png;base64,...`).
  final String? imageBase64;

  /// Whether to apply Floyd-Steinberg error-diffusion dithering when converting
  /// an image receipt into a 1-bit monochrome thermal bitmap.
  final bool imageDithering;

  /// Luminance threshold (0..255, default 160) for 1-bit monochrome conversion.
  final int imageThreshold;

  const ReceiptPayload({
    required this.schemaVersion,
    required this.jobId,
    required this.billId,
    required this.billNumber,
    required this.copyType,
    required this.paperWidth,
    this.jobType = 'receipt',
    this.targetPrinterId,
    required this.store,
    required this.cashier,
    required this.issuedAt,
    required this.items,
    required this.subtotal,
    required this.discountTotal,
    required this.vatRate,
    required this.vatAmount,
    required this.grandTotal,
    required this.payment,
    this.imageBase64,
    this.imageDithering = false,
    this.imageThreshold = 160,
  });

  bool get isImageReceipt =>
      imageBase64 != null && imageBase64!.trim().isNotEmpty;

  /// Strips any `data:image/...;base64,` prefix and decodes the image bytes.
  Uint8List? decodeImageBytes() {
    final raw = imageBase64?.trim();
    if (raw == null || raw.isEmpty) return null;
    final clean = stripDataUrlPrefix(raw);
    return base64Decode(clean);
  }

  static String stripDataUrlPrefix(String input) {
    var s = input.trim();
    final commaIdx = s.indexOf(',');
    if (s.startsWith('data:') && commaIdx != -1) {
      s = s.substring(commaIdx + 1);
    }
    return s.replaceAll(RegExp(r'\s+'), '');
  }

  factory ReceiptPayload.fromJson(Map<String, dynamic> json) {
    final rawImg =
        (json['imageBase64'] ?? json['imageData'] ?? json['image']) as String?;
    final hasImg = rawImg != null && rawImg.trim().isNotEmpty;

    final storeMap =
        json['store'] is Map<String, dynamic>
            ? json['store'] as Map<String, dynamic>
            : const <String, dynamic>{'name': 'Image Receipt'};
    final cashierMap =
        json['cashier'] is Map<String, dynamic>
            ? json['cashier'] as Map<String, dynamic>
            : const <String, dynamic>{'name': 'POS'};
    final paymentMap =
        json['payment'] is Map<String, dynamic>
            ? json['payment'] as Map<String, dynamic>
            : const <String, dynamic>{
              'method': 'cash',
              'received': 0,
              'change': 0,
            };
    final itemsList =
        json['items'] is List<dynamic>
            ? (json['items'] as List<dynamic>)
                .whereType<Map<String, dynamic>>()
                .map(ReceiptItem.fromJson)
                .toList()
            : const <ReceiptItem>[];

    final billNumber =
        (json['billNumber'] as String?) ??
        (json['billId'] as String?) ??
        (json['jobId'] as String?) ??
        'IMG-RECEIPT';
    final billId = (json['billId'] as String?) ?? billNumber;

    return ReceiptPayload(
      schemaVersion: (json['schemaVersion'] as int?) ?? 1,
      jobId: (json['jobId'] as String?) ?? billId,
      billId: billId,
      billNumber: billNumber,
      copyType: (json['copyType'] as String?) ?? 'original',
      paperWidth:
          AppConstants.parsePaperWidthMm(
            json['paperWidth'] ?? json['paperSize'],
          ) ??
          80,
      jobType: (json['jobType'] as String?) ?? 'receipt',
      targetPrinterId:
          (json['targetPrinterId'] ?? json['printerId']) as String?,
      store: StoreInfo.fromJson(storeMap),
      cashier: CashierInfo.fromJson(cashierMap),
      issuedAt:
          (json['issuedAt'] as String?) ?? DateTime.now().toIso8601String(),
      items: itemsList,
      subtotal: (json['subtotal'] as num?) ?? 0,
      discountTotal: (json['discountTotal'] as num?) ?? 0,
      vatRate: (json['vatRate'] as num?) ?? 0,
      vatAmount: (json['vatAmount'] as num?) ?? 0,
      grandTotal: (json['grandTotal'] as num?) ?? 0,
      payment: PaymentInfo.fromJson(paymentMap),
      imageBase64: hasImg ? rawImg.trim() : null,
      imageDithering:
          (json['dithering'] as bool?) ??
          (json['imageDithering'] as bool?) ??
          false,
      imageThreshold: ((json['threshold'] as int?) ??
              (json['imageThreshold'] as int?) ??
              160)
          .clamp(16, 245),
    );
  }

  Map<String, dynamic> toJson() => {
    'schemaVersion': schemaVersion,
    'jobId': jobId,
    'billId': billId,
    'billNumber': billNumber,
    'copyType': copyType,
    'paperWidth': paperWidth,
    'jobType': jobType,
    if (targetPrinterId != null) 'targetPrinterId': targetPrinterId,
    'store': store.toJson(),
    'cashier': cashier.toJson(),
    'issuedAt': issuedAt,
    'items': items.map((e) => e.toJson()).toList(),
    'subtotal': subtotal,
    'discountTotal': discountTotal,
    'vatRate': vatRate,
    'vatAmount': vatAmount,
    'grandTotal': grandTotal,
    'payment': payment.toJson(),
    if (imageBase64 != null) 'imageBase64': imageBase64,
    if (imageBase64 != null) 'imageDithering': imageDithering,
    if (imageBase64 != null) 'imageThreshold': imageThreshold,
  };

  String toRawJson() => jsonEncode(toJson());

  ReceiptPayload copyWith({
    String? jobId,
    String? copyType,
    int? paperWidth,
    String? targetPrinterId,
    String? imageBase64,
    bool? imageDithering,
    int? imageThreshold,
  }) {
    return ReceiptPayload(
      schemaVersion: schemaVersion,
      jobId: jobId ?? this.jobId,
      billId: billId,
      billNumber: billNumber,
      copyType: copyType ?? this.copyType,
      paperWidth: paperWidth ?? this.paperWidth,
      jobType: jobType,
      targetPrinterId: targetPrinterId ?? this.targetPrinterId,
      store: store,
      cashier: cashier,
      issuedAt: issuedAt,
      items: items,
      subtotal: subtotal,
      discountTotal: discountTotal,
      vatRate: vatRate,
      vatAmount: vatAmount,
      grandTotal: grandTotal,
      payment: payment,
      imageBase64: imageBase64 ?? this.imageBase64,
      imageDithering: imageDithering ?? this.imageDithering,
      imageThreshold: imageThreshold ?? this.imageThreshold,
    );
  }
}
