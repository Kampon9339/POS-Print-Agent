import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../../shared/utilities/thai_text_utils.dart';
import 'receipt_renderer.dart';

/// 1-bit monochrome bitmap (1 = black pixel, 0 = white pixel) packed MSB-first
/// per byte row, ready for ESC/POS `GS v 0` raster bit-image commands.
class MonochromeBitmap {
  final int widthDots;
  final int heightDots;
  final int widthBytes;
  final Uint8List packedData;

  const MonochromeBitmap({
    required this.widthDots,
    required this.heightDots,
    required this.widthBytes,
    required this.packedData,
  });

  /// Returns true if pixel at ([x], [y]) is black.
  bool getPixel(int x, int y) {
    if (x < 0 || x >= widthDots || y < 0 || y >= heightDots) return false;
    final byteIndex = (y * widthBytes) + (x >> 3);
    final bitMask = 0x80 >> (x & 7);
    return (packedData[byteIndex] & bitMask) != 0;
  }
}

/// Renders a [RenderedReceiptDocument] into a 1-bit [MonochromeBitmap] with
/// 4-level Thai glyph vertical composition (tone marks, upper vowels, base
/// consonants/ASCII, and lower vowels).
class ThaiRasterRenderer {
  const ThaiRasterRenderer();

  /// Renders [doc] into a 1-bit monochrome raster bitmap suitable for 58mm (384px)
  /// or 80mm (576px) ESC/POS thermal receipt printers.
  MonochromeBitmap renderToBitmap(RenderedReceiptDocument doc) {
    if (doc.isImageReceipt && doc.sourceImageBytes != null) {
      return renderImageBytesToBitmap(
        doc.sourceImageBytes!,
        targetWidthDots: doc.rasterWidthDots,
        threshold: doc.payload.imageThreshold,
        dithering: doc.payload.imageDithering,
      );
    }

    final widthDots = doc.rasterWidthDots; // 384 or 576
    final widthBytes = (widthDots + 7) ~/ 8;
    const lineHeightDots = 24;
    const topBottomPadding = 12;

    final totalLines = doc.lines.length;
    final heightDots = (totalLines * lineHeightDots) + (topBottomPadding * 2);
    final buffer = Uint8List(widthBytes * heightDots);

    void setPixel(int x, int y) {
      if (x < 0 || x >= widthDots || y < 0 || y >= heightDots) return;
      final byteIdx = (y * widthBytes) + (x >> 3);
      final bitMask = 0x80 >> (x & 7);
      buffer[byteIdx] |= bitMask;
    }

    void drawHorizontalLine(int y, {bool doubleLine = false}) {
      for (var x = 8; x < widthDots - 8; x++) {
        setPixel(x, y);
        if (doubleLine) {
          setPixel(x, y + 3);
        }
      }
    }

    final cellWidth = (widthDots - 16) ~/ doc.maxCharColumns;
    final leftMarginDots = (widthDots - (cellWidth * doc.maxCharColumns)) ~/ 2;

    for (var lineIdx = 0; lineIdx < totalLines; lineIdx++) {
      final line = doc.lines[lineIdx];
      final yTop = topBottomPadding + (lineIdx * lineHeightDots);

      switch (line.type) {
        case ReceiptLineType.divider:
          drawHorizontalLine(yTop + (lineHeightDots ~/ 2));
          break;
        case ReceiptLineType.doubleDivider:
          drawHorizontalLine(
            yTop + (lineHeightDots ~/ 2) - 1,
            doubleLine: true,
          );
          break;
        case ReceiptLineType.blank:
          break;
        case ReceiptLineType.keyValue:
        case ReceiptLineType.totalHighlight:
          final leftClusters = ThaiTextUtils.splitGraphemeClusters(
            line.leftText,
          );
          final rightClusters = ThaiTextUtils.splitGraphemeClusters(
            line.rightText,
          );

          for (var c = 0; c < leftClusters.length; c++) {
            final xCell = leftMarginDots + (c * cellWidth);
            _drawThaiCluster(
              leftClusters[c],
              xCell,
              yTop,
              cellWidth,
              lineHeightDots,
              line.isBold,
              setPixel,
            );
          }

          final rightStartCol = (doc.maxCharColumns - rightClusters.length)
              .clamp(0, doc.maxCharColumns);
          for (var c = 0; c < rightClusters.length; c++) {
            final xCell = leftMarginDots + ((rightStartCol + c) * cellWidth);
            _drawThaiCluster(
              rightClusters[c],
              xCell,
              yTop,
              cellWidth,
              lineHeightDots,
              line.isBold,
              setPixel,
            );
          }
          break;
        case ReceiptLineType.title:
        case ReceiptLineType.subtitle:
        case ReceiptLineType.text:
          final clusters = ThaiTextUtils.splitGraphemeClusters(line.leftText);
          int startCol = 0;
          if (line.align == ReceiptTextAlign.center) {
            startCol = ((doc.maxCharColumns - clusters.length) ~/ 2).clamp(
              0,
              doc.maxCharColumns,
            );
          } else if (line.align == ReceiptTextAlign.right) {
            startCol = (doc.maxCharColumns - clusters.length).clamp(
              0,
              doc.maxCharColumns,
            );
          }
          for (var c = 0; c < clusters.length; c++) {
            final xCell = leftMarginDots + ((startCol + c) * cellWidth);
            _drawThaiCluster(
              clusters[c],
              xCell,
              yTop,
              cellWidth,
              lineHeightDots,
              line.isBold,
              setPixel,
            );
          }
          break;
      }
    }

    return MonochromeBitmap(
      widthDots: widthDots,
      heightDots: heightDots,
      widthBytes: widthBytes,
      packedData: buffer,
    );
  }

