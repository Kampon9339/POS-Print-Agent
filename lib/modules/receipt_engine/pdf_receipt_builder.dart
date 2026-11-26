import 'dart:io';
import 'dart:typed_data';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'receipt_renderer.dart';
import 'thai_raster_renderer.dart';

/// Builds a roll-sized PDF document (58mm or 80mm) for Native OS Printing
/// (`OsPrintBackend`) on Windows and macOS.
class PdfReceiptBuilder {
  final ThaiRasterRenderer rasterRenderer;

  const PdfReceiptBuilder({this.rasterRenderer = const ThaiRasterRenderer()});

  /// Builds a PDF byte stream for [doc], using native Thai TrueType system fonts
  /// when available and embedding the high-contrast thermal raster image as
  /// universal fallback so Thai glyphs never fail offline.
  Future<Uint8List> buildPdf(RenderedReceiptDocument doc) async {
    final pdf = pw.Document(
      title: 'Receipt ${doc.payload.billNumber}',
      author: 'POS Print Agent',
    );

    final isA4 = doc.paperWidthMm == 210;
    final pageWidthPt = doc.paperWidthMm * PdfPageFormat.mm;
    final effectiveMarginMm = isA4 && doc.marginMm < 8.0 ? 12.0 : doc.marginMm;
    final marginPt = effectiveMarginMm * PdfPageFormat.mm;

    final thaiFont = _tryLoadSystemThaiFont();
    final bitmap = rasterRenderer.renderToBitmap(doc);
    final pngBytes =
        doc.isImageReceipt && doc.sourceImageBytes != null
            ? doc.sourceImageBytes!
            : encodeBitmapToPng(bitmap);

    final printableWidthPt = (pageWidthPt - (marginPt * 2)).clamp(
      80.0,
      pageWidthPt,
    );

    if (isA4) {
      final a4Format = PdfPageFormat.a4.copyWith(
        marginLeft: marginPt,
        marginRight: marginPt,
        marginTop: marginPt,
        marginBottom: marginPt,
      );
      if (thaiFont != null && !doc.isImageReceipt) {
        pdf.addPage(
          pw.MultiPage(
            pageFormat: a4Format,
            build: (context) => _buildVectorThaiReceiptList(doc, thaiFont),
          ),
        );
      } else {
        pdf.addPage(
          pw.Page(
            pageFormat: a4Format,
            build: (context) {
              return pw.Align(
                alignment: pw.Alignment.topCenter,
                child: pw.Image(
                  pw.MemoryImage(pngBytes),
                  width: printableWidthPt,
                  fit: pw.BoxFit.contain,
                ),
              );
            },
          ),
        );
      }
      return pdf.save();
    }

    // Calculate proportional height in points for 58mm / 80mm thermal roll
    final aspect = bitmap.heightDots / bitmap.widthDots;
    final estimatedHeightPt =
        (printableWidthPt * aspect) + (marginPt * 2) + (20 * PdfPageFormat.mm);

    final pageFormat = PdfPageFormat(
      pageWidthPt,
      estimatedHeightPt,
      marginAll: marginPt,
    );

    pdf.addPage(
      pw.Page(
        pageFormat: pageFormat,
        build: (context) {
          if (thaiFont != null && !doc.isImageReceipt) {
            return _buildVectorThaiReceipt(doc, thaiFont);
          }
          return pw.Center(
            child: pw.Image(
              pw.MemoryImage(pngBytes),
              width: printableWidthPt,
              fit: pw.BoxFit.contain,
            ),
          );
        },
      ),
    );

    return pdf.save();
  }

