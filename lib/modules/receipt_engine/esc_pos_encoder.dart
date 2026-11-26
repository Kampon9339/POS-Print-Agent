import 'dart:typed_data';
import '../../shared/utilities/thai_text_utils.dart';
import 'receipt_renderer.dart';
import 'thai_raster_renderer.dart';

/// Generates ESC/POS binary command streams from a [RenderedReceiptDocument].
class EscPosEncoder {
  final ThaiRasterRenderer rasterRenderer;

  const EscPosEncoder({this.rasterRenderer = const ThaiRasterRenderer()});

  /// Encodes [doc] into ESC/POS bytes.
  /// By default (`useRasterMode = true`), renders Thai & English text as a
  /// 1-bit raster bitmap (`GS v 0`) to guarantee accurate Thai vowel and
  /// tone-mark positioning across all thermal printers.
  Uint8List encode(
    RenderedReceiptDocument doc, {
    bool useRasterMode = true,
    bool autoCut = true,
    bool openCashDrawer = false,
  }) {
    final builder = BytesBuilder(copy: false);

    // 1. Initialize printer: ESC @
    builder.add(const [0x1B, 0x40]);

    // 2. Optional cash drawer kick: ESC p 0 25 250
    if (openCashDrawer) {
      builder.add(const [0x1B, 0x70, 0x00, 0x19, 0xFA]);
    }

    if (useRasterMode || doc.isImageReceipt) {
      // Center align raster image: ESC a 1
      builder.add(const [0x1B, 0x61, 0x01]);

      final bitmap = rasterRenderer.renderToBitmap(doc);
      _appendRasterBitImageBands(builder, bitmap);
    } else {
      // Legacy TIS-620 / CP874 character mode fallback
      // Select Thai character code table (PC874 / TIS-620 = 70 or 21)
      builder.add(const [0x1B, 0x74, 21]);
      // Left align: ESC a 0
      builder.add(const [0x1B, 0x61, 0x00]);
      final plainBytes = ThaiTextUtils.encodeTis620(doc.plainText);
      builder.add(plainBytes);
    }

    // 3. Feed 4 lines: ESC d 4
    builder.add(const [0x1B, 0x64, 0x04]);

    // 4. Optional automatic paper cutter: GS V 66 0 (Feed & partial cut)
    if (autoCut) {
      builder.add(const [0x1D, 0x56, 0x42, 0x00]);
    }

    return builder.toBytes();
  }

  /// Emits `GS v 0` raster bit-image commands in horizontal bands of at most
  /// 128 rows to avoid overflowing small printer receive buffers.
  void _appendRasterBitImageBands(
    BytesBuilder builder,
    MonochromeBitmap bitmap,
  ) {
    const maxBandHeight = 128;
    final xL = bitmap.widthBytes & 0xFF;
    final xH = (bitmap.widthBytes >> 8) & 0xFF;

    var yOffset = 0;
    while (yOffset < bitmap.heightDots) {
      final bandHeight =
          (bitmap.heightDots - yOffset) > maxBandHeight
              ? maxBandHeight
              : (bitmap.heightDots - yOffset);
      final yL = bandHeight & 0xFF;
      final yH = (bandHeight >> 8) & 0xFF;

      // GS v 0 m xL xH yL yH d1...dk (m = 0 normal mode)
      builder.add([0x1D, 0x76, 0x30, 0x00, xL, xH, yL, yH]);

      final startByte = yOffset * bitmap.widthBytes;
      final endByte = startByte + (bandHeight * bitmap.widthBytes);
      builder.add(Uint8List.sublistView(bitmap.packedData, startByte, endByte));

      yOffset += bandHeight;
    }
  }
}
