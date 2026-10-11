import 'dart:math';
import '../models/arrow.dart';
import '../models/level.dart';
import '../../core/constants.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  FullBoardGenerator — 100% arrow coverage, solvable by construction
// ═══════════════════════════════════════════════════════════════════════════════
//
//  WHY 100% IS POSSIBLE
//  ─────────────────────
//  An arrow is blocked only by ANOTHER arrow's body on its exit ray. A fully
//  packed board is therefore fine as long as the "blocked-by" graph has no
//  cycle: some arrow (e.g. a head on the border pointing outward) is free, it
//  leaves, which frees the next arrow, and so on.
//
//  ALGORITHM
//  ─────────
//  1. Every arrow's exit ray is a fixed straight line (head + direction), so
//     "A is blocked by B" is simply "B's body touches A's ray". We keep that
//     graph incrementally (blockedBy sets + rayOwners per cell).
//  2. A new arrow / tail extension is accepted ONLY if it keeps the graph
//     acyclic (cheap DFS). So every board we build is solvable by construction.
//  3. Fill: repeatedly start at the most constrained free cell, grow a snake
//     (Warnsdorff-style, so pockets are not stranded), try both ends as the
//     head, accept the first end that keeps the graph acyclic.
//  4. Leftover cells: absorb into an adjacent arrow's tail, else REPAIR —
//     remove 1-3 neighbouring arrows around the hole and re-fill the region.
//  5. Difficulty is MEASURED (longest dependency chain, arrows free on move 1,
//     decoys, average blockers) so callers can generate several candidates
//     and keep the hardest.
//  6. A board with >= [minCoverage] (default 95%) arrow coverage counts as a
//     success; the few holes are returned in [FullBoardResult.emptyCells].
//
//  Pure Dart, deterministic for a given [Random].
// ═══════════════════════════════════════════════════════════════════════════════

const List<int> _kDr = [-1, 1, 0, 0];
const List<int> _kDc = [0, 0, -1, 1];

/// One generated arrow: body cells (head first) and its exit direction.
class FullArrowSpec {
  final List<List<int>> path; // [[row, col], ...] head first
  final ArrowDirection direction;
  FullArrowSpec(this.path, this.direction);
}

/// A (nearly) fully covered board plus its difficulty metrics.
class FullBoardResult {
  final List<FullArrowSpec> arrows;

  /// Cells no arrow covers ([row, col]); empty when coverage is 100%.
  final List<List<int>> emptyCells;

  /// Longest chain of "must leave before" dependencies (= minimum number of
  /// move-waves needed to clear the board). Higher = harder.
  final int chainDepth;

  /// Arrows that can be tapped on the very first move. Lower = harder.
  final int initiallyFree;

  /// "Near-miss" decoys: arrows blocked by exactly ONE arrow but sitting deep
  /// in the chain. They look almost free and waste the player's attention.
  final int decoys;

  /// Average number of arrows blocking an arrow. Higher = harder to read.
  final double avgBlockers;

  FullBoardResult(this.arrows, this.emptyCells, this.chainDepth,
      this.initiallyFree, this.decoys, this.avgBlockers);
}