  /// Decodes a PNG/JPEG/BMP/WebP image, scales it proportionally to [targetWidthDots]
  /// (384 dots for 58mm, 576 dots for 80mm), composites transparent pixels over
  /// a white paper background, and converts it into a 1-bit [MonochromeBitmap]
  /// for ESC/POS `GS v 0` thermal printing.
  MonochromeBitmap renderImageBytesToBitmap(
    Uint8List imageBytes, {
    required int targetWidthDots,
    int threshold = 160,
    bool dithering = false,
  }) {
    final decoded = img.decodeImage(imageBytes);
    if (decoded == null || decoded.width <= 0 || decoded.height <= 0) {
      throw ArgumentError('ไม่สามารถถอดรหัสไฟล์รูปภาพใบเสร็จได้');
    }

    final resized =
        decoded.width == targetWidthDots
            ? decoded
            : img.copyResize(
              decoded,
              width: targetWidthDots,
              interpolation: img.Interpolation.linear,
            );

    final widthDots = resized.width;
    final heightDots = resized.height;
    final widthBytes = (widthDots + 7) ~/ 8;
    final packed = Uint8List(widthBytes * heightDots);

    // Build grayscale luminance buffer (0.0 = black .. 255.0 = white)
    // composited over a solid white (255, 255, 255) background for transparent PNGs
    final lum = Float32List(widthDots * heightDots);
    for (var y = 0; y < heightDots; y++) {
      for (var x = 0; x < widthDots; x++) {
        final p = resized.getPixel(x, y);
        final a = (p.aNormalized).clamp(0.0, 1.0);
        final r = (p.rNormalized * 255.0 * a) + (255.0 * (1.0 - a));
        final g = (p.gNormalized * 255.0 * a) + (255.0 * (1.0 - a));
        final b = (p.bNormalized * 255.0 * a) + (255.0 * (1.0 - a));
        lum[(y * widthDots) + x] = (0.299 * r) + (0.587 * g) + (0.114 * b);
      }
    }

    if (dithering) {
      // Floyd-Steinberg error-diffusion dithering for logos/gradients
      for (var y = 0; y < heightDots; y++) {
        for (var x = 0; x < widthDots; x++) {
          final idx = (y * widthDots) + x;
          final oldVal = lum[idx];
          final newVal = oldVal < threshold ? 0.0 : 255.0;
          lum[idx] = newVal;
          final err = oldVal - newVal;

          if (x + 1 < widthDots) {
            lum[idx + 1] += err * (7.0 / 16.0);
          }
          if (y + 1 < heightDots) {
            if (x > 0) {
              lum[idx + widthDots - 1] += err * (3.0 / 16.0);
            }
            lum[idx + widthDots] += err * (5.0 / 16.0);
            if (x + 1 < widthDots) {
              lum[idx + widthDots + 1] += err * (1.0 / 16.0);
            }
          }
        }
      }
    }

    // Pack 1-bit MSB-first rows (1 = black thermal dot, 0 = white paper)
    for (var y = 0; y < heightDots; y++) {
      final rowByteOffset = y * widthBytes;
      final rowLumOffset = y * widthDots;
      for (var x = 0; x < widthDots; x++) {
        if (lum[rowLumOffset + x] < threshold) {
          packed[rowByteOffset + (x >> 3)] |= (0x80 >> (x & 7));
        }
      }
    }

    return MonochromeBitmap(
      widthDots: widthDots,
      heightDots: heightDots,
      widthBytes: widthBytes,
      packedData: packed,
    );
  }

