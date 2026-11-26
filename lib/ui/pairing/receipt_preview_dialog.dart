import 'package:flutter/material.dart';
import '../../modules/receipt_engine/pdf_receipt_builder.dart';
import '../../modules/receipt_engine/receipt_renderer.dart';
import '../../modules/receipt_engine/thai_raster_renderer.dart';

/// Displays an accurate visual preview of a 58mm or 80mm rendered Thai receipt
/// before or after printing, including both vector layout and thermal raster view.
class ReceiptPreviewDialog extends StatefulWidget {
  final RenderedReceiptDocument document;
  final VoidCallback? onConfirmPrint;

  const ReceiptPreviewDialog({
    super.key,
    required this.document,
    this.onConfirmPrint,
  });

  @override
  State<ReceiptPreviewDialog> createState() => _ReceiptPreviewDialogState();
}

class _ReceiptPreviewDialogState extends State<ReceiptPreviewDialog> {
  bool _showRasterBitmap = false;

  @override
  Widget build(BuildContext context) {
    final doc = widget.document;
    final isA4 = doc.paperWidthMm == 210;
    final previewWidthPx =
        isA4 ? 560.0 : (doc.paperWidthMm == 58 ? 290.0 : 390.0);
    final paperLabel = isA4 ? 'A4 (210 × 297 มม.)' : '${doc.paperWidthMm} มม.';

    return AlertDialog(
      title: Row(
        children: [
          const Icon(Icons.receipt_long, color: Colors.indigo),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'ตัวอย่างใบเสร็จ ($paperLabel — พื้นที่พิมพ์จริง ${doc.printableWidthMm.toStringAsFixed(0)} มม.)',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(
                value: false,
                label: Text('มุมมองใบเสร็จ'),
                icon: Icon(Icons.article_outlined, size: 16),
              ),
              ButtonSegment(
                value: true,
                label: Text('Raster (ESC/POS)'),
                icon: Icon(Icons.grid_on, size: 16),
              ),
            ],
            selected: {_showRasterBitmap},
            onSelectionChanged: (sel) {
              setState(() => _showRasterBitmap = sel.first);
            },
          ),
        ],
      ),
      content: SizedBox(
        width: isA4 ? 640 : 480,
        height: 540,
        child: Container(
          color: Colors.grey.shade200,
          alignment: Alignment.topCenter,
          padding: const EdgeInsets.all(16),
          child: SingleChildScrollView(
            child: Container(
              width: previewWidthPx,
              padding: EdgeInsets.all(doc.marginMm * 2.5),
              decoration: BoxDecoration(
                color: Colors.white,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.12),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child:
                  _showRasterBitmap
                      ? _buildRasterView(doc)
                      : _buildVisualLines(doc),
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('ปิดหน้าต่าง'),
        ),
        if (widget.onConfirmPrint != null)
          FilledButton.icon(
            onPressed: () {
              Navigator.of(context).pop();
              widget.onConfirmPrint?.call();
            },
            icon: const Icon(Icons.print),
            label: const Text('ส่งพิมพ์ใบเสร็จนี้'),
          ),
      ],
    );
  }

  Widget _buildRasterView(RenderedReceiptDocument doc) {
    const rasterRenderer = ThaiRasterRenderer();
    final bitmap = rasterRenderer.renderToBitmap(doc);
    final pngBytes = PdfReceiptBuilder.encodeBitmapToPng(bitmap);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'ขนาดภาพบิตแมป: ${bitmap.widthDots} x ${bitmap.heightDots} จุด (Dots)',
          style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
        ),
        const SizedBox(height: 8),
        Image.memory(
          pngBytes,
          fit: BoxFit.contain,
          filterQuality: FilterQuality.none,
        ),
      ],
    );
  }

  Widget _buildVisualLines(RenderedReceiptDocument doc) {
    if (doc.isImageReceipt && doc.sourceImageBytes != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'ใบเสร็จแบบรูปภาพต้นฉบับ (${doc.payload.billNumber})',
            style: TextStyle(fontSize: 11, color: Colors.grey.shade700),
          ),
          const SizedBox(height: 8),
          Image.memory(doc.sourceImageBytes!, fit: BoxFit.contain),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children:
          doc.lines.map((line) {
            switch (line.type) {
              case ReceiptLineType.divider:
                return const Divider(height: 12, thickness: 1);
              case ReceiptLineType.doubleDivider:
                return const Column(
                  children: [
                    Divider(height: 4, thickness: 1.5, color: Colors.black87),
                    Divider(height: 4, thickness: 1.5, color: Colors.black87),
                  ],
                );
              case ReceiptLineType.blank:
                return const SizedBox(height: 8);
              case ReceiptLineType.keyValue:
              case ReceiptLineType.totalHighlight:
                final style = TextStyle(
                  fontSize: doc.baseFontSize * line.fontSizeScale,
                  fontWeight: line.isBold ? FontWeight.bold : FontWeight.normal,
                  height: doc.lineSpacing,
                  color: Colors.black,
                );
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: Text(line.leftText, style: style)),
                      const SizedBox(width: 8),
                      Text(line.rightText, style: style),
                    ],
                  ),
                );
              case ReceiptLineType.title:
              case ReceiptLineType.subtitle:
              case ReceiptLineType.text:
                final style = TextStyle(
                  fontSize: doc.baseFontSize * line.fontSizeScale,
                  fontWeight: line.isBold ? FontWeight.bold : FontWeight.normal,
                  height: doc.lineSpacing,
                  color: Colors.black,
                );
                TextAlign align = TextAlign.left;
                if (line.align == ReceiptTextAlign.center) {
                  align = TextAlign.center;
                } else if (line.align == ReceiptTextAlign.right) {
                  align = TextAlign.right;
                }
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 1.5),
                  child: Text(line.leftText, textAlign: align, style: style),
                );
            }
          }).toList(),
    );
  }
}
