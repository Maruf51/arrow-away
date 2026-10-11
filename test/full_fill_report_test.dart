import 'package:flutter_test/flutter_test.dart';

import '../lib/core/constants.dart';
import '../lib/data/level_generator/level_generator_v2.dart';
import '../lib/data/models/level.dart';

/// Difficulty metrics computed INDEPENDENTLY of the generator, straight from
/// the finished LevelModel, so the numbers can be trusted.
///
///  coverage     arrow-body cells / mask cells   (target: 100% on normal levels)
///  chain        longest "must leave first" dependency chain (higher = harder)
///  free         arrows tappable on the first move            (lower  = harder)
///  pairs        colour pairs
///  fill%        (arrow cells + colored deflector cells) / mask  (target: >= 95%)
///  chain        longest dependency chain on STRAIGHT rays (deflectors ignored)
///  dots         colored deflector dots (0 before level 21)
///  neutral      leftover neutral dots (look empty; keep few)
class _M {
  final double coverage;
  final int arrows, chain, free, pairs, orphans;

  /// Colored deflector dots (the visible, gameplay-relevant kind).
  final int coloredDots;

  /// Pairs where at least one partner could be tapped on move one (target: 0).
  final int pairsFree;

  /// Smallest dependency depth among all paired arrows (higher = pairs are
  /// gated behind more clearing). 0 when the level has no pairs.
  final int pairMinDepth;
  _M(this.coverage, this.arrows, this.chain, this.free, this.pairs,
      this.orphans, this.pairsFree, this.pairMinDepth, this.coloredDots);
}

/// True if arrow [i] is blocked on move one, tracing its ray THROUGH deflector
/// dots exactly like the game does (dot turns the ray; revisiting a cell = blocked).
bool _blockedAtStart(LevelModel l, int i, Map<int, int> owner,
    Map<int, List<int>> dots) {
  final n = l.gridSize;
  final a = l.arrows[i];
  var d = a.direction.delta;
  int r = a.path[0][0] + d[0], c = a.path[0][1] + d[1];
  final seen = <int>{};
  while (r >= 0 && r < n && c >= 0 && c < n) {
    final k = r * n + c;
    if (!seen.add(k)) return true;
    final dot = dots[k];
    if (dot != null) {
      d = dot;
    } else {
      final o = owner[k];
      if (o != null && o != i) return true;
    }
    r += d[0];
    c += d[1];
  }
  return false;
}

_M _measure(LevelModel l) {
  final n = l.gridSize;
  final owner = <int, int>{};
  for (int i = 0; i < l.arrows.length; i++) {
    for (final pt in l.arrows[i].path) {
      owner[pt[0] * n + pt[1]] = i;
    }
  }

  // blockedBy[i] = arrows whose body touches arrow i's exit ray.
  final blockedBy = List.generate(l.arrows.length, (_) => <int>{});
  for (int i = 0; i < l.arrows.length; i++) {
    final a = l.arrows[i];
    final d = a.direction.delta;
    int r = a.path[0][0] + d[0], c = a.path[0][1] + d[1];
    while (r >= 0 && r < n && c >= 0 && c < n) {
      final o = owner[r * n + c];
      if (o != null && o != i) blockedBy[i].add(o);
      r += d[0];
      c += d[1];
    }
  }

  // Layer the graph (Kahn). chain == -1 means a cycle (must never happen).
  final remaining = blockedBy.map((s) => s.length).toList();
  final dependents = List.generate(l.arrows.length, (_) => <int>[]);
  for (int i = 0; i < l.arrows.length; i++) {
    for (final k in blockedBy[i]) {
      dependents[k].add(i);
    }
  }
  final depth = List<int>.filled(l.arrows.length, 0);
  final queue = <int>[];
  int free = 0;
  for (int i = 0; i < l.arrows.length; i++) {
    if (remaining[i] == 0) {
      depth[i] = 1;
      queue.add(i);
      free++;
    }
  }
  int h = 0, chain = 0;
  while (h < queue.length) {
    final i = queue[h++];
    if (depth[i] > chain) chain = depth[i];
    for (final j in dependents[i]) {
      if (depth[j] < depth[i] + 1) depth[j] = depth[i] + 1;
      if (--remaining[j] == 0) queue.add(j);
    }
  }
  if (queue.length != l.arrows.length) chain = -1;

  final bodyCells = owner.length;
  final pairs = l.arrows.where((a) => a.colorGroup != null).length ~/ 2;

  // Colored dots -> ray direction they force (up/down/left/right).
  final dotDir = <int, List<int>>{};
  const deltas = {
    'up': [-1, 0], 'down': [1, 0], 'left': [0, -1], 'right': [0, 1],
  };
  for (final od in l.orphanDots) {
    final dd = deltas[od.type.name];
    if (dd != null) dotDir[od.row * n + od.col] = dd;
  }

  // Pair hardness: a pair is "free" if either partner can leave on move one.
  final byGroup = <int, List<int>>{};
  for (int i = 0; i < l.arrows.length; i++) {
    final g = l.arrows[i].colorGroup;
    if (g != null) byGroup.putIfAbsent(g, () => []).add(i);
  }
  int pairsFree = 0;
  int pairMinDepth = 0;
  for (final members in byGroup.values) {
    if (members.any((i) => !_blockedAtStart(l, i, owner, dotDir))) pairsFree++;
    final d = members.map((i) => depth[i]).reduce((a, b) => a < b ? a : b);
    if (pairMinDepth == 0 || d < pairMinDepth) pairMinDepth = d;
  }
  final colored = l.orphanDots.where((d) => d.type.name != 'neutral').length;
  final neutral = l.orphanDots.length - colored;
  // "Filled" = arrow bodies + visible colored deflectors (neutral dots look empty).
  return _M((bodyCells + colored) / l.mask.length, l.arrows.length, chain, free,
      pairs, neutral, pairsFree, pairMinDepth, colored);
}