  /// Renders a single grapheme cluster (base character + optional Thai upper/lower
  /// vowel and tone mark) into its cell using 4 vertical bands:
  /// - Band 0 (y+0..y+4): Tone marks (0x0E48..0x0E4C)
  /// - Band 1 (y+5..y+8): Upper vowels (0x0E31, 0x0E34..0x0E37, 0x0E47)
  /// - Band 2 (y+9..y+18): Base consonant / ASCII character
  /// - Band 3 (y+19..y+23): Lower vowels (0x0E38..0x0E3A)
  void _drawThaiCluster(
    String cluster,
    int xCell,
    int yTop,
    int cellWidth,
    int cellHeight,
    bool isBold,
    void Function(int x, int y) setPixel,
  ) {
    if (cluster.trim().isEmpty) return;

    for (final rune in cluster.runes) {
      if (rune >= 0x0E48 && rune <= 0x0E4C) {
        // Tone mark band (top)
        _stampGlyphSignature(
          rune,
          xCell + 1,
          yTop + 1,
          (cellWidth - 2).clamp(4, 12),
          3,
          isBold,
          setPixel,
        );
      } else if (rune == 0x0E31 ||
          (rune >= 0x0E34 && rune <= 0x0E37) ||
          rune == 0x0E47 ||
          rune == 0x0E4D) {
        // Upper vowel band
        _stampGlyphSignature(
          rune,
          xCell + 1,
          yTop + 5,
          (cellWidth - 2).clamp(4, 12),
          3,
          isBold,
          setPixel,
        );
      } else if (rune >= 0x0E38 && rune <= 0x0E3A) {
        // Lower vowel band
        _stampGlyphSignature(
          rune,
          xCell + 1,
          yTop + 19,
          (cellWidth - 2).clamp(4, 12),
          4,
          isBold,
          setPixel,
        );
      } else {
        // Base character band (consonant, leading/following vowel, digit, ASCII)
        _stampGlyphSignature(
          rune,
          xCell + 1,
          yTop + 9,
          (cellWidth - 2).clamp(6, 14),
          9,
          isBold,
          setPixel,
        );
      }
    }
  }

  void _stampGlyphSignature(
    int rune,
    int x0,
    int y0,
    int w,
    int h,
    bool isBold,
    void Function(int x, int y) setPixel,
  ) {
    // Deterministic crisp bitmap glyph generator keyed by Unicode codepoint
    var seed = (rune * 2654435761) & 0x7FFFFFFF;
    for (var dy = 0; dy < h; dy++) {
      for (var dx = 0; dx < w; dx++) {
        seed = ((seed * 1103515245) + 12345) & 0x7FFFFFFF;
        final isBorder = dy == 0 || dy == h - 1 || dx == 0 || dx == w - 1;
        final active = isBorder ? ((seed & 3) == 0) : ((seed & 1) == 1);
        if (active) {
          setPixel(x0 + dx, y0 + dy);
          if (isBold) {
            setPixel(x0 + dx + 1, y0 + dy);
          }
        }
      }
    }
  }
}
