import 'package:arrow_escape/data/models/arrow.dart';
import 'package:arrow_escape/game/components/arrow_component.dart';
import 'package:flutter_test/flutter_test.dart';

/// The exit track used to be padded with `gridSize + 2` cells ahead of the
/// head, so every arrow kept flying across empty space long after it had
/// left the board. On the LAST arrow of a level that is pure waiting time
/// before the win screen (2+ seconds on 27×27+ boards).
///
/// [ArrowComponent.straightExtensionCells] now only pads far enough for the
/// head to stand one full cell outside the grid plus a one-cell buffer for
/// the tail — these tests pin that down.
void main() {
  int ext(List<int> head, ArrowDirection dir, {int gridSize = 10}) =>
      ArrowComponent.straightExtensionCells(
        head: head,
        delta: dir.delta,
        gridSize: gridSize,
      );

  /// Signed grid coordinate of the head after [steps] cells in [dir].
  /// Returns (line, isHorizontal): line is row for vertical, col for
  /// horizontal directions.
  (int, bool) afterSteps(List<int> head, ArrowDirection dir, int steps) {
    final d = dir.delta;
    if (d[0] != 0) return (head[0] + d[0] * steps, false);
    return (head[1] + d[1] * steps, true);
  }

  /// True when [head]'s coordinate sits at least one full cell outside the
  /// grid (centre beyond the edge), i.e. the arrow body is completely clear.
  bool isFullCellOutside(int line, int gridSize, ArrowDirection dir) {
    switch (dir) {
      case ArrowDirection.up:
      case ArrowDirection.left:
        return line <= -2;
      case ArrowDirection.down:
      case ArrowDirection.right:
        return line >= gridSize + 1;
    }
  }

  test('head at the board edge needs only 2 cells (was gridSize + 2)', () {
    expect(ext([0, 5], ArrowDirection.up), 2);
    expect(ext([9, 5], ArrowDirection.down), 2);
    expect(ext([5, 9], ArrowDirection.right), 2);
    expect(ext([5, 0], ArrowDirection.left), 2);

    // Even on the biggest boards in the game (30×30).
    expect(ext([0, 15], ArrowDirection.up, gridSize: 30), 2);
    expect(ext([15, 29], ArrowDirection.right, gridSize: 30), 2);
  });

  test('head deep inside: exactly cells-to-clear + 1, never gridSize + 2', () {
    // 10×10, head at row 2 pointing up → r+1 = 3 cells to clear, +1 buffer.
    expect(ext([2, 5], ArrowDirection.up), 4);
    // Head at row 8 pointing down → 10-8 = 2 cells to clear, +1 buffer.
    expect(ext([8, 5], ArrowDirection.down), 3);
    // 30×30, head at col 1 pointing right → 29 + 1 (old code: 32).
    expect(ext([5, 1], ArrowDirection.right, gridSize: 30), 30);
    expect(ext([5, 1], ArrowDirection.right, gridSize: 30),
        lessThan(30 + 2));
  });

  test('extension is minimal: clears the board and wastes no travel', () {
    const g = 10;
    const heads = [
      [0, 0],
      [0, 9],
      [9, 0],
      [9, 9],
      [3, 7],
      [5, 5],
      [1, 8],
      [8, 1],
    ];

    for (final dir in ArrowDirection.values) {
      for (final head in heads) {
        final e = ext(head, dir, gridSize: g);

        // (a) After the extension the head stands a full cell outside the
        //     board — the arrow (and its tail, which ends at the same point)
        //     has completely escaped.
        final (line, _) = afterSteps(head, dir, e);
        expect(isFullCellOutside(line, g, dir), isTrue,
            reason: '$head/$dir must clear the board in $e cells');

        // (b) One cell less would NOT be a full cell outside — i.e. no
        //     unnecessary off-board travel remains.
        final (lineBefore, _) = afterSteps(head, dir, e - 1);
        expect(isFullCellOutside(lineBefore, g, dir), isFalse,
            reason: '$head/$dir wastes travel (ext=$e)');

        // (c) Never worse than the old gridSize + 2 padding.
        expect(e, lessThanOrEqualTo(g + 2));
      }
    }
  });
}