class FullBoardGenerator {
  /// Returns a board whose arrows cover EVERY cell of [mask], or null if this
  /// attempt could not close all holes (caller retries with another stream).
  static FullBoardResult? generate({
    required int gridSize,
    required Set<String> mask,
    required Random rng,
    required double avgLen,
    required int maxLen,
    required double blockBias,
    double shortFrac = 0.0,
    double longFrac = 0.0,
    double minCoverage = 0.95,
    int repairRounds = 600,
  }) {
    final b = _Board(gridSize, mask);
    _shortFrac = shortFrac;
    _longFrac = longFrac;
    _fill(b, rng, avgLen, maxLen, blockBias, null);

    int rounds = 0;
    while (rounds < repairRounds) {
      final free = b.freeCells();
      if (free.isEmpty) break;
      rounds++;

      final orphan = free[rng.nextInt(free.length)];
      final near = <int>{};
      for (int k = 0; k < 4; k++) {
        final p = b.nb(orphan, k);
        if (p >= 0 && b.body[p] >= 0) near.add(b.body[p]);
      }
      final nearList = near.toList()..shuffle(rng);
      final take = nearList.isEmpty
          ? 0
          : 1 + rng.nextInt(min(3, nearList.length));

      final region = <int>{orphan};
      for (int i = 0; i < take; i++) {
        final id = nearList[i];
        region.addAll(b.arrows[id]!.path);
        b.remove(id);
      }
      for (final c in List<int>.from(region)) {
        for (int k = 0; k < 4; k++) {
          final p = b.nb(c, k);
          if (p >= 0 && b.inMask[p] && b.body[p] < 0) region.add(p);
        }
      }
      _fill(b, rng, avgLen, maxLen, blockBias, region);
    }

    // >= minCoverage counts as success; the holes are reported to the caller.
    final holes = b.freeCells();
    final coverage = 1.0 - holes.length / b.maskCells.length;
    if (coverage < minCoverage) return null;
    return _finish(b, holes);
  }

  // Length-mix knobs for the current generate() call (single-threaded use).
  static double _shortFrac = 0.0;
  static double _longFrac = 0.0;

  /// Maps a (dRow, dCol) unit step to the game's [ArrowDirection].
  static ArrowDirection dirFromDelta(int dr, int dc) {
    for (final d in ArrowDirection.values) {
      final v = d.delta;
      if (v[0] == dr && v[1] == dc) return d;
    }
    throw StateError('No ArrowDirection for delta ($dr,$dc)');
  }

  // ── Fill ───────────────────────────────────────────────────────────────────

  static void _fill(_Board b, Random rng, double avgLen, int maxLen,
      double blockBias, Set<int>? region) {
    final stuck = <int>{};
    int guard = 0;
    while (guard++ < 20000) {
      // Most constrained free cell (fewest free neighbours); random tie-break.
      int seed = -1, bestFn = 99, ties = 0;
      for (final c in b.maskCells) {
        if (b.body[c] >= 0 || stuck.contains(c)) continue;
        if (region != null && !region.contains(c)) continue;
        final fn = b.freeNbCount(c);
        if (fn < bestFn) {
          bestFn = fn;
          seed = c;
          ties = 1;
        } else if (fn == bestFn) {
          ties++;
          if (rng.nextInt(ties) == 0) seed = c;
        }
      }
      if (seed < 0) break;
      if (bestFn == 0) {
        stuck.add(seed);
        continue;
      }

      final len = _sampleLen(rng, avgLen, maxLen);
      var path = _grow(b, seed, len, rng);
      bool placed = path.length >= 2 && _tryPlace(b, path, rng, blockBias);
      for (int t = 0; t < 6 && !placed; t++) {
        path = _grow(b, seed, 2 + rng.nextInt(3), rng);
        placed = path.length >= 2 && _tryPlace(b, path, rng, blockBias);
      }
      if (!placed) stuck.add(seed);
    }
    _absorb(b);
  }

  /// Mixed length distribution: a share of short 2-3 cell arrows (many small
  /// things to scan), a share of very long snakes (hard to trace), and the rest
  /// around [avg].
  static int _sampleLen(Random rng, double avg, int maxLen) {
    final r = rng.nextDouble();
    if (r < _shortFrac) return 2 + rng.nextInt(2); // 2..3
    if (r < _shortFrac + _longFrac) {
      final lo = max(4, (maxLen * 0.6).round());
      return (lo + rng.nextInt(max(1, maxLen - lo + 1))).clamp(2, maxLen);
    }
    final u = 1.0 - rng.nextDouble(); // (0, 1]
    final v = rng.nextDouble();
    final g = sqrt(-2.0 * log(u)) * cos(2 * pi * v);
    return (avg + g * avg * 0.5).round().clamp(2, maxLen);
  }