void main() {
  // Sample across the whole progression; add/remove levels as you like.
  const sample = [4, 5, 10, 16, 25, 40, 60, 100, 150, 200, 250, 300, 350, 400, 450, 500];

  test('full-board report', () {
    // ignore: avoid_print
    print('level type    grid  arrows  fill%  chain  free pairs pFree pDepth  dots neutral    ms');
    for (final lv in sample) {
      final sw = Stopwatch()..start();
      final level = LevelGeneratorV2.generateLevel(lv);
      sw.stop();
      final type = AppConstants.levelTypeFor(lv);
      final m = _measure(level);

      // ignore: avoid_print
      print('${lv.toString().padLeft(5)} ${type.name.padRight(7)} '
          '${level.gridSize.toString().padLeft(4)} '
          '${m.arrows.toString().padLeft(6)} '
          '${(m.coverage * 100).toStringAsFixed(1).padLeft(6)} '
          '${m.chain.toString().padLeft(6)} '
          '${m.free.toString().padLeft(5)} '
          '${m.pairs.toString().padLeft(5)} '
          '${m.pairsFree.toString().padLeft(5)} '
          '${m.pairMinDepth.toString().padLeft(6)} '
          '${m.coloredDots.toString().padLeft(5)} '
          '${m.orphans.toString().padLeft(7)} '
          '${sw.elapsedMilliseconds.toString().padLeft(5)}');

      // Hard requirements for every level.
      expect(m.chain, greaterThan(0), reason: 'level $lv has a dependency cycle');
      expect(level.solutionOrder, isNotEmpty, reason: 'level $lv has no solution');

      // No pair may be tappable on move one (that was the "free pair" bug).
      // Only enforced for levels the full-board generator is expected to own.
      if (type == LevelType.normal && lv != 213 && lv != 395 && lv != 437) {
        expect(m.pairsFree, equals(0),
            reason: 'level $lv has a pair that is free on move one');
      }

      // Full-board requirement: normal levels must be >= 95% filled
      // (arrow bodies + colored deflectors). Boss/God and the 3 hand-tuned
      // levels are allowed to fall short.
      if (type == LevelType.normal && lv != 213 && lv != 395 && lv != 437) {
        expect(m.coverage, greaterThanOrEqualTo(0.95),
            reason: 'level $lv is under 95% filled');
        // No colored deflectors in the gentle intro levels (strict gate: 21+).
        if (lv <= 20) {
          expect(m.coloredDots, equals(0),
              reason: 'level $lv must not have deflectors yet');
        }
      }
    }
  }, timeout: const Timeout(Duration(minutes: 30)));

  test('deterministic: same level number gives identical board', () {
    // Normal levels only: Boss/God pick masks via a session-level shape-history
    // queue (pre-existing behaviour), so repeating them in one session differs.
    final normals = const [5, 8, 25, 100, 250, 401]
        .where((lv) => AppConstants.levelTypeFor(lv) == LevelType.normal);
    for (final lv in normals) {
      String sig(LevelModel l) => l.arrows
          .map((a) => '${a.path}${a.direction.name}${a.colorGroup}')
          .join('|');
      expect(sig(LevelGeneratorV2.generateLevel(lv)),
          equals(sig(LevelGeneratorV2.generateLevel(lv))),
          reason: 'level $lv is not deterministic');
    }
  }, timeout: const Timeout(Duration(minutes: 10)));
}