  pw.Widget _buildVectorThaiReceipt(
    RenderedReceiptDocument doc,
    pw.Font thaiFont,
  ) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      mainAxisSize: pw.MainAxisSize.min,
      children: _buildVectorThaiReceiptList(doc, thaiFont),
    );
  }

  List<pw.Widget> _buildVectorThaiReceiptList(
    RenderedReceiptDocument doc,
    pw.Font thaiFont,
  ) {
    final baseStyle = pw.TextStyle(
      font: thaiFont,
      fontSize: doc.baseFontSize * 0.75,
      lineSpacing: doc.lineSpacing,
    );
    final boldStyle = baseStyle.copyWith(fontWeight: pw.FontWeight.bold);

    final widgets = <pw.Widget>[];
    for (final line in doc.lines) {
      switch (line.type) {
        case ReceiptLineType.divider:
          widgets.add(pw.Divider(thickness: 0.5, height: 6));
          break;
        case ReceiptLineType.doubleDivider:
          widgets.add(pw.Divider(thickness: 1.2, height: 8));
          break;
        case ReceiptLineType.blank:
          widgets.add(pw.SizedBox(height: 4));
          break;
        case ReceiptLineType.keyValue:
        case ReceiptLineType.totalHighlight:
          final style = (line.isBold ? boldStyle : baseStyle).copyWith(
            fontSize: baseStyle.fontSize! * line.fontSizeScale,
          );
          widgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Expanded(child: pw.Text(line.leftText, style: style)),
                  pw.SizedBox(width: 4),
                  pw.Text(line.rightText, style: style),
                ],
              ),
            ),
          );
          break;
        case ReceiptLineType.title:
        case ReceiptLineType.subtitle:
        case ReceiptLineType.text:
          final style = (line.isBold ? boldStyle : baseStyle).copyWith(
            fontSize: baseStyle.fontSize! * line.fontSizeScale,
          );
          pw.Alignment alignment = pw.Alignment.centerLeft;
          if (line.align == ReceiptTextAlign.center) {
            alignment = pw.Alignment.center;
          } else if (line.align == ReceiptTextAlign.right) {
            alignment = pw.Alignment.centerRight;
          }
          widgets.add(
            pw.Container(
              alignment: alignment,
              padding: const pw.EdgeInsets.symmetric(vertical: 1),
              child: pw.Text(line.leftText, style: style),
            ),
          );
          break;
      }
    }

    return widgets;
  }

  pw.Font? _tryLoadSystemThaiFont() {
    final candidatePaths = <String>[
      if (Platform.isMacOS) ...[
        '/System/Library/Fonts/Supplemental/Ayuthaya.ttf',
        '/System/Library/Fonts/Supplemental/Tahoma.ttf',
        '/System/Library/Fonts/Supplemental/Krungthep.ttf',
        '/System/Library/Fonts/Supplemental/Silom.ttf',
      ],
      if (Platform.isWindows) ...[
        r'C:\Windows\Fonts\tahoma.ttf',
        r'C:\Windows\Fonts\leelawui.ttf',
        r'C:\Windows\Fonts\angsana.ttc',
      ],
    ];

    for (final path in candidatePaths) {
      try {
        final file = File(path);
        if (file.existsSync()) {
          final bytes = file.readAsBytesSync();
          return pw.Font.ttf(bytes.buffer.asByteData());
        }
      } catch (_) {}
    }
    return null;
  }

  /// Encodes a 1-bit [MonochromeBitmap] into a valid 8-bit grayscale PNG image.
  static Uint8List encodeBitmapToPng(MonochromeBitmap bitmap) {
    final width = bitmap.widthDots;
    final height = bitmap.heightDots;

    // Each scanline has 1 filter byte (0) + width grayscale bytes (0x00 black, 0xFF white)
    final rawScanlines = Uint8List((width + 1) * height);
    var offset = 0;
    for (var y = 0; y < height; y++) {
      rawScanlines[offset++] = 0; // Filter type 0 (None)
      for (var x = 0; x < width; x++) {
        rawScanlines[offset++] = bitmap.getPixel(x, y) ? 0x00 : 0xFF;
      }
    }

    final compressed = zlib.encode(rawScanlines);
    final out = BytesBuilder(copy: false);

    // PNG Signature
    out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

    // IHDR chunk (13 bytes: width, height, bitDepth=8, colorType=0 grayscale)
    final ihdr = ByteData(13);
    ihdr.setUint32(0, width, Endian.big);
    ihdr.setUint32(4, height, Endian.big);
    ihdr.setUint8(8, 8); // 8-bit grayscale
    ihdr.setUint8(9, 0); // Color type 0
    ihdr.setUint8(10, 0);
    ihdr.setUint8(11, 0);
    ihdr.setUint8(12, 0);
    _writePngChunk(out, 'IHDR', ihdr.buffer.asUint8List());

    // IDAT chunk
    _writePngChunk(out, 'IDAT', Uint8List.fromList(compressed));

    // IEND chunk
    _writePngChunk(out, 'IEND', Uint8List(0));

    return out.toBytes();
  }

  static void _writePngChunk(BytesBuilder out, String type, Uint8List data) {
    final lenBytes = ByteData(4)..setUint32(0, data.length, Endian.big);
    out.add(lenBytes.buffer.asUint8List());

    final typeBytes = type.codeUnits;
    out.add(typeBytes);
    out.add(data);

    final crcInput = Uint8List(typeBytes.length + data.length);
    crcInput.setRange(0, typeBytes.length, typeBytes);
    crcInput.setRange(typeBytes.length, crcInput.length, data);

    final crc = _crc32(crcInput);
    final crcBytes = ByteData(4)..setUint32(0, crc, Endian.big);
    out.add(crcBytes.buffer.asUint8List());
  }

  static int _crc32(Uint8List bytes) {
    var crc = 0xFFFFFFFF;
    for (final b in bytes) {
      crc ^= b;
      for (var k = 0; k < 8; k++) {
        crc = (crc & 1) != 0 ? (0xEDB88320 ^ (crc >>> 1)) : (crc >>> 1);
      }
    }
    return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
  }
}
