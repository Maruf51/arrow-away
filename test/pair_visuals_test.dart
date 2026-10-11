import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_escape/core/app_colors.dart';
import 'package:arrow_escape/ui/renderer/PairVisuals.dart';

void main() {
  test('all supported pair ids resolve to unique color and glyph tuples', () {
    final identities = <String>{};

    for (var groupId = 0; groupId < PairVisuals.maxDistinctPairs; groupId++) {
      final visual = PairVisuals.resolve(groupId);
      final identity = '${visual.color.toARGB32()}:${visual.glyph.name}';
      expect(identities.add(identity), isTrue,
          reason: 'Pair id $groupId reused $identity');
    }

    expect(identities, hasLength(PairVisuals.maxDistinctPairs));
  });

  test('identity wraps after maxDistinctPairs', () {
    final first = PairVisuals.resolve(0);
    final wrapped = PairVisuals.resolve(PairVisuals.maxDistinctPairs);

    expect(wrapped.color, first.color);
    expect(wrapped.glyph, first.glyph);
  });

  test('glyph advances after each full color rotation', () {
    final colorCount = PairVisuals.colorCount;
    expect(colorCount, AppColors.pairColorCount);
    expect(PairGlyph.values, [PairGlyph.ring, PairGlyph.triangle, PairGlyph.diamond]);
    expect(PairVisuals.maxDistinctPairs, 36);

    final firstCycle = [
      for (var id = 0; id < 3; id++) PairVisuals.resolve(id),
    ];
    expect(firstCycle.every((visual) => visual.glyph == PairGlyph.ring), isTrue);
    expect(firstCycle.map((visual) => visual.color).toSet(), hasLength(3));

    for (var offset = 0; offset < 3; offset++) {
      expect(PairVisuals.resolve(12 + offset).glyph, PairGlyph.triangle);
      expect(PairVisuals.resolve(24 + offset).glyph, PairGlyph.diamond);
    }
  });
}
