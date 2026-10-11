import 'package:flutter_test/flutter_test.dart';
import 'package:arrow_escape/data/level_generator/level_generator_v2.dart';

void main() {
  test('sandbox generation honors the selected board size and bounds', () {
    const selectedSize = 12;
    final level = LevelGeneratorV2.generateLevel(
      4,
      gridSizeOverride: selectedSize,
    );

    expect(level.gridSize, selectedSize);
    for (final cell in level.mask) {
      final coordinates = cell.split(',').map(int.parse).toList();
      expect(coordinates[0], inInclusiveRange(0, selectedSize - 1));
      expect(coordinates[1], inInclusiveRange(0, selectedSize - 1));
    }
    for (final arrow in level.arrows) {
      for (final point in arrow.path) {
        expect(point[0], inInclusiveRange(0, selectedSize - 1));
        expect(point[1], inInclusiveRange(0, selectedSize - 1));
      }
    }
  });
}