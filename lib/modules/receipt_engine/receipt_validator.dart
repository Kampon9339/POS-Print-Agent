import 'dart:convert';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../shared/constants/app_constants.dart';
import '../../shared/models/receipt_payload.dart';

/// Structured validation result for incoming receipt JSON payloads.
class ReceiptValidationResult {
  final bool isValid;
  final ReceiptPayload? payload;
  final List<String> errors;
  final String? errorCode;

  const ReceiptValidationResult._({
    required this.isValid,
    this.payload,
    this.errors = const [],
    this.errorCode,
  });

  factory ReceiptValidationResult.success(ReceiptPayload payload) {
    return ReceiptValidationResult._(isValid: true, payload: payload);
  }

  factory ReceiptValidationResult.failure(
    List<String> errors, {
    String errorCode = 'VALIDATION_ERROR',
  }) {
    return ReceiptValidationResult._(
      isValid: false,
      errors: errors,
      errorCode: errorCode,
    );
  }
}

/// Validates receipt JSON payloads without recalculating any financial values.
class ReceiptValidator {
  ReceiptValidator._();

  static final RegExp _unsafeScriptPattern = RegExp(
    r'(<\s*script|javascript\s*:|onerror\s*=|onload\s*=|<\s*iframe|<\s*object)',
    caseSensitive: false,
  );

  /// Validates a raw JSON string, enforcing size limits and structural rules.
  /// Supports both structured JSON receipts and Base64 image receipts.
  static ReceiptValidationResult validateRawJson(
    String rawBody, {
    int? maxBytes,
    bool allowAutoJobIdForImage = false,
  }) {
    if (rawBody.trim().isEmpty) {
      return ReceiptValidationResult.failure([
        'Request body cannot be empty.',
      ], errorCode: 'MALFORMED_JSON');
    }

    final byteLength = utf8.encode(rawBody).length;
    final hasImageHint =
        rawBody.contains('"imageBase64"') ||
        rawBody.contains('"imageData"') ||
        rawBody.contains('"image"');
    final effectiveMaxBytes =
        maxBytes ??
        (hasImageHint
            ? AppConstants.maxImageRequestBodyBytes
            : AppConstants.maxRequestBodyBytes);

    if (byteLength > effectiveMaxBytes) {
      return ReceiptValidationResult.failure([
        'Request payload exceeds maximum allowed size of $effectiveMaxBytes bytes.',
      ], errorCode: 'PAYLOAD_TOO_LARGE');
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(rawBody);
    } catch (e) {
      return ReceiptValidationResult.failure([
        'Malformed JSON payload: ${e.toString()}',
      ], errorCode: 'MALFORMED_JSON');
    }

    if (decoded is! Map<String, dynamic>) {
      return ReceiptValidationResult.failure([
        'Receipt payload root must be a JSON object.',
      ], errorCode: 'MALFORMED_JSON');
    }

    return validateMap(decoded, allowAutoJobIdForImage: allowAutoJobIdForImage);
  }

