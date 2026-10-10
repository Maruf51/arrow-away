import 'package:arrow_escape/game/components/grid_component.dart';
import 'package:flame/components.dart';
import 'package:flutter_test/flutter_test.dart';

/// Tap resolution must pick the arrow a player actually touched.
///
/// Flame's default delivery rule is "top-most component containing the
/// point", i.e. the last-added arrow whenever two expanded hit boxes
/// overlap — which made taps land on a neighbouring arrow, or get swallowed
/// entirely. GridComponent instead resolves the CLOSEST arrow.
void main() {
  const cell = 40.0;

  // Arrow A: two horizontal cells at (0,0)-(0,1).
  // Arrow B: one cell at (0,2) — directly neighbouring A.
  // Arrow C: one cell at (0,4) — separated from A/B by an empty column.
  final pathA = [
    [0, 0],
    [0, 1],
  ];
  final pathB = [
    [0, 2],
  ];
  final pathC = [
    [0, 4],
  ];
  final paths = [
    pathA,
    pathB,
    pathC,
  ];

  test('a tap inside a body cell picks that arrow', () {
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(0.5 * cell, 0.5 * cell), cell),
      0,
    );
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(2.5 * cell, 0.5 * cell), cell),
      1,
    );
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(4.5 * cell, 0.5 * cell), cell),
      2,
    );
  });

  test('overlapping hit boxes resolve to the CLOSEST arrow, not the last one',
      () {
    // Just inside B's cell but only 0.1 cell away from A's edge: both arrows
    // claim this point, the closer one (B) must win.
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(2.1 * cell, 0.5 * cell), cell),
      1,
    );
    // Mirror case: 0.1 cell inside A's last cell — A must win over B.
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(1.9 * cell, 0.5 * cell), cell),
      0,
    );
  });

  test('a tap in the gap picks the nearer arrow when within reach', () {
    // Column 3 is empty; A ends at x = 2c, B starts at x = 3c... A is at
    // columns 0-1, B at column 2, so the gap after B starts at x = 3c.
    // 3.3c is 0.3 cell from B (within the 0.35 reach) and 1.3 from A.
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(3.3 * cell, 0.5 * cell), cell),
      1,
    );
    // 2.7c is 0.3 cell from B as well (inside the empty column 2? no —
    // column 2 is B's cell, so 2.7c is INSIDE B).
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(2.7 * cell, 0.5 * cell), cell),
      1,
    );
  });

  test('a tap far from every arrow is ignored', () {
    // Way beyond the 0.35-cell reach of all three arrows.
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(6.0 * cell, 5.0 * cell), cell),
      -1,
    );
    // Between A/B (columns 0-2) and C (column 4): column 3 is empty, and its
    // middle is 0.5 cell from both — outside the reach, so nothing fires.
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(3.5 * cell, 0.5 * cell), cell),
      -1,
    );
  });

  test('empty arrow list never resolves', () {
    expect(
      GridComponent.resolveArrowIndex([], Vector2(cell, cell), cell),
      -1,
    );
  });

  test('exact tie between touching cells is resolved deterministically', () {
    // Point exactly on the shared edge of A's last cell and B's cell:
    // distance 0 to both; centre distance is equal too, so the first arrow
    // in list order wins (stable, never random).
    expect(
      GridComponent.resolveArrowIndex(paths, Vector2(2.0 * cell, 0.5 * cell), cell),
      0,
    );
  });
}
