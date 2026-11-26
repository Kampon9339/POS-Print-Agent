/// Formatting utilities for Thai receipts, numbers, currency, and dates.
class FormatUtils {
  FormatUtils._();

  /// Formats a numeric amount as Thai currency string (e.g. 1,250.00).
  /// Preserves the exact value supplied by the POS.
  static String formatCurrency(num amount) {
    final isNegative = amount < 0;
    final absValue = amount.abs().toDouble();
    final fixed = absValue.toStringAsFixed(2);
    final parts = fixed.split('.');
    final intPart = parts[0];
    final decPart = parts.length > 1 ? parts[1] : '00';

    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      final positionFromRight = intPart.length - i;
      buffer.write(intPart[i]);
      if (positionFromRight > 1 && positionFromRight % 3 == 1) {
        buffer.write(',');
      }
    }

    return '${isNegative ? '-' : ''}${buffer.toString()}.$decPart';
  }

  /// Formats item quantity cleanly (e.g., 3 -> "3", 1.5 -> "1.5").
  static String formatQuantity(num quantity) {
    if (quantity == quantity.roundToDouble()) {
      return quantity.toInt().toString();
    }
    return quantity.toString();
  }

  /// Formats an ISO-8601 date string into a readable Thai receipt timestamp
  /// (DD/MM/YYYY HH:mm).
  static String formatReceiptDateTime(String isoString) {
    final parsed = DateTime.tryParse(isoString);
    if (parsed == null) return isoString;
    final local = parsed.toLocal();
    final day = local.day.toString().padLeft(2, '0');
    final month = local.month.toString().padLeft(2, '0');
    final year = local.year;
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$day/$month/$year $hour:$minute';
  }

  /// Translates payment method code to Thai display text.
  static String formatPaymentMethodThai(String method) {
    switch (method.toLowerCase()) {
      case 'cash':
        return 'เงินสด (Cash)';
      case 'qr':
      case 'promptpay':
        return 'สแกน QR / พร้อมเพย์';
      case 'transfer':
        return 'โอนเงินธนาคาร';
      case 'card':
      case 'credit_card':
        return 'บัตรเครดิต/เดบิต';
      default:
        return method;
    }
  }

  /// Translates copyType to Thai header badge.
  static String formatCopyTypeThai(String copyType) {
    switch (copyType.toLowerCase()) {
      case 'original':
        return 'ต้นฉบับ (Original)';
      case 'copy':
        return 'สำเนา (Copy)';
      case 'reprint':
        return 'พิมพ์ซ้ำ (Reprint)';
      default:
        return copyType;
    }
  }
}