  /// Validates a decoded JSON map against the versioned Receipt Schema
  /// (either structured JSON receipt or Base64 image receipt).
  static ReceiptValidationResult validateMap(
    Map<String, dynamic> map, {
    bool allowAutoJobIdForImage = false,
  }) {
    final rawImg = map['imageBase64'] ?? map['imageData'] ?? map['image'];
    if (rawImg != null) {
      return validateImageMap(map, allowAutoJobId: allowAutoJobIdForImage);
    }

    final errors = <String>[];

    // 1. schemaVersion (default 1 if omitted, or must equal supportedSchemaVersion)
    final schemaVersion = map['schemaVersion'] ?? 1;
    if (schemaVersion is! int ||
        schemaVersion != AppConstants.supportedSchemaVersion) {
      errors.add(
        'schemaVersion must be integer ${AppConstants.supportedSchemaVersion}.',
      );
    }

    // 2. Identifiers: jobId, billId, billNumber
    _validateRequiredString(map, 'jobId', errors, maxLength: 128);
    _validateRequiredString(map, 'billId', errors, maxLength: 128);
    _validateRequiredString(map, 'billNumber', errors, maxLength: 128);

    // 3. copyType
    if (map['copyType'] != null) {
      if (map['copyType'] is! String ||
          (map['copyType'] as String).trim().isEmpty) {
        errors.add('copyType must be a non-empty string.');
      } else {
        _checkUnsafeContent('copyType', map['copyType'] as String, errors);
      }
    }

    // 4. paperWidth / paperSize (supports 58, 80, 210, or "A4")
    final parsedPaperWidth = AppConstants.parsePaperWidthMm(
      map['paperWidth'] ?? map['paperSize'],
    );
    if (parsedPaperWidth == null) {
      errors.add('paperWidth must be one of 58, 80, 210 (or "A4").');
    }

    // 5. store object
    final store = map['store'];
    if (store is! Map<String, dynamic>) {
      errors.add('store is required and must be an object.');
    } else {
      _validateRequiredString(store, 'name', errors, prefix: 'store.');
      _validateOptionalString(store, 'address', errors, prefix: 'store.');
      _validateOptionalString(store, 'phone', errors, prefix: 'store.');
      _validateOptionalString(store, 'taxId', errors, prefix: 'store.');
      _validateOptionalString(store, 'footer', errors, prefix: 'store.');
    }

    // 6. cashier object
    final cashier = map['cashier'];
    if (cashier is! Map<String, dynamic>) {
      errors.add('cashier is required and must be an object.');
    } else {
      _validateRequiredString(cashier, 'name', errors, prefix: 'cashier.');
    }

    // 7. issuedAt date
    final issuedAt = map['issuedAt'];
    if (issuedAt is! String || issuedAt.trim().isEmpty) {
      errors.add('issuedAt is required and must be an ISO-8601 date string.');
    } else if (DateTime.tryParse(issuedAt) == null) {
      errors.add('issuedAt must be a valid ISO-8601 date/time string.');
    }

    // 8. items array
    final items = map['items'];
    if (items is! List || items.isEmpty) {
      errors.add('items is required and must be a non-empty array.');
    } else {
      for (var i = 0; i < items.length; i++) {
        final item = items[i];
        if (item is! Map<String, dynamic>) {
          errors.add('items[$i] must be an object.');
          continue;
        }
        _validateRequiredString(
          item,
          'productName',
          errors,
          prefix: 'items[$i].',
          maxLength: 500,
        );
        _validateOptionalString(
          item,
          'unit',
          errors,
          prefix: 'items[$i].',
          maxLength: 64,
        );
        _validateNumber(
          item,
          'quantity',
          errors,
          prefix: 'items[$i].',
          strictlyPositive: true,
        );
        _validateNumber(
          item,
          'unitPrice',
          errors,
          prefix: 'items[$i].',
          allowZero: true,
        );
        if (item['discount'] != null) {
          _validateNumber(
            item,
            'discount',
            errors,
            prefix: 'items[$i].',
            allowZero: true,
          );
        }
        _validateNumber(
          item,
          'total',
          errors,
          prefix: 'items[$i].',
          allowZero: true,
        );
      }
    }

    // 9. Financial totals (validated for numeric integrity, NEVER recalculated)
    _validateNumber(map, 'subtotal', errors, allowZero: true);
    if (map['discountTotal'] != null) {
      _validateNumber(map, 'discountTotal', errors, allowZero: true);
    }
    if (map['vatRate'] != null) {
      _validateNumber(map, 'vatRate', errors, allowZero: true);
    }
    if (map['vatAmount'] != null) {
      _validateNumber(map, 'vatAmount', errors, allowZero: true);
    }
    _validateNumber(map, 'grandTotal', errors, allowZero: true);

    // 10. payment object
    final payment = map['payment'];
    if (payment is! Map<String, dynamic>) {
      errors.add('payment is required and must be an object.');
    } else {
      _validateRequiredString(payment, 'method', errors, prefix: 'payment.');
      _validateNumber(
        payment,
        'received',
        errors,
        prefix: 'payment.',
        allowZero: true,
      );
      _validateNumber(
        payment,
        'change',
        errors,
        prefix: 'payment.',
        allowZero: true,
      );
    }

    if (errors.isNotEmpty) {
      return ReceiptValidationResult.failure(errors);
    }

    return ReceiptValidationResult.success(ReceiptPayload.fromJson(map));
  }

