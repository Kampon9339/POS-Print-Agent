import 'dart:typed_data';
import '../../shared/constants/app_constants.dart';
import '../../shared/models/receipt_payload.dart';
import '../../shared/utilities/format_utils.dart';
import '../../shared/utilities/thai_text_utils.dart';

/// Alignment for a rendered receipt line.
enum ReceiptTextAlign { left, center, right }

/// Type of line in a rendered receipt document.
enum ReceiptLineType {
  title,
  subtitle,
  text,
  keyValue,
  divider,
  doubleDivider,
  blank,
  totalHighlight,
}

/// A single structured line in a rendered receipt document.
class ReceiptRenderLine {
  final ReceiptLineType type;
  final String leftText;
  final String rightText;
  final ReceiptTextAlign align;
  final bool isBold;
  final double fontSizeScale;

  const ReceiptRenderLine({
    required this.type,
    this.leftText = '',
    this.rightText = '',
    this.align = ReceiptTextAlign.left,
    this.isBold = false,
    this.fontSizeScale = 1.0,
  });
}

/// Complete rendered receipt document ready for OS PDF, UI Preview, or ESC/POS.
class RenderedReceiptDocument {
  final ReceiptPayload payload;
  final int paperWidthMm;
  final double printableWidthMm;
  final int rasterWidthDots;
  final int maxCharColumns;
  final double baseFontSize;
  final double lineSpacing;
  final double marginMm;
  final List<ReceiptRenderLine> lines;
  final String plainText;

  /// Decoded image bytes (PNG/JPEG/BMP/WebP) when the receipt was submitted as an image.
  final Uint8List? sourceImageBytes;

  const RenderedReceiptDocument({
    required this.payload,
    required this.paperWidthMm,
    required this.printableWidthMm,
    required this.rasterWidthDots,
    required this.maxCharColumns,
    required this.baseFontSize,
    required this.lineSpacing,
    required this.marginMm,
    required this.lines,
    required this.plainText,
    this.sourceImageBytes,
  });

  bool get isImageReceipt =>
      sourceImageBytes != null && sourceImageBytes!.isNotEmpty;
}

/// Renders a validated [ReceiptPayload] into a [RenderedReceiptDocument]
/// for 58mm or 80mm paper without recalculating any financial values.
class ReceiptRenderer {
  const ReceiptRenderer();

