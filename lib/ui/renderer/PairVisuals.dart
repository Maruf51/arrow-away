import 'package:flutter/material.dart';
import '../../core/app_colors.dart';

/// Three silhouettes, chosen for readability at very small sizes.
/// Ring (hollow circle), Triangle (pointed apex), Diamond (rotated square).
/// 12 palette colors × 3 glyphs = 36 distinct pair identities.
enum PairGlyph { ring, triangle, diamond }

class PairVisual {
  final Color color;
  final PairGlyph glyph;
  const PairVisual(this.color, this.glyph);
}

class PairVisuals {
  static int get glyphCount => PairGlyph.values.length;
  static int get colorCount => AppColors.pairColorCount;
  static int get maxDistinctPairs => colorCount * glyphCount;

  /// Decodes a colorGroup id into a unique (color, glyph) combination.
  /// Colors cycle first; when a color would repeat, the glyph advances.
  static PairVisual resolve(int groupId) {
    final c = AppColors.getGroupColor(groupId % colorCount);
    final g = PairGlyph.values[(groupId ~/ colorCount) % glyphCount];
    return PairVisual(c, g);
  }
}