  /// Validates an Image Receipt JSON map (`imageBase64` / `imageData` / `image`).
  static ReceiptValidationResult validateImageMap(
    Map<String, dynamic> map, {
    bool allowAutoJobId = true,
  }) {
    final errors = <String>[];
    final normalizedMap = Map<String, dynamic>.from(map);

    // 1. Validate schemaVersion if present
    final schemaVersion = normalizedMap['schemaVersion'] ?? 1;
    if (schemaVersion is! int ||
        schemaVersion != AppConstants.supportedSchemaVersion) {
      errors.add(
        'schemaVersion must be integer ${AppConstants.supportedSchemaVersion}.',
      );
    }

    // 2. Identifiers (auto-populate if allowAutoJobId is true and omitted)
    final nowMs = DateTime.now().millisecondsSinceEpoch;
    if (allowAutoJobId &&
        (normalizedMap['jobId'] == null ||
            (normalizedMap['jobId'] is String &&
                (normalizedMap['jobId'] as String).trim().isEmpty))) {
      normalizedMap['jobId'] = 'IMG-JOB-$nowMs';
    }
    _validateRequiredString(normalizedMap, 'jobId', errors, maxLength: 128);

    if (normalizedMap['billNumber'] == null ||
        (normalizedMap['billNumber'] is String &&
            (normalizedMap['billNumber'] as String).trim().isEmpty)) {
      normalizedMap['billNumber'] =
          (normalizedMap['billId'] as String?) ??
          (normalizedMap['jobId'] as String?) ??
          'IMG-$nowMs';
    }
    if (normalizedMap['billId'] == null ||
        (normalizedMap['billId'] is String &&
            (normalizedMap['billId'] as String).trim().isEmpty)) {
      normalizedMap['billId'] = normalizedMap['billNumber'];
    }
    _validateRequiredString(normalizedMap, 'billId', errors, maxLength: 128);
    _validateRequiredString(
      normalizedMap,
      'billNumber',
      errors,
      maxLength: 128,
    );

    // 3. paperWidth / paperSize (default 80 if omitted in image mode; supports 58, 80, 210, or "A4")
    final rawPaperWidth =
        normalizedMap['paperWidth'] ?? normalizedMap['paperSize'] ?? 80;
    final parsedPaperWidth = AppConstants.parsePaperWidthMm(rawPaperWidth);
    if (parsedPaperWidth == null) {
      errors.add('paperWidth must be one of 58, 80, 210 (or "A4").');
    } else {
      normalizedMap['paperWidth'] = parsedPaperWidth;
    }

    // 4. Validate Base64 image data and verify it decodes as a valid image
    final rawImg =
        normalizedMap['imageBase64'] ??
        normalizedMap['imageData'] ??
        normalizedMap['image'];
    if (rawImg is! String || rawImg.trim().isEmpty) {
      errors.add(
        'imageBase64 is required and must be a non-empty Base64 image string.',
      );
    } else {
      try {
        final cleanBase64 = ReceiptPayload.stripDataUrlPrefix(rawImg);
        final Uint8List imgBytes = base64Decode(cleanBase64);
        if (imgBytes.isEmpty) {
          errors.add('Decoded imageBase64 byte array is empty.');
        } else {
          final decodedImage = img.decodeImage(imgBytes);
          if (decodedImage == null ||
              decodedImage.width <= 0 ||
              decodedImage.height <= 0) {
            errors.add(
              'imageBase64 could not be decoded as a valid PNG/JPEG/BMP/WebP image.',
            );
          } else {
            normalizedMap['imageBase64'] = cleanBase64;
          }
        }
      } catch (e) {
        errors.add('Invalid Base64 encoding in imageBase64: $e');
      }
    }

    if (errors.isNotEmpty) {
      return ReceiptValidationResult.failure(errors);
    }

    return ReceiptValidationResult.success(
      ReceiptPayload.fromJson(normalizedMap),
    );
  }

  static void _validateRequiredString(
    Map<String, dynamic> map,
    String key,
    List<String> errors, {
    String prefix = '',
    int maxLength = 256,
  }) {
    final val = map[key];
    final fullKey = '$prefix$key';
    if (val is! String || val.trim().isEmpty) {
      errors.add('$fullKey is required and must be a non-empty string.');
      return;
    }
    if (val.length > maxLength) {
      errors.add('$fullKey exceeds maximum length of $maxLength characters.');
    }
    _checkUnsafeContent(fullKey, val, errors);
  }

  static void _validateOptionalString(
    Map<String, dynamic> map,
    String key,
    List<String> errors, {
    String prefix = '',
    int maxLength = 512,
  }) {
    final val = map[key];
    if (val == null) return;
    final fullKey = '$prefix$key';
    if (val is! String) {
      errors.add('$fullKey must be a string.');
      return;
    }
    if (val.length > maxLength) {
      errors.add('$fullKey exceeds maximum length of $maxLength characters.');
    }
    _checkUnsafeContent(fullKey, val, errors);
  }

  static void _checkUnsafeContent(
    String fieldName,
    String value,
    List<String> errors,
  ) {
    if (_unsafeScriptPattern.hasMatch(value)) {
      errors.add(
        '$fieldName contains prohibited executable HTML/JavaScript content.',
      );
    }
  }

  static void _validateNumber(
    Map<String, dynamic> map,
    String key,
    List<String> errors, {
    String prefix = '',
    bool strictlyPositive = false,
    bool allowZero = true,
  }) {
    final val = map[key];
    final fullKey = '$prefix$key';
    if (val is! num || val.isNaN || val.isInfinite) {
      errors.add('$fullKey is required and must be a valid finite number.');
      return;
    }
    if (strictlyPositive && val <= 0) {
      errors.add('$fullKey must be greater than 0.');
    } else if (!strictlyPositive && allowZero && val < 0) {
      errors.add('$fullKey must be 0 or greater.');
    }
  }
}