  /// Warnsdorff-style growth: mostly prefer the neighbour with the fewest free
  /// neighbours (so we never strand pockets), sometimes random (keeps tangle).
  static List<int> _grow(_Board b, int seed, int len, Random rng) {
    final path = <int>[seed];
    final pset = <int>{seed};
    while (path.length < len) {
      final cur = path.last;
      final cands = <List<int>>[]; // [freeNeighbours, tiebreak, cell]
      for (int k = 0; k < 4; k++) {
        final nbc = b.nb(cur, k);
        if (nbc < 0 || !b.inMask[nbc] || b.body[nbc] >= 0) continue;
        if (pset.contains(nbc)) continue;

        // Anti-square: new cell may not touch any path cell except `cur`.
        bool bad = false;
        for (int k2 = 0; k2 < 4; k2++) {
          final p = b.nb(nbc, k2);
          if (p >= 0 && p != cur && pset.contains(p)) {
            bad = true;
            break;
          }
        }
        if (bad) continue;

        int fn = 0;
        for (int k2 = 0; k2 < 4; k2++) {
          final p = b.nb(nbc, k2);
          if (p >= 0 && b.inMask[p] && b.body[p] < 0 && !pset.contains(p)) {
            fn++;
          }
        }
        cands.add([fn, rng.nextInt(1 << 20), nbc]);
      }
      if (cands.isEmpty) break;
      cands.sort((x, y) =>
          x[0] != y[0] ? x[0].compareTo(y[0]) : x[1].compareTo(y[1]));
      final pick = rng.nextDouble() < 0.75
          ? cands[0]
          : cands[rng.nextInt(cands.length)];
      path.add(pick[2]);
      pset.add(pick[2]);
    }
    return path;
  }

  /// Tries both ends as the head (head direction points away from the next
  /// cell). Truncates the tail until an acyclic placement exists.
  static bool _tryPlace(
      _Board b, List<int> path, Random rng, double blockBias) {
    var p = path;
    while (p.length >= 2) {
      final opts = <_Opt>[];
      for (int e = 0; e < 2; e++) {
        final ends = e == 0 ? p : p.reversed.toList();
        final dr = b.rowOf(ends[0]) - b.rowOf(ends[1]);
        final dc = b.colOf(ends[0]) - b.colOf(ends[1]);
        final info = b.canAdd(ends, dr, dc);
        if (info != null) opts.add(_Opt(ends, dr, dc, info));
      }
      if (opts.isNotEmpty) {
        _Opt best;
        if (opts.length > 1 && rng.nextDouble() < blockBias) {
          // Prefer the end whose ray crosses more arrows (more dependencies).
          best = opts[0].info.out.length >= opts[1].info.out.length
              ? opts[0]
              : opts[1];
        } else {
          best = opts[rng.nextInt(opts.length)];
        }
        b.add(best.cells, best.dr, best.dc, best.info);
        return true;
      }
      p = p.sublist(0, p.length - 1);
    }
    return false;
  }

  /// Extend an adjacent arrow's TAIL into each leftover cell (head and
  /// direction never change), when the graph stays acyclic.
  static void _absorb(_Board b) {
    bool changed = true;
    while (changed) {
      changed = false;
      for (final c in b.maskCells) {
        if (b.body[c] >= 0) continue;
        for (int k = 0; k < 4; k++) {
          final nbc = b.nb(c, k);
          if (nbc < 0) continue;
          final id = b.body[nbc];
          if (id < 0) continue;
          if (b.arrows[id]!.path.last != nbc) continue;
          if (b.canExtend(id, c)) {
            b.extend(id, c);
            changed = true;
            break;
          }
        }
      }
    }
  }

  // ── Metrics + export ───────────────────────────────────────────────────────

