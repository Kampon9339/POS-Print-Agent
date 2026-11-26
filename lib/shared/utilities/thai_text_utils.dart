import 'dart:typed_data';

/// Utilities for Thai Unicode text handling, grapheme-safe line wrapping,
/// combining vowel/tone mark awareness, and TIS-620/CP874 encoding.
class ThaiTextUtils {
  ThaiTextUtils._();

  /// Returns true if [codeUnit] is a zero-width Thai combining character
  /// (upper/lower vowel, tone mark, karan, etc.).
  static bool isThaiCombiningChar(int codeUnit) {
    return codeUnit == 0x0E31 || // MAI HAN-AKAT
        (codeUnit >= 0x0E34 && codeUnit <= 0x0E3A) || // SARA I .. PHINTHU
        (codeUnit >= 0x0E47 && codeUnit <= 0x0E4E); // MAITAIKHU .. YAMAKKAN
  }

  /// Returns true if [text] contains any Thai Unicode characters (U+0E00..U+0E7F).
  static bool containsThai(String text) {
    for (final unit in text.codeUnits) {
      if (unit >= 0x0E00 && unit <= 0x0E7F) {
        return true;
      }
    }
    return false;
  }

  /// Normalizes Thai vowel + tone mark ordering so tone marks follow upper/lower
  /// vowels consistently, preventing broken Thai glyph positioning.
  static String normalizeThaiSequence(String input) {
    if (input.isEmpty) return input;
    final units = input.codeUnits;
    final result = <int>[];

    for (var i = 0; i < units.length; i++) {
      final current = units[i];
      // If a tone mark (0x0E48..0x0E4B) comes immediately before an upper/lower vowel
      // (0x0E31, 0x0E34..0x0E39), swap them so the vowel attaches to the consonant first.
      if (i + 1 < units.length &&
          (current >= 0x0E48 && current <= 0x0E4B) &&
          (units[i + 1] == 0x0E31 ||
              (units[i + 1] >= 0x0E34 && units[i + 1] <= 0x0E39))) {
        result.add(units[i + 1]);
        result.add(current);
        i++;
      } else {
        result.add(current);
      }
    }
    return String.fromCharCodes(result);
  }

  /// Splits [text] into grapheme clusters where Thai base characters keep their
  /// attached combining vowels and tone marks together.
  static List<String> splitGraphemeClusters(String text) {
    final normalized = normalizeThaiSequence(text);
    final runes = normalized.runes.toList();
    if (runes.isEmpty) return const [];

    final clusters = <String>[];
    final currentCluster = <int>[];

    for (final rune in runes) {
      if (isThaiCombiningChar(rune) && currentCluster.isNotEmpty) {
        currentCluster.add(rune);
      } else {
        if (currentCluster.isNotEmpty) {
          clusters.add(String.fromCharCodes(currentCluster));
          currentCluster.clear();
        }
        currentCluster.add(rune);
      }
    }
    if (currentCluster.isNotEmpty) {
      clusters.add(String.fromCharCodes(currentCluster));
    }
    return clusters;
  }

  /// Returns the visual character column count (excluding zero-width Thai marks).
  static int visualLength(String text) {
    return splitGraphemeClusters(text).length;
  }

  /// Wraps [text] into lines of at most [maxColumns] visual characters without
  /// ever detaching a Thai vowel or tone mark from its base consonant.
  static List<String> wrapThaiText(String text, int maxColumns) {
    if (maxColumns <= 0) return [text];
    final paragraphs = text.split('\n');
    final lines = <String>[];

    for (final paragraph in paragraphs) {
      final clusters = splitGraphemeClusters(paragraph.trimRight());
      if (clusters.isEmpty) {
        lines.add('');
        continue;
      }

      var index = 0;
      while (index < clusters.length) {
        final remaining = clusters.length - index;
        if (remaining <= maxColumns) {
          lines.add(clusters.sublist(index).join());
          break;
        }

        // Try to find a space near the end of the window for clean word breaks
        var breakAt = index + maxColumns;
        for (var j = breakAt - 1; j > index + (maxColumns ~/ 2); j--) {
          if (clusters[j] == ' ') {
            breakAt = j;
            break;
          }
        }

        lines.add(clusters.sublist(index, breakAt).join().trimRight());
        index = clusters[breakAt] == ' ' ? breakAt + 1 : breakAt;
      }
    }

    return lines.isEmpty ? [''] : lines;
  }

  /// Encodes UTF-8 Thai/ASCII string into TIS-620 / CP874 bytes for legacy
  /// character-mode ESC/POS printers (note: raster mode is preferred for Thai).
  static Uint8List encodeTis620(String text) {
    final normalized = normalizeThaiSequence(text);
    final bytes = <int>[];
    for (final rune in normalized.runes) {
      if (rune <= 0x7F) {
        bytes.add(rune);
      } else if (rune >= 0x0E01 && rune <= 0x0E3A) {
        bytes.add(rune - 0x0E00 + 0xA0);
      } else if (rune >= 0x0E3F && rune <= 0x0E5B) {
        bytes.add(rune - 0x0E00 + 0xA0);
      } else {
        bytes.add(0x3F); // '?' fallback
      }
    }
    return Uint8List.fromList(bytes);
  }
}