  RenderedReceiptDocument render(
    ReceiptPayload payload, {
    int? overridePaperWidthMm,
    double fontSize = 14.0,
    double lineSpacing = 1.25,
    double marginMm = 4.0,
    String customHeaderNote = '',
    String customFooterNote = '',
  }) {
    final paperWidth =
        overridePaperWidthMm ??
        (AppConstants.supportedPaperWidths.contains(payload.paperWidth)
            ? payload.paperWidth
            : 80);

    final printableMm = AppConstants.printableWidthMm(
      paperWidth,
      marginMm: marginMm,
    );
    final rasterDots = AppConstants.rasterDotsWidth(paperWidth);

    // Base columns: 32 cols for 58mm, 48 cols for 80mm, 88 cols for A4 (210mm)
    final baseCols = paperWidth == 210 ? 88 : (paperWidth == 58 ? 32 : 48);
    final fontRatio = (14.0 / fontSize.clamp(10.0, 22.0));
    final maxColumns = (baseCols * fontRatio).round().clamp(24, 110);

    // If the POS sent a Base64 receipt image, decode and return an image-backed document
    if (payload.isImageReceipt) {
      final decodedBytes = payload.decodeImageBytes();
      final imageSummaryLines = <ReceiptRenderLine>[
        ReceiptRenderLine(
          type: ReceiptLineType.title,
          leftText: payload.store.name,
          align: ReceiptTextAlign.center,
          isBold: true,
        ),
        ReceiptRenderLine(
          type: ReceiptLineType.subtitle,
          leftText:
              '[ ใบเสร็จแบบรูปภาพ (${FormatUtils.formatCopyTypeThai(payload.copyType)}) ]',
          align: ReceiptTextAlign.center,
        ),
        ReceiptRenderLine(
          type: ReceiptLineType.keyValue,
          leftText: 'เลขที่บิล:',
          rightText: payload.billNumber,
          isBold: true,
        ),
      ];
      return RenderedReceiptDocument(
        payload: payload,
        paperWidthMm: paperWidth,
        printableWidthMm: printableMm,
        rasterWidthDots: rasterDots,
        maxCharColumns: maxColumns,
        baseFontSize: fontSize,
        lineSpacing: lineSpacing,
        marginMm: marginMm,
        lines: imageSummaryLines,
        plainText: _buildPlainText(imageSummaryLines, maxColumns),
        sourceImageBytes: decodedBytes,
      );
    }

    final lines = <ReceiptRenderLine>[];

    // 1. Optional Custom Header Note
    if (customHeaderNote.trim().isNotEmpty) {
      for (final wrapped in ThaiTextUtils.wrapThaiText(
        customHeaderNote.trim(),
        maxColumns,
      )) {
        lines.add(
          ReceiptRenderLine(
            type: ReceiptLineType.subtitle,
            leftText: wrapped,
            align: ReceiptTextAlign.center,
          ),
        );
      }
    }

    // 2. Store Name & Details
    for (final wrapped in ThaiTextUtils.wrapThaiText(
      payload.store.name,
      (maxColumns * 0.85).round(),
    )) {
      lines.add(
        ReceiptRenderLine(
          type: ReceiptLineType.title,
          leftText: wrapped,
          align: ReceiptTextAlign.center,
          isBold: true,
          fontSizeScale: 1.25,
        ),
      );
    }

    if (payload.store.address.trim().isNotEmpty) {
      for (final wrapped in ThaiTextUtils.wrapThaiText(
        payload.store.address.trim(),
        maxColumns,
      )) {
        lines.add(
          ReceiptRenderLine(
            type: ReceiptLineType.subtitle,
            leftText: wrapped,
            align: ReceiptTextAlign.center,
          ),
        );
      }
    }

    if (payload.store.phone.trim().isNotEmpty) {
      lines.add(
        ReceiptRenderLine(
          type: ReceiptLineType.subtitle,
          leftText:
              'โทร: ${ThaiTextUtils.normalizeThaiSequence(payload.store.phone.trim())}',
          align: ReceiptTextAlign.center,
        ),
      );
    }

    if (payload.store.taxId.trim().isNotEmpty) {
      lines.add(
        ReceiptRenderLine(
          type: ReceiptLineType.subtitle,
          leftText: 'เลขประจำตัวผู้เสียภาษี: ${payload.store.taxId.trim()}',
          align: ReceiptTextAlign.center,
        ),
      );
    }

    // Copy type badge if not standard original
    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.subtitle,
        leftText: '[ ${FormatUtils.formatCopyTypeThai(payload.copyType)} ]',
        align: ReceiptTextAlign.center,
        isBold: payload.copyType.toLowerCase() != 'original',
      ),
    );

    lines.add(const ReceiptRenderLine(type: ReceiptLineType.divider));

    // 3. Bill Metadata
    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.keyValue,
        leftText: 'เลขที่บิล:',
        rightText: payload.billNumber,
        isBold: true,
      ),
    );
    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.keyValue,
        leftText: 'วันที่:',
        rightText: FormatUtils.formatReceiptDateTime(payload.issuedAt),
      ),
    );
    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.keyValue,
        leftText: 'พนักงาน:',
        rightText: ThaiTextUtils.normalizeThaiSequence(payload.cashier.name),
      ),
    );

    lines.add(const ReceiptRenderLine(type: ReceiptLineType.divider));

    // 4. Items Header
    lines.add(
      const ReceiptRenderLine(
        type: ReceiptLineType.keyValue,
        leftText: 'รายการสินค้า (จำนวน x ราคา)',
        rightText: 'รวม (฿)',
        isBold: true,
      ),
    );
    lines.add(const ReceiptRenderLine(type: ReceiptLineType.divider));

    // 5. Items List (preserving authoritative POS amounts)
    for (final item in payload.items) {
      final normalizedName = ThaiTextUtils.normalizeThaiSequence(
        item.productName,
      );
      final nameWrapCols = (maxColumns - 2).clamp(16, maxColumns);
      final wrappedNameLines = ThaiTextUtils.wrapThaiText(
        normalizedName,
        nameWrapCols,
      );

      for (final nameLine in wrappedNameLines) {
        lines.add(
          ReceiptRenderLine(
            type: ReceiptLineType.text,
            leftText: nameLine,
            isBold: true,
          ),
        );
      }

      final qtyStr = FormatUtils.formatQuantity(item.quantity);
      final unitStr =
          item.unit.trim().isNotEmpty
              ? ' ${ThaiTextUtils.normalizeThaiSequence(item.unit.trim())}'
              : '';
      final priceStr = FormatUtils.formatCurrency(item.unitPrice);
      final totalStr = FormatUtils.formatCurrency(item.total);

      lines.add(
        ReceiptRenderLine(
          type: ReceiptLineType.keyValue,
          leftText: '  $qtyStr$unitStr x $priceStr',
          rightText: totalStr,
        ),
      );

      if (item.discount > 0) {
        lines.add(
          ReceiptRenderLine(
            type: ReceiptLineType.keyValue,
            leftText: '  ส่วนลดรายการ',
            rightText: '-${FormatUtils.formatCurrency(item.discount)}',
          ),
        );
      }

      if (item.note != null && item.note!.trim().isNotEmpty) {
        lines.add(
          ReceiptRenderLine(
            type: ReceiptLineType.text,
            leftText:
                '  * ${ThaiTextUtils.normalizeThaiSequence(item.note!.trim())}',
          ),
        );
      }
    }

    lines.add(const ReceiptRenderLine(type: ReceiptLineType.divider));

    // 6. Totals Section (strictly using POS supplied values without recalculation)
    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.keyValue,
        leftText: 'รวมเป็นเงิน (Subtotal)',
        rightText: FormatUtils.formatCurrency(payload.subtotal),
      ),
    );

    if (payload.discountTotal > 0) {
      lines.add(
        ReceiptRenderLine(
          type: ReceiptLineType.keyValue,
          leftText: 'ส่วนลดรวม (Discount)',
          rightText: '-${FormatUtils.formatCurrency(payload.discountTotal)}',
        ),
      );
    }

    if (payload.vatRate > 0 || payload.vatAmount > 0) {
      final rateLabel = FormatUtils.formatQuantity(payload.vatRate);
      lines.add(
        ReceiptRenderLine(
          type: ReceiptLineType.keyValue,
          leftText: 'ภาษีมูลค่าเพิ่ม (VAT $rateLabel%)',
          rightText: FormatUtils.formatCurrency(payload.vatAmount),
        ),
      );
    }

    lines.add(const ReceiptRenderLine(type: ReceiptLineType.doubleDivider));

    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.totalHighlight,
        leftText: 'ยอดสุทธิ (Grand Total)',
        rightText: '${FormatUtils.formatCurrency(payload.grandTotal)} ฿',
        isBold: true,
        fontSizeScale: 1.2,
      ),
    );

    lines.add(const ReceiptRenderLine(type: ReceiptLineType.doubleDivider));

    // 7. Payment Details
    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.keyValue,
        leftText: 'ชำระโดย:',
        rightText: FormatUtils.formatPaymentMethodThai(payload.payment.method),
      ),
    );
    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.keyValue,
        leftText: 'รับเงิน (Received):',
        rightText: FormatUtils.formatCurrency(payload.payment.received),
      ),
    );
    lines.add(
      ReceiptRenderLine(
        type: ReceiptLineType.keyValue,
        leftText: 'เงินทอน (Change):',
        rightText: FormatUtils.formatCurrency(payload.payment.change),
        isBold: true,
      ),
    );

    lines.add(const ReceiptRenderLine(type: ReceiptLineType.divider));

    // 8. Store Footer & Custom Footer
    if (payload.store.footer.trim().isNotEmpty) {
      for (final wrapped in ThaiTextUtils.wrapThaiText(
        payload.store.footer.trim(),
        maxColumns,
      )) {
        lines.add(
          ReceiptRenderLine(
            type: ReceiptLineType.subtitle,
            leftText: wrapped,
            align: ReceiptTextAlign.center,
          ),
        );
      }
    }

    if (customFooterNote.trim().isNotEmpty) {
      for (final wrapped in ThaiTextUtils.wrapThaiText(
        customFooterNote.trim(),
        maxColumns,
      )) {
        lines.add(
          ReceiptRenderLine(
            type: ReceiptLineType.subtitle,
            leftText: wrapped,
            align: ReceiptTextAlign.center,
          ),
        );
      }
    }

    final plainText = _buildPlainText(lines, maxColumns);

    return RenderedReceiptDocument(
      payload: payload,
      paperWidthMm: paperWidth,
      printableWidthMm: printableMm,
      rasterWidthDots: rasterDots,
      maxCharColumns: maxColumns,
      baseFontSize: fontSize,
      lineSpacing: lineSpacing,
      marginMm: marginMm,
      lines: lines,
      plainText: plainText,
    );
  }

  String _buildPlainText(List<ReceiptRenderLine> lines, int maxColumns) {
    final buffer = StringBuffer();
    for (final line in lines) {
      switch (line.type) {
        case ReceiptLineType.divider:
          buffer.writeln('-' * maxColumns);
          break;
        case ReceiptLineType.doubleDivider:
          buffer.writeln('=' * maxColumns);
          break;
        case ReceiptLineType.blank:
          buffer.writeln();
          break;
        case ReceiptLineType.keyValue:
        case ReceiptLineType.totalHighlight:
          final leftLen = ThaiTextUtils.visualLength(line.leftText);
          final rightLen = ThaiTextUtils.visualLength(line.rightText);
          final spaces = (maxColumns - leftLen - rightLen).clamp(1, maxColumns);
          buffer.writeln('${line.leftText}${' ' * spaces}${line.rightText}');
          break;
        case ReceiptLineType.title:
        case ReceiptLineType.subtitle:
        case ReceiptLineType.text:
          if (line.align == ReceiptTextAlign.center) {
            final visualLen = ThaiTextUtils.visualLength(line.leftText);
            final padLeft = ((maxColumns - visualLen) ~/ 2).clamp(
              0,
              maxColumns,
            );
            buffer.writeln('${' ' * padLeft}${line.leftText}');
          } else if (line.align == ReceiptTextAlign.right) {
            final visualLen = ThaiTextUtils.visualLength(line.leftText);
            final padLeft = (maxColumns - visualLen).clamp(0, maxColumns);
            buffer.writeln('${' ' * padLeft}${line.leftText}');
          } else {
            buffer.writeln(line.leftText);
          }
          break;
      }
    }
    return buffer.toString();
  }
}