  /// Layers the dependency graph (Kahn). Also an independent acyclicity check:
  /// returns null if any arrow is never reached (would mean a cycle).
  static FullBoardResult? _finish(_Board b, List<int> holes) {
    final ids = b.arrows.keys.toList()..sort();
    final remaining = <int, int>{};
    final dependents = <int, List<int>>{};
    for (final id in ids) {
      final a = b.arrows[id]!;
      remaining[id] = a.blockedBy.length;
      for (final k in a.blockedBy) {
        dependents.putIfAbsent(k, () => []).add(id);
      }
    }
    final depth = <int, int>{};
    final queue = <int>[];
    int initiallyFree = 0;
    for (final id in ids) {
      if (remaining[id] == 0) {
        depth[id] = 1;
        queue.add(id);
        initiallyFree++;
      }
    }
    int head = 0, chain = 0;
    while (head < queue.length) {
      final id = queue[head++];
      final d = depth[id]!;
      if (d > chain) chain = d;
      for (final j in dependents[id] ?? const <int>[]) {
        depth[j] = max(depth[j] ?? 0, d + 1);
        remaining[j] = remaining[j]! - 1;
        if (remaining[j] == 0) queue.add(j);
      }
    }
    if (queue.length != ids.length) return null; // cycle — must never happen

    int decoys = 0, blockerSum = 0;
    for (final id in ids) {
      final cnt = b.arrows[id]!.blockedBy.length;
      blockerSum += cnt;
      if (cnt == 1 && (depth[id] ?? 0) >= 4) decoys++;
    }

    final specs = <FullArrowSpec>[];
    for (final id in ids) {
      final a = b.arrows[id]!;
      specs.add(FullArrowSpec(
        a.path.map((c) => [b.rowOf(c), b.colOf(c)]).toList(),
        dirFromDelta(a.dr, a.dc),
      ));
    }
    return FullBoardResult(
      specs,
      holes.map((c) => [b.rowOf(c), b.colOf(c)]).toList(),
      chain,
      initiallyFree,
      decoys,
      ids.isEmpty ? 0.0 : blockerSum / ids.length,
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Internal board model
// ═══════════════════════════════════════════════════════════════════════════════

class _Arrow {
  final List<int> path; // cell indices, [0] = head
  final int dr, dc; // exit direction
  final List<int> ray; // cells from head to the grid edge
  final Set<int> blockedBy = <int>{};
  _Arrow(this.path, this.dr, this.dc, this.ray);
}

class _AddInfo {
  final List<int> ray;
  final Set<int> out; // arrows that will block the new arrow
  final Set<int> inn; // arrows the new arrow will block
  _AddInfo(this.ray, this.out, this.inn);
}

class _Opt {
  final List<int> cells;
  final int dr, dc;
  final _AddInfo info;
  _Opt(this.cells, this.dr, this.dc, this.info);
}

class _Board {
  final int n;
  final List<bool> inMask;
  final List<int> maskCells = <int>[];
  final List<int> body; // arrow id per cell, -1 = free
  final List<Set<int>?> rayOwners; // arrows whose exit ray passes the cell
  final Map<int, _Arrow> arrows = <int, _Arrow>{};
  int nextId = 0;

  _Board(this.n, Set<String> mask)
      : inMask = List<bool>.filled(n * n, false),
        body = List<int>.filled(n * n, -1),
        rayOwners = List<Set<int>?>.filled(n * n, null) {
    for (final k in mask) {
      final comma = k.indexOf(',');
      final r = int.parse(k.substring(0, comma));
      final c = int.parse(k.substring(comma + 1));
      final idx = r * n + c;
      inMask[idx] = true;
      maskCells.add(idx);
    }
  }

  int rowOf(int cell) => cell ~/ n;
  int colOf(int cell) => cell % n;

  /// Neighbour of [cell] in direction k, or -1 when it falls off the grid.
  int nb(int cell, int k) {
    final r = cell ~/ n + _kDr[k];
    final c = cell % n + _kDc[k];
    if (r < 0 || r >= n || c < 0 || c >= n) return -1;
    return r * n + c;
  }

  int freeNbCount(int cell) {
    int fn = 0;
    for (int k = 0; k < 4; k++) {
      final p = nb(cell, k);
      if (p >= 0 && inMask[p] && body[p] < 0) fn++;
    }
    return fn;
  }

  List<int> freeCells() {
    final out = <int>[];
    for (final c in maskCells) {
      if (body[c] < 0) out.add(c);
    }
    return out;
  }

  List<int> _ray(int head, int dr, int dc) {
    final out = <int>[];
    int r = head ~/ n + dr, c = head % n + dc;
    while (r >= 0 && r < n && c >= 0 && c < n) {
      out.add(r * n + c);
      r += dr;
      c += dc;
    }
    return out;
  }

  /// True if some arrow in [targets] is reachable from [start] by following
  /// "blocked-by" edges.
  bool _reaches(Set<int> start, Set<int> targets) {
    if (targets.isEmpty) return false;
    final seen = <int>{};
    final stack = start.toList();
    while (stack.isNotEmpty) {
      final a = stack.removeLast();
      if (!seen.add(a)) continue;
      if (targets.contains(a)) return true;
      final node = arrows[a];
      if (node != null) stack.addAll(node.blockedBy);
    }
    return false;
  }

  /// Checks whether a new arrow (body [path], head first, exiting along
  /// (dr, dc)) can be added without creating a dependency cycle.
  _AddInfo? canAdd(List<int> path, int dr, int dc) {
    final ray = _ray(path[0], dr, dc);
    final pset = path.toSet();
    final out = <int>{};
    for (final c in ray) {
      if (pset.contains(c)) return null; // own body on own ray: keep visuals clean
      final o = body[c];
      if (o >= 0) out.add(o);
    }
    final inn = <int>{};
    for (final c in path) {
      final s = rayOwners[c];
      if (s != null) inn.addAll(s);
    }
    if (out.isNotEmpty && inn.isNotEmpty) {
      for (final o in out) {
        if (inn.contains(o)) return null; // 2-cycle
      }
      if (_reaches(out, inn)) return null;
    }
    return _AddInfo(ray, out, inn);
  }

  int add(List<int> path, int dr, int dc, _AddInfo info) {
    final id = nextId++;
    final a = _Arrow(List<int>.from(path), dr, dc, info.ray);
    a.blockedBy.addAll(info.out);
    arrows[id] = a;
    for (final c in path) {
      body[c] = id;
    }
    for (final c in info.ray) {
      (rayOwners[c] ??= <int>{}).add(id);
    }
    for (final j in info.inn) {
      arrows[j]!.blockedBy.add(id);
    }
    return id;
  }

  void remove(int id) {
    final a = arrows.remove(id)!;
    for (final c in a.path) {
      body[c] = -1;
    }
    for (final c in a.ray) {
      rayOwners[c]?.remove(id);
    }
    for (final o in arrows.values) {
      o.blockedBy.remove(id);
    }
  }

  /// Can arrow [id] grow its tail into free cell [cell]? (Caller guarantees
  /// [cell] is orthogonally adjacent to the tail.)
  bool canExtend(int id, int cell) {
    final a = arrows[id]!;
    final tail = a.path.last;
    for (final c in a.ray) {
      if (c == cell) return false; // never put own body on own exit ray
    }
    // Anti-loop: new cell may not touch other body cells of this arrow.
    for (int k = 0; k < 4; k++) {
      final p = nb(cell, k);
      if (p >= 0 && p != tail && a.path.contains(p)) return false;
    }
    final s = rayOwners[cell];
    if (s == null || s.isEmpty) return true;
    final inn = Set<int>.from(s)..remove(id); // own ray is transparent to self
    if (inn.isEmpty) return true;
    return !_reaches(a.blockedBy, inn);
  }

  void extend(int id, int cell) {
    final a = arrows[id]!;
    a.path.add(cell);
    body[cell] = id;
    final s = rayOwners[cell];
    if (s != null) {
      for (final j in s) {
        if (j != id) arrows[j]!.blockedBy.add(id);
      }
    }
  }
}
