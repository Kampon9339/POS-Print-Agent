/// Application-wide constants for POS Print Agent.
class AppConstants {
  AppConstants._();

  static const String appName = 'POS Print Agent';
  static const String appVersion = '1.0.0';
  static const String apiVersion = '1.0';
  static const int supportedSchemaVersion = 1;

  /// Default Local HTTP API settings (strictly bound to 127.0.0.1)
  static const String localApiBindHost = '127.0.0.1';
  static const int defaultLocalApiPort = 8765;

  /// Default Central Print Coordinator port (Mode B)
  static const int defaultCoordinatorPort = 8766;

  /// Maximum allowed HTTP request body size for structured JSON (256 KB)
  static const int maxRequestBodyBytes = 256 * 1024;

  /// Maximum allowed HTTP request body size for Base64 Image receipts (10 MB)
  static const int maxImageRequestBodyBytes = 10 * 1024 * 1024;

  /// Supported paper widths in millimeters (58mm, 80mm thermal rolls, and 210mm A4 sheet)
  static const List<int> supportedPaperWidths = [58, 80, 210];

  /// Parses paper width from int (`58`, `80`, `210`) or string (`"58mm"`, `"80mm"`, `"A4"`, `"210"`).
  static int? parsePaperWidthMm(Object? raw) {
    if (raw is int) {
      return supportedPaperWidths.contains(raw) ? raw : null;
    }
    if (raw is String) {
      final normalized = raw.trim().toUpperCase();
      if (normalized == 'A4' || normalized == '210' || normalized == '210MM') {
        return 210;
      }
      if (normalized == '80' || normalized == '80MM') {
        return 80;
      }
      if (normalized == '58' || normalized == '58MM') {
        return 58;
      }
    }
    return null;
  }

  /// Human-readable Thai label for paper size.
  static String formatPaperWidthLabel(int paperWidthMm) {
    if (paperWidthMm == 210) return 'A4 (210×297 มม.)';
    return '$paperWidthMm มม.';
  }

  /// Actual printable widths in millimeters (accounting for hardware margins)
  static double printableWidthMm(int paperWidthMm, {double marginMm = 4.0}) {
    if (paperWidthMm == 210) {
      final effectiveMargin = marginMm < 8.0 ? 10.0 : marginMm;
      return (210.0 - (effectiveMargin * 2)).clamp(150.0, 200.0);
    }
    final basePrintable = paperWidthMm == 58 ? 48.0 : 72.0;
    final adjusted = basePrintable - (marginMm * 2);
    return adjusted.clamp(32.0, basePrintable);
  }

  /// Standard raster dot widths (384 for 58mm, 576 for 80mm, 1200 for A4)
  static int rasterDotsWidth(int paperWidthMm) {
    if (paperWidthMm == 210) return 1200;
    return paperWidthMm == 58 ? 384 : 576;
  }

  /// Default network printer ports by protocol
  static const int defaultRawTcpPort = 9100;
  static const int defaultIppPort = 631;
  static const int defaultLprPort = 515;

  /// Pairing code expiration duration
  static const Duration pairingCodeTtl = Duration(minutes: 5);

  /// Default retention policy in days for completed/failed jobs
  static const int defaultRetentionDays = 30;
}
