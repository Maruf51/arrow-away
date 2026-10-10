import 'package:arrow_escape/game/components/arrow_component.dart';
import 'package:flutter_test/flutter_test.dart';

/// The release-wave (grid dot pop) must fire ONE dot at a time, at the exact
/// moment the escaping arrow's tail vacates that dot's cell — the previous
/// implementation compared a *decreasing* remaining-distance against
/// *ascending* thresholds, which satisfied every remaining threshold in a
/// single frame and made all dots burst at once when the arrow escaped.
void main() {
  // Exit track: 10 extension cells ahead of the head, then a 4-cell body.
  // One cell = 10 px, so trackDist[i] = i * 10.
  const extCount = 10;
  const bodyCells = 4;
  const cellPx = 10.0;
  final trackDist = [
    for (int i = 0; i < extCount + bodyCells; i++) i * cellPx,
  ];
  final tailDist = trackDist[extCount + bodyCells - 1]; // 130 px

  List<double> thresholds() => ArrowComponent.releaseWaveThresholds(
        trackDist: trackDist,
        extCount: extCount,
        bodyCells: bodyCells,
      );

  test('thresholds are strictly ascending: tail cell first, head cell last',
      () {
    final t = thresholds();

    expect(t, hasLength(bodyCells));
    expect(t.first, 0.0, reason: 'tail cell is vacated the moment it moves');
    // Head cell vacated only once the whole body has slid past it.
    expect(t.last, closeTo((tailDist - trackDist[extCount]) / tailDist, 1e-9));
    for (int i = 1; i < t.length; i++) {
      expect(t[i], greaterThan(t[i - 1]),
          reason: 'threshold $i must come after ${i - 1}');
    }
  });

  test('each threshold equals the progress where the tail passes its cell', () {
    final t = thresholds();
    for (int i = 0; i < bodyCells; i++) {
      // Body cell i is stored reversed (firing order), so cell index is
      // bodyCells - 1 - i.
      final cell = bodyCells - 1 - i;
      final arc = trackDist[extCount + cell];
      expect(t[i], closeTo((tailDist - arc) / tailDist, 1e-9),
          reason: 'threshold for body cell $cell');
    }
  });

  test('a forward cursor pops exactly one dot per crossing, all exactly once',
      () {
    final t = thresholds();
    final poppedAt = <int, double>{}; // body cell -> progress at which it popped
    int cursor = 0;

    // Simulate ArrowComponent.update() over the whole exit.
    const frames = 200;
    for (int f = 0; f <= frames; f++) {
      final progress = f / frames;
      final before = cursor;
      while (cursor < t.length && progress >= t[cursor]) {
        poppedAt[bodyCells - 1 - cursor] = progress;
        cursor++;
      }
      // Never more than one dot per frame for a 4-cell body at this rate,
      // and never a dot that has not been vacated yet.
      expect(cursor - before, lessThanOrEqualTo(1),
          reason: 'frame $f popped more than one dot');
      expect(poppedAt.length, lessThanOrEqualTo(f + 1));
    }

    expect(poppedAt, hasLength(bodyCells), reason: 'every cell pops exactly once');
    for (final entry in poppedAt.entries) {
      final arc = trackDist[extCount + entry.key];
      final expected = (tailDist - arc) / tailDist;
      expect(entry.value, greaterThanOrEqualTo(expected - 1e-9),
          reason: 'cell ${entry.key} popped before the tail reached it');
    }
    // Order of firing: tail cell (3) first, head cell (0) last.
    final order = poppedAt.entries.toList()
      ..sort((a, b) => a.value.compareTo(b.value));
    expect(order.map((e) => e.key).toList(), [3, 2, 1, 0]);
  });

  test('a single-cell arrow pops its only dot immediately', () {
    final t = ArrowComponent.releaseWaveThresholds(
      trackDist: const [0.0, 10.0, 20.0, 30.0],
      extCount: 3,
      bodyCells: 1,
    );
    expect(t, [0.0]);
  });
}
