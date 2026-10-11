import 'dart:collection';
import 'dart:math';
import 'dart:io';
import 'dart:typed_data';
import '../models/arrow.dart';
import '../models/level.dart';
import '../../core/constants.dart';
import 'solver.dart';
import 'mask_generator_v2.dart';
import 'full_board_generator.dart';

// ═══════════════════════════════════════════════════════════════════════════════
//  Arrow Puzzle Level Generator — V2
// ═══════════════════════════════════════════════════════════════════════════════
//
//  KEY IMPROVEMENTS OVER V1:
//  ─────────────────────────────────────────────────────────────────────────────
//  • STRICT MECHANIC GATE: Zero color pairs and zero direction dots for levels
//    4–15 across ALL level types (including Boss at level 7). Teaches pure arrow
//    mechanics first.
//
//  • IMPROVED TANGLE FACTOR: Starts at 0.20 from level 4 (not 0.0). Early
//    levels already look like real puzzles. Ramps to 1.0 at level 300+.
//    Boss gets +0.15 boost, God gets +0.25 boost.
//
//  • 4-TIER LENGTH DISTRIBUTION: Adds an explicit Short tier (10% weight,
//    length=2) alongside VeryLong(35%), Long(30%), Medium(25%). 2-cell arrows
//    are actually the most annoying blockers — they fill corridors without
//    taking much visual space.
//
//  • SMARTER PAIR COUNTS: More color pairs appear earlier after the gate lifts
//    at level 16. Boss always ≥ 1 pair from first Boss after gate. God always
//    ≥ 2 pairs.
//
//  • FASTER DOT RAMP: Direction-changing dots appear sooner and more densely,
//    making mid-levels meaningfully harder than early levels.
//
//  • REDUCED PHASE-2 DOMINANCE: Phase 2 (2-cell fill sweep) is capped at a
//    fill-rate that scales with level number. Early levels don't become 80%
//    trivially-fireable 2-cell arrows.
//
//  • SHAPE NO-REPEAT RULE: Tracks last 5 Boss and last 5 God shapes used
//    independently. Prevents the same shape from appearing in consecutive
//    Boss/God levels.
//
//  • EXPANDED SHAPE LIBRARY: Uses MaskGeneratorV2 with 25+ Boss shapes and
//    24+ God shapes.
//
//  • SELF-AVOIDING PATH ASSERTIONS: Debug builds verify no cell repeats and no
//    180° U-turns in any placed arrow body.
//
//  PRESERVED FROM V1:
//  ─────────────────────────────────────────────────────────────────────────────
//  • Level schedule: Boss every 3rd, God every 7th in the 7-cycle.
//  • Grid sizes:     10 → 40 as implemented in AppConstants.
//  • Tutorial canvas: 10×10.
//  • Backwards construction guarantees solvability by design.
//  • Greedy solver for large grids (>20), DFS for small grids (≤20).
//  • Anti-square / closed-loop prevention in _growPath.
//  • Greedy-adjacent Phase 2b sweep.
//  • Orphan absorption.
//  • ColorLock mutual-exit validation.
//  • Tutorial levels hand-authored with STRAIGHT arrows only.
// ═══════════════════════════════════════════════════════════════════════════════

class LevelGeneratorV2 {
  // ── Shape history (no-repeat rule) ──────────────────────────────────────────
  // Tracks last 5 Boss and last 5 God shape names independently.
  // Persists for the duration of the generation session (static).
  static final ListQueue<String> _bossShapeHistory = ListQueue<String>();
  static final ListQueue<String> _godShapeHistory  = ListQueue<String>();
  static const int _shapeHistoryMaxLen = 5;

  // ── Entry point ─────────────────────────────────────────────────────────────

  /// Generate a level. Seeded by levelNumber for determinism.
  static LevelModel generateLevel(
    int levelNumber, {
    int? gridSizeOverride,
    int? seedOverride,
    bool quickGeneration = false,
  }) {
    // ── Tutorial levels — hand-authored, straight arrows only ─────────────────
    // ┌─────────────────────────────────────────────────────────────────────────┐
    // │  TUTORIAL RULE: All arrow paths in levels 1–3 are STRAIGHT (no bends). │
    // │  No color pairs (except Level 2), no direction dots (except Level 3).  │
    // │  Bent paths via _growPath() are used only from level 4 onward.         │
    // └─────────────────────────────────────────────────────────────────────────┘
    if (levelNumber <= 3 && gridSizeOverride != null && gridSizeOverride != 10) {
      return generateLevel(
        4,
        gridSizeOverride: gridSizeOverride,
        seedOverride: seedOverride,
        quickGeneration: quickGeneration,
      )
          .copyWith(levelNumber: levelNumber);
    }
    if (levelNumber == 1) return _buildTutorial1();
    if (levelNumber == 2) return _buildTutorial2();
    if (levelNumber == 3) return _buildTutorial3();

    final type    = AppConstants.levelTypeFor(levelNumber);
    int gridSize  = gridSizeOverride ?? AppConstants.gridSizeForLevel(levelNumber);

    // Specific overrides from V1 retained
    if (gridSizeOverride == null) {
      if (levelNumber == 213) gridSize = 32;
      if (levelNumber == 395) gridSize = 35;
      if (levelNumber == 437) gridSize = 36;
    }

    final seed = seedOverride ?? levelNumber * 7919 + 314159;
    final rng  = Random(seed);

    final maskShape = _shapeFor(type, rng, levelNumber);
    final mask      = MaskGeneratorV2.shapeByName(maskShape.name, gridSize, rng);
    final params    = _paramsFor(levelNumber, type, gridSize, mask);

    // ── Full-board generator (100% arrow coverage) ────────────────────────────
    // Tried first. If it cannot produce a verified level, the legacy pipeline
    // below runs exactly as before.
    if (_useFullFill(levelNumber, type)) {
      final full = _generateFullBoard(
        levelNumber: levelNumber,
        gridSize: gridSize,
        mask: mask,
        type: type,
        maskShape: maskShape,
        seedOverride: seedOverride,
        quickGeneration: quickGeneration,
      );
      if (full != null) return full;
    }

    LevelModel? level;

    final bool isLargeGrid = gridSize > 20;
    final int maxAttempts = quickGeneration
      ? 8
      : isLargeGrid
        ? (type == LevelType.normal ? 80 : 120)
        : 80;

    for (int attempt = 0; attempt < maxAttempts && level == null; attempt++) {
      level = _attempt(
        levelNumber: levelNumber,
        gridSize: gridSize,
        mask: mask,
        params: params,
        type: type,
        rng: rng,
        maskShape: maskShape,
        attempt: attempt,
      );
    }

    // Final strict DFS verification for small grids only.
    if (level != null && !isLargeGrid) {
      final strictSolution = LevelSolver.solve(level, 6000);
      if (strictSolution == null) {
        level = null;
      } else {
        level = level.copyWith(solutionOrder: strictSolution);
      }
    }

    return level ?? _fallback(levelNumber, gridSize, mask, type);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  FULL-BOARD MODE — every mask cell is an arrow body, solvable by design
  // ═══════════════════════════════════════════════════════════════════════════

  /// Set to false to leave Boss/God levels on the legacy pipeline.
  static const bool _fullFillSpecialLevels = true;

  static bool _useFullFill(int levelNumber, LevelType type) {
    if (type == LevelType.tutorial) return false;
    // Hand-tuned sparse special levels keep their original design.
    if (levelNumber == 213 || levelNumber == 395 || levelNumber == 437) {
      return false;
    }
    if ((type == LevelType.boss || type == LevelType.god) &&
        !_fullFillSpecialLevels) {
      return false;
    }
    return true;
  }

  /// Difficulty knobs for the full-board generator.
  ///  • avgLen      shorter arrows => MORE arrows => deeper dependency chains.
  ///  • short/longFrac  bimodal mix: many 2-3 cell arrows + some very long
  ///                snakes (harder to scan AND harder to trace).
  ///  • blockBias   how strongly we pick the head whose ray crosses more arrows.
  ///  • candidates  generate K boards and keep the hardest (see _rankByDifficulty).
  static ({
    double avgLen,
    int maxLen,
    double blockBias,
    int candidates,
    double shortFrac,
    double longFrac
  }) _fullParamsFor(int levelNumber, LevelType type, int gridSize) {
    final double p = ((levelNumber - 4) / 396.0).clamp(0.0, 1.0);
    double avgLen = 6.0 - 2.5 * p;
    if (type == LevelType.boss) avgLen -= 0.5;
    if (type == LevelType.god) avgLen -= 0.8;
    if (avgLen < 3.0) avgLen = 3.0;

    final int maxLen = (8 + gridSize ~/ 4).clamp(8, 18);
    final double blockBias = 0.3 + 0.6 * p;

    // Bimodal lengths only once the gentle intro levels are over.
    final bool mix = levelNumber >= 21;
    final double shortFrac = mix ? 0.25 : 0.0;
    final double longFrac = mix ? 0.15 : 0.0;

    int candidates = 1 + levelNumber ~/ 35;
    if (type == LevelType.boss || type == LevelType.god) candidates += 1;
    candidates = candidates.clamp(1, 10);
    if (gridSize > 20 && candidates > 7) candidates = 7;
    if (gridSize > 30 && candidates > 5) candidates = 5; // bound build time

    return (
      avgLen: avgLen,
      maxLen: maxLen,
      blockBias: blockBias,
      candidates: candidates,
      shortFrac: shortFrac,
      longFrac: longFrac,
    );
  }

  /// Ranks candidate boards hardest-first. Each metric is converted to a
  /// z-score WITHIN this level's candidate set (the metrics have very different
  /// scales), then combined:
  ///   + deeper dependency chain      + more near-miss decoys
  ///   + more blockers per arrow      − more arrows free on move one
  ///   − more uncovered holes
  static void _rankByDifficulty(List<FullBoardResult> rs) {
    if (rs.length < 2) return;
    List<double> z(double Function(FullBoardResult) f) {
      final v = rs.map(f).toList();
      final mean = v.reduce((a, b) => a + b) / v.length;
      double varSum = 0;
      for (final x in v) {
        varSum += (x - mean) * (x - mean);
      }
      final sd = sqrt(varSum / v.length);
      return v.map((x) => sd < 1e-9 ? 0.0 : (x - mean) / sd).toList();
    }

    final zChain = z((r) => r.chainDepth.toDouble());
    final zFree = z((r) => r.initiallyFree.toDouble());
    final zDecoy = z((r) => r.decoys.toDouble());
    final zBlk = z((r) => r.avgBlockers);
    final zHole = z((r) => r.emptyCells.length.toDouble());

    final score = <FullBoardResult, double>{};
    for (int i = 0; i < rs.length; i++) {
      score[rs[i]] = 1.0 * zChain[i] -
          0.8 * zFree[i] +
          0.6 * zDecoy[i] +
          0.5 * zBlk[i] -
          0.4 * zHole[i];
    }
    rs.sort((a, b) => score[b]!.compareTo(score[a]!));
  }

  /// Builds K candidate boards, ranks them by measured difficulty, then runs
  /// pairs + deflectors + solver on the hardest one that verifies.
  /// Returns null if nothing verifies (caller falls back to the old pipeline).
  static LevelModel? _generateFullBoard({
    required int levelNumber,
    required int gridSize,
    required Set<String> mask,
    required LevelType type,
    required MaskShape maskShape,
    int? seedOverride,
    bool quickGeneration = false,
  }) {
    final fp = _fullParamsFor(levelNumber, type, gridSize);
    final int baseSeed = seedOverride ?? levelNumber * 7919 + 314159;
    final candidateCount = quickGeneration ? 1 : fp.candidates;

    final results = <FullBoardResult>[];
    for (int v = 0; v < candidateCount; v++) {
      FullBoardResult? r;
      final retryLimit = quickGeneration ? 1 : 3;
      for (int retry = 0; retry < retryLimit && r == null; retry++) {
        final rng = Random(baseSeed + (v + 1) * 104729 + retry * 1299709);
        r = FullBoardGenerator.generate(
          gridSize: gridSize,
          mask: mask,
          rng: rng,
          avgLen: fp.avgLen,
          maxLen: fp.maxLen,
          blockBias: fp.blockBias,
          shortFrac: fp.shortFrac,
          longFrac: fp.longFrac,
          minCoverage: 0.95, // >= 95% arrow coverage counts as success
        );
      }
      if (r != null) results.add(r);
    }
    if (results.isEmpty) return null;

    _rankByDifficulty(results);

    for (int i = 0; i < results.length; i++) {
      // First with deflectors; if the strict solver rejects, retry without.
      for (final allowDots in const [true, false]) {
        final level = _finishFullLevel(
          result: results[i],
          levelNumber: levelNumber,
          gridSize: gridSize,
          mask: mask,
          type: type,
          maskShape: maskShape,
          pairSeed: baseSeed + 31 * (i + 1),
          allowDots: allowDots,
        );
        if (level != null) {
          _log('Level $levelNumber FULL-BOARD ok: arrows=${results[i].arrows.length} '
              'holes=${results[i].emptyCells.length} chain=${results[i].chainDepth} '
              'free=${results[i].initiallyFree} decoys=${results[i].decoys} '
              'dots=${level.orphanDots.where((d) => d.type != OrphanDotType.neutral).length}\n');
          return level;
        }
      }
    }
    return null;
  }

  /// Fast deterministic seed-driven hard board for daily challenges.
  /// It intentionally skips multi-candidate difficulty ranking and large retry
  /// budgets so first-open generation stays responsive.
  static LevelModel generateDailyChallenge(int seed) {
    return generateLevel(
      480,
      gridSizeOverride: 21,
      seedOverride: seed,
      quickGeneration: true,
    );
  }

  static LevelModel? _finishFullLevel({
    required FullBoardResult result,
    required int levelNumber,
    required int gridSize,
    required Set<String> mask,
    required LevelType type,
    required MaskShape maskShape,
    required int pairSeed,
    required bool allowDots,
  }) {
    // Hard guarantee: every mask cell is EITHER in exactly one arrow OR a hole.
    final covered = <String>{};
    for (final spec in result.arrows) {
      for (final pt in spec.path) {
        if (!covered.add('${pt[0]},${pt[1]}')) return null;
      }
    }
    final holes = <int>[]; // packed r*1000+c
    for (final h in result.emptyCells) {
      if (covered.contains('${h[0]},${h[1]}')) return null;
      holes.add(h[0] * 1000 + h[1]);
    }
    if (covered.length + holes.length != mask.length) return null;
    for (final k in covered) {
      if (!mask.contains(k)) return null;
    }

    final arrows = <ArrowModel>[];
    for (int i = 0; i < result.arrows.length; i++) {
      final spec = result.arrows[i];
      final head = spec.path[0];
      arrows.add(ArrowModel(
        id: 'a_${levelNumber}_$i',
        row: head[0],
        col: head[1],
        direction: spec.direction,
        isPartOfPattern: true,
        path: spec.path,
        mechanic: SnakeMechanic.standard,
      ));
    }

    // 1) Colour pairs on BLOCKED arrows only (straight-ray graph, still exact).
    if (levelNumber >= 16) {
      _hardPairMix(arrows, levelNumber, type, Random(pairSeed), gridSize);
    }

    // 2) Deflector dots (level 21+): holes first, then shortened tails. Every
    //    accepted dot re-verifies the whole board with the runtime-exact solver.
    final dots = allowDots
        ? _carveDeflectors(
            arrows: arrows,
            gridSize: gridSize,
            maskSize: mask.length,
            level: levelNumber,
            type: type,
            holes: holes,
            rng: Random(pairSeed ^ 0x5bd1e995),
          )
        : <int, OrphanDotType>{};

    // 3) Remaining holes become neutral dots (as the legacy pipeline does).
    final orphanDots = <OrphanDot>[];
    dots.forEach((packed, t) {
      orphanDots.add(OrphanDot(row: packed ~/ 1000, col: packed % 1000, type: t));
    });
    for (final h in holes) {
      if (!dots.containsKey(h)) {
        orphanDots.add(
            OrphanDot(row: h ~/ 1000, col: h % 1000, type: OrphanDotType.neutral));
      }
    }

    final level = LevelModel(
      levelNumber: levelNumber,
      gridSize: gridSize,
      arrows: arrows,
      patternName: _nameFor(type, levelNumber),
      difficulty: _difficultyFor(levelNumber, type),
      maskShape: maskShape,
      mask: mask,
      orphanDots: orphanDots,
    );

    final greedyOrder = _greedySolve(level);
    if (greedyOrder == null) return null;

    if (gridSize <= 20) {
      final strict = LevelSolver.solve(level, 6000);
      if (strict == null) return null;
      return level.copyWith(solutionOrder: strict);
    }
    return level.copyWith(solutionOrder: greedyOrder);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  DEFLECTORS (full-board levels, level 21+)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  //  Dots bend exit rays, so rays are no longer straight lines and the simple
  //  acyclic-graph guarantee no longer applies. Instead EVERY dot is accepted
  //  only if the runtime-exact greedy solver still clears the board, colour
  //  pairs still have no free partner, and no pair deadlock appears.
  //
  //  Candidate cells (only cells that lie on some arrow's straight exit ray, so
  //  the dot actually matters): leftover holes first (free), then the TAIL cell
  //  of arrows with >= 3 cells (shortening an arrow only removes blockers, so it
  //  can never create a cycle by itself).
  //
  //  Among the valid directions we keep the one that makes the board take the
  //  most solver rounds, and we never accept a dot that lowers that number.
  static Map<int, OrphanDotType> _carveDeflectors({
    required List<ArrowModel> arrows,
    required int gridSize,
    required int maskSize,
    required int level,
    required LevelType type,
    required List<int> holes,
    required Random rng,
  }) {
    final dots = <int, OrphanDotType>{};
    if (level <= 20) return dots; // STRICT GATE: no dots before level 21

    final double p = ((level - 21) / 380.0).clamp(0.0, 1.0);
    double frac = 0.01 + 0.03 * p;
    if (type == LevelType.boss || type == LevelType.god) frac *= 1.3;
    if (frac > 0.045) frac = 0.045;
    final int want = (maskSize * frac).round();
    if (want <= 0) return dots;

    // How many arrows' STRAIGHT exit rays pass through each cell.
    final rayCount = <int, int>{};
    for (final a in arrows) {
      final d = a.direction.delta;
      int r = a.path[0][0] + d[0], c = a.path[0][1] + d[1];
      while (r >= 0 && r < gridSize && c >= 0 && c < gridSize) {
        final k = r * 1000 + c;
        rayCount[k] = (rayCount[k] ?? 0) + 1;
        r += d[0];
        c += d[1];
      }
    }

    // Candidates: (priority, cell, arrowIndex or -1 for a hole).
    final cands = <(double, int, int)>[];
    for (final h in holes) {
      final rc = rayCount[h] ?? 0;
      if (rc > 0) cands.add((rc + 2.0 + rng.nextDouble(), h, -1));
    }
    for (int i = 0; i < arrows.length; i++) {
      if (arrows[i].path.length < 3) continue;
      final t = arrows[i].path.last;
      final k = t[0] * 1000 + t[1];
      final rc = rayCount[k] ?? 0;
      if (rc > 0) cands.add((rc + rng.nextDouble(), k, i));
    }
    cands.sort((a, b) => b.$1.compareTo(a.$1));

    final minDotDist = (gridSize * 0.20).floor().clamp(2, 6);

    // Whole-board occupancy + dot tables in the formats the helpers expect.
    final occ = <String>{};
    for (final a in arrows) {
      for (final pt in a.path) {
        occ.add('${pt[0]},${pt[1]}');
      }
    }
    final dotsStr = <String, OrphanDotType>{};

    int roundsOf(Map<int, OrphanDotType> m) {
      final out = <int>[];
      final order = _greedySolveWithMap(gridSize, arrows, m, roundsOut: out);
      return order == null ? -1 : out.first;
    }

    int cur = roundsOf(dots);
    if (cur < 0) return dots; // base board must already be solvable

    bool pairsStillBlocked() {
      for (final a in arrows) {
        if (a.colorGroup == null) continue;
        if (_simulateExitClear(a, gridSize, occ, dotsStr)) return false;
      }
      return true;
    }

    int budget = want * 4;
    for (final cand in cands) {
      if (dots.length >= want || budget-- <= 0) break;
      final cell = cand.$2;
      final ai = cand.$3;
      final cr = cell ~/ 1000, cc = cell % 1000;

      // Colored dots must be spaced apart (same rule the legacy pipeline uses).
      bool tooClose = false;
      for (final k in dots.keys) {
        if ((k ~/ 1000 - cr).abs() + (k % 1000 - cc).abs() < minDotDist) {
          tooClose = true;
          break;
        }
      }
      if (tooClose) continue;

      // Tail candidates: shorten the arrow (it must still own this tail).
      ArrowModel? original;
      if (ai >= 0) {
        final a = arrows[ai];
        final t = a.path.last;
        if (a.path.length < 3 || t[0] != cr || t[1] != cc) continue;
        original = a;
        arrows[ai] = a.copyWith(
            path: List<List<int>>.from(a.path)..removeLast());
        occ.remove('$cr,$cc');
      }

      int bestRounds = -1;
      OrphanDotType? bestType;
      for (final dir in ArrowDirection.values) {
        final t = _dotTypeForDir(dir);
        dots[cell] = t;
        dotsStr['$cr,$cc'] = t;
        final r = roundsOf(dots);
        final ok = r >= 0 &&
            r >= cur &&
            !_hasColorLockDeadlock(arrows, gridSize, dotsStr) &&
            pairsStillBlocked();
        dots.remove(cell);
        dotsStr.remove('$cr,$cc');
        if (ok && r > bestRounds) {
          bestRounds = r;
          bestType = t;
        }
      }

      if (bestType != null) {
        dots[cell] = bestType;
        dotsStr['$cr,$cc'] = bestType;
        cur = bestRounds;
      } else if (original != null) {
        arrows[ai] = original; // revert the shortening
        occ.add('$cr,$cc');
      }
    }
    return dots;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  HARD COLOR PAIRS (full-board levels)
  // ═══════════════════════════════════════════════════════════════════════════
  //
  //  Rule of the game: tapping one arrow of a pair fires BOTH, so both exit
  //  rays must be clear at the same moment.
  //
  //  The legacy mixer only paired arrows whose rays were ALREADY clear, so every
  //  pair was free on move one (tap = 2 arrows gone, no thinking). Here a pair
  //  is chosen only among BLOCKED arrows, ranked by how deep / how separate
  //  their blockers are, so the player must clear two different regions before
  //  the pair can fire.
  //
  //  Solvability: a pair behaves like ONE node whose blockers are the union of
  //  both partners' blockers. A candidate is accepted only if the dependency
  //  graph, with the pair contracted into one node, is still acyclic (this also
  //  rejects "A is blocked by something that waits on B"). It also rejects any
  //  pair where one partner's ray crosses the other's body, which is exactly
  //  what the verifier (_hasColorLockDeadlock) rejects.

  /// Pair count per level band — same table as _mechanicMixV2.
  static int _pairCountFor(int level, LevelType type, int arrowCount) {
    int pairs;
    if (type == LevelType.god) {
      if      (level < 30)   pairs = 3;
      else if (level < 60)   pairs = (arrowCount * 0.25).floor().clamp(3, 7);
      else if (level < 150)  pairs = (arrowCount * 0.35).floor().clamp(4, 10);
      else                   pairs = (arrowCount * 0.40).floor().clamp(5, 14);
    } else if (type == LevelType.boss) {
      if      (level < 30)   pairs = 2;
      else if (level < 60)   pairs = (arrowCount * 0.20).floor().clamp(2, 5);
      else if (level < 150)  pairs = (arrowCount * 0.28).floor().clamp(3, 8);
      else                   pairs = (arrowCount * 0.35).floor().clamp(4, 12);
    } else {
      if      (level < 25)   pairs = 1;
      else if (level < 45)   pairs = (arrowCount * 0.15).floor().clamp(1, 3);
      else if (level < 80)   pairs = (arrowCount * 0.22).floor().clamp(2, 5);
      else if (level < 150)  pairs = (arrowCount * 0.28).floor().clamp(3, 8);
      else if (level < 300)  pairs = (arrowCount * 0.32).floor().clamp(4, 10);
      else                   pairs = (arrowCount * 0.38).floor().clamp(5, 14);
    }
    if (level >= 150) pairs += 2; // late game: more simultaneous-exit puzzles
    return pairs.clamp(1, 15);
  }

  /// Layers the dependency graph with each pair contracted into one node
  /// ([rep] maps every arrow to its group representative). Returns the layer
  /// depth per representative, or null if the contracted graph has a cycle.
  static List<int>? _layerDepth(List<Set<int>> blockedBy, List<int> rep) {
    final n = blockedBy.length;
    final isNode = List<bool>.filled(n, false);
    for (int i = 0; i < n; i++) {
      isNode[rep[i]] = true;
    }
    final deps = List.generate(n, (_) => <int>{});
    for (int x = 0; x < n; x++) {
      for (final y in blockedBy[x]) {
        final u = rep[x], v = rep[y];
        if (u != v) deps[u].add(v);
      }
    }
    final users = List.generate(n, (_) => <int>[]);
    final remaining = List<int>.filled(n, 0);
    int nodes = 0;
    for (int u = 0; u < n; u++) {
      if (!isNode[u]) continue;
      nodes++;
      remaining[u] = deps[u].length;
      for (final v in deps[u]) {
        users[v].add(u);
      }
    }
    final depth = List<int>.filled(n, 0);
    final queue = <int>[];
    for (int u = 0; u < n; u++) {
      if (isNode[u] && remaining[u] == 0) {
        depth[u] = 1;
        queue.add(u);
      }
    }
    int head = 0;
    while (head < queue.length) {
      final u = queue[head++];
      for (final w in users[u]) {
        if (depth[w] < depth[u] + 1) depth[w] = depth[u] + 1;
        if (--remaining[w] == 0) queue.add(w);
      }
    }
    return queue.length == nodes ? depth : null;
  }

  /// Assigns colour pairs to BLOCKED arrows only (preferring chained pairs
  /// and partners with disjoint blockers). Returns the pair count.
  static int _hardPairMix(List<ArrowModel> arrows, int level, LevelType type,
      Random rng, int gridSize) {
    if (arrows.length < 4 || level <= 15) return 0;
    final want = _pairCountFor(level, type, arrows.length);
    final n = arrows.length;

    // blockedBy[i] = arrows whose body touches arrow i's exit ray.
    final owner = <int, int>{};
    for (int i = 0; i < n; i++) {
      for (final pt in arrows[i].path) {
        owner[pt[0] * gridSize + pt[1]] = i;
      }
    }
    final blockedBy = List.generate(n, (_) => <int>{});
    for (int i = 0; i < n; i++) {
      final a = arrows[i];
      final d = a.direction.delta;
      int r = a.path[0][0] + d[0], c = a.path[0][1] + d[1];
      while (r >= 0 && r < gridSize && c >= 0 && c < gridSize) {
        final o = owner[r * gridSize + c];
        if (o != null && o != i) blockedBy[i].add(o);
        r += d[0];
        c += d[1];
      }
    }

    var rep = List<int>.generate(n, (i) => i);
    final base = _layerDepth(blockedBy, rep);
    if (base == null) return 0; // board already cyclic — never pair on it

    // Only arrows that are NOT free on move one may be paired.
    final ids = <int>[
      for (int i = 0; i < n; i++)
        if (blockedBy[i].isNotEmpty) i
    ];
    if (ids.length < 2) return 0;

    final minDist = (gridSize * 0.25).floor().clamp(2, 15);
    // Early pair levels pick a mid-difficulty pair, later levels the hardest.
    final double hardness = ((level - 16) / 300.0).clamp(0.0, 1.0);

    final used = <int>{};
    int made = 0;
    for (int pn = 0; pn < want; pn++) {
      final cands = <(double, int, int)>[];
      for (int t = 0; t < 120; t++) {
        final x = ids[rng.nextInt(ids.length)];
        final y = ids[rng.nextInt(ids.length)];
        if (x == y || used.contains(x) || used.contains(y)) continue;
        final dist = (arrows[x].row - arrows[y].row).abs() +
            (arrows[x].col - arrows[y].col).abs();
        if (dist < minDist) continue;
        // A partner's ray must not cross the other partner's body.
        if (blockedBy[x].contains(y) || blockedBy[y].contains(x)) continue;
        final union = <int>{...blockedBy[x], ...blockedBy[y]};
        // Blockers in DIFFERENT regions force two separate clearing efforts.
        int inter = 0;
        for (final u in blockedBy[x]) {
          if (blockedBy[y].contains(u)) inter++;
        }
        final symDiff = union.length - inter;
        // CHAINED pairs: blockers that are themselves paired arrows mean this
        // pair can only fire after another pair has fired.
        int links = 0;
        for (final u in union) {
          if (used.contains(u)) links++;
        }
        final score = base[x] + base[y] + 0.5 * union.length +
            0.5 * symDiff + 4.0 * links;
        cands.add((score, x, y));
      }
      if (cands.isEmpty) continue;
      cands.sort((a, b) => b.$1.compareTo(a.$1));

      final start = ((1.0 - hardness) * (cands.length - 1) * 0.5).round();
      for (int k = 0; k < cands.length; k++) {
        final c = cands[(start + k) % cands.length];
        final x = c.$2, y = c.$3;
        final rep2 = List<int>.from(rep);
        rep2[y] = x;
        if (_layerDepth(blockedBy, rep2) == null) continue; // would deadlock
        rep = rep2;
        used..add(x)..add(y);
        arrows[x] = arrows[x]
            .copyWith(mechanic: SnakeMechanic.colorLock, colorGroup: made);
        arrows[y] = arrows[y]
            .copyWith(mechanic: SnakeMechanic.colorLock, colorGroup: made);
        made++;
        break;
      }
    }

    // Safety net: same verifier criterion the pipeline already uses.
    int valid = made;
    while (valid > 0 &&
        _hasColorLockDeadlock(arrows, gridSize, <String, OrphanDotType>{})) {
      _demoteLastPair(arrows, valid - 1);
      valid--;
    }
    return valid;
  }

  // ── Tutorial level builders ──────────────────────────────────────────────────

  static LevelModel _buildTutorial1() {
    // ┌─────────────────────────────────────────────────────────────────────────┐
    // │  TUTORIAL LEVEL 1 — Tap to Fire                                        │
    // │  2 solo arrows on 10×10, both immediately fireable from the start.     │
    // │  Teaches: tap → fires, blocked path → costs a life.                   │
    // └─────────────────────────────────────────────────────────────────────────┘
    final arrows = [
      ArrowModel(
        id: 'a_1_0',
        row: 4, col: 5,
        direction: ArrowDirection.right,
        isPartOfPattern: true,
        path: [[4, 5], [4, 4]],
        mechanic: SnakeMechanic.standard,
      ),
      ArrowModel(
        id: 'a_1_1',
        row: 5, col: 5,
        direction: ArrowDirection.up,
        isPartOfPattern: true,
        path: [[5, 5], [6, 5]],
        mechanic: SnakeMechanic.standard,
      ),
      ArrowModel(
        id: 'a_1_2',
        row: 7, col: 5,
        direction: ArrowDirection.up,
        isPartOfPattern: true,
        path: [[7, 5], [8, 5]],
        mechanic: SnakeMechanic.standard,
      ),
    ];
    return LevelModel(
      levelNumber: 1,
      gridSize: 10,
      arrows: arrows,
      patternName: 'Tutorial 1',
      difficulty: Difficulty.tutorial,
      maskShape: MaskShape.square,
      mask: MaskGeneratorV2.squareMask(10),
      orphanDots: [],
      solutionOrder: ['a_1_0', 'a_1_1', 'a_1_2'],
    );
  }

  static LevelModel _buildTutorial2() {
    // ┌─────────────────────────────────────────────────────────────────────────┐
    // │  TUTORIAL LEVEL 2 — Color Pairs                                        │
    // │  1 color pair (both must be clear simultaneously) + 1 solo arrow.      │
    // │  Teaches: tapping either partner fires both; both must be unblocked.   │
    // └─────────────────────────────────────────────────────────────────────────┘
    final arrows = [
      ArrowModel(
        id: 'a_2_0',
        row: 5, col: 4,
        direction: ArrowDirection.up,
        isPartOfPattern: true,
        path: [[5, 4], [6, 4]],
        mechanic: SnakeMechanic.colorLock,
        colorGroup: 0,
      ),
      ArrowModel(
        id: 'a_2_1',
        row: 5, col: 6,
        direction: ArrowDirection.right,
        isPartOfPattern: true,
        path: [[5, 6], [5, 5]],
        mechanic: SnakeMechanic.colorLock,
        colorGroup: 0,
      ),
      ArrowModel(
        id: 'a_2_2',
        row: 4, col: 4,
        direction: ArrowDirection.left,
        isPartOfPattern: true,
        path: [[4, 4], [4, 5]],
        mechanic: SnakeMechanic.standard,
      ),
    ];
    return LevelModel(
      levelNumber: 2,
      gridSize: 10,
      arrows: arrows,
      patternName: 'Tutorial 2',
      difficulty: Difficulty.tutorial,
      maskShape: MaskShape.square,
      mask: MaskGeneratorV2.squareMask(10),
      orphanDots: [],
      solutionOrder: ['a_2_2', 'a_2_0', 'a_2_1'],
    );
  }

  static LevelModel _buildTutorial3() {
    // ┌─────────────────────────────────────────────────────────────────────────┐
    // │  TUTORIAL LEVEL 3 — Direction-Changing Dots                            │
    // │  1 plain arrow + 1 arrow that exits through a deflector dot.           │
    // │  Teaches: dots turn the arrow; new exit direction must also be clear.  │
    // └─────────────────────────────────────────────────────────────────────────┘
    // arr_0: head at (6,4) pointing UP, tail at (7,4).
    //   Exit path: row=5,4,3,2,1,0 all at col=4 — hits dot at (5,4) → turns RIGHT.
    //   After turn: exits col=5,6,7,8,9 at row=5 — clear (arr_1 is at col=6 row=4).
    // arr_1: head at (4,6) pointing DOWN, tail at (3,6). Fires first.
    //   Exit path: row=5,6,7,8,9 at col=6 — clear.
    final arrows = [
      ArrowModel(
        id: 'a_3_0',
        row: 6, col: 4,
        direction: ArrowDirection.up,
        isPartOfPattern: true,
        path: [[6, 4], [7, 4]],
        mechanic: SnakeMechanic.standard,
      ),
      ArrowModel(
        id: 'a_3_1',
        row: 4, col: 6,
        direction: ArrowDirection.down,
        isPartOfPattern: true,
        path: [[4, 6], [3, 6]],
        mechanic: SnakeMechanic.standard,
      ),
    ];
    final orphanDots = [
      const OrphanDot(row: 5, col: 4, type: OrphanDotType.right),
    ];
    return LevelModel(
      levelNumber: 3,
      gridSize: 10,
      arrows: arrows,
      patternName: 'Tutorial 3',
      difficulty: Difficulty.tutorial,
      maskShape: MaskShape.square,
      mask: MaskGeneratorV2.squareMask(10),
      orphanDots: orphanDots,
      solutionOrder: ['a_3_1', 'a_3_0'],
    );
  }

  // ── Single generation attempt ────────────────────────────────────────────────

  static LevelModel? _attempt({
    required int levelNumber,
    required int gridSize,
    required Set<String> mask,
    required _Params params,
    required LevelType type,
    required Random rng,
    required MaskShape maskShape,
    required int attempt,
  }) {
    final arrows           = <ArrowModel>[];
    final occupied         = <String>{};
    final occupiedPacked   = <int>{};
    int counter            = 0;

    final maskCells = mask.map((k) {
      final p = k.split(',');
      return [int.parse(p[0]), int.parse(p[1])];
    }).toList();

    final maskPacked = <int>{};
    for (final cell in maskCells) {
      maskPacked.add(cell[0] * 1000 + cell[1]);
    }

    // ── Fill strategy ────────────────────────────────────────────────────────
    // Phase 1 tries to fill the entire grid for the first 12 attempts.
    // After that it falls back to a density target that decreases on each retry.
    // V2 CHANGE: Phase 2 fill rate is capped per level to avoid 2-cell dominance.
    bool fillEntireGrid = type != LevelType.tutorial && attempt < 12;
    if (levelNumber == 213 || levelNumber == 395 || levelNumber == 437) {
      fillEntireGrid = false;
    }

    int targetCount = fillEntireGrid ? mask.length : params.arrowCount;
    if (!fillEntireGrid) {
      double fillRate;
      if (levelNumber == 213 || levelNumber == 395 || levelNumber == 437) {
        fillRate = 0.55;
      } else {
        fillRate = (1.0 - (attempt - 12) * 0.02).clamp(0.68, 0.95);
      }
      final targetOccupied = (mask.length * fillRate).round();
      targetCount = (targetOccupied / params.avgLen).round().clamp(4, 300);
    }



    // ═══════════════════════════════════════════════════════════════════════════
    //  PHASE 1 — Place VeryLong / Long / Medium / Short arrows (≥3 cell first)
    //  V2 CHANGE: Short tier added (10% weight, length=2).
    //  V2 CHANGE: Tangle factor starts at 0.20 from level 4 (was 0.0).
    // ═══════════════════════════════════════════════════════════════════════════
    {
      int failures     = 0;
      int veryLongCount = 0;
      int longCount     = 0;
      int medCount      = 0;
      int shortCount    = 0;
      final int maxFailures = type == LevelType.tutorial ? 60 : 80;

      // ── V2 Tangle factor ──────────────────────────────────────────────────
      final double tangleFactor = _tangleFactorFor(levelNumber, type);

      // Grid-size-adaptive tier thresholds
      int veryLongMin = 5 + (gridSize ~/ 6);
      int longMin     = 3 + (gridSize ~/ 10);
      int veryLongMax = max(veryLongMin + 1,
          (veryLongMin + 4).clamp(veryLongMin + 1, mask.length));

      if (maskShape != MaskShape.square && maskShape != MaskShape.longRectangle) {
        veryLongMin = max(5, (veryLongMin * 0.8).round());
        longMin     = max(3, (longMin     * 0.8).round());
        veryLongMax = max(veryLongMin + 1, (veryLongMax * 0.8).round());
      }

      final int maxAllowedBlocks =
          (type == LevelType.tutorial || gridSize > 20) ? 0 : 1;

      while (failures < maxFailures &&
          (fillEntireGrid
              ? occupiedPacked.length < mask.length
              : arrows.length < targetCount)) {

        final int relaxation     = failures ~/ 8;
        final int curVeryLongMin = max(5, veryLongMin - relaxation);
        final int curLongMin     = max(3, longMin     - relaxation);
        final int curVeryLongMax =
            max(curVeryLongMin + 1, veryLongMax - relaxation);

        final candidates = _exitCandidates(
            maskCells, occupiedPacked, gridSize, maxAllowedBlocks);
        if (candidates.isEmpty) break;

        // Quick check: can we still fit a ≥3-cell arrow?
        bool anyCanFit3 = false;
        for (final cell in maskCells) {
          final r = cell[0], c = cell[1];
          if (occupiedPacked.contains(r * 1000 + c)) continue;
          int freeNb = 0;
          for (final nb in [[-1,0],[1,0],[0,-1],[0,1]]) {
            final nr = r + nb[0], nc = c + nb[1];
            if (maskPacked.contains(nr * 1000 + nc) &&
                !occupiedPacked.contains(nr * 1000 + nc)) {
              freeNb++;
            }
          }
          if (freeNb >= 2) { anyCanFit3 = true; break; }
        }
        if (!anyCanFit3) break; // hand off to Phase 2

        _shuffleCandidatesFromCenter(candidates, gridSize, rng);

        _Cand? bestCand;
        List<List<int>>? bestPath;
        int minBlocked = 9999;

        // ── V2: 4-tier selection (35% VeryLong, 30% Long, 25% Medium, 10% Short)
        final _LenTier wantTier = _selectTier(
          type: type,
          failures: failures,
          veryLongCount: veryLongCount,
          longCount: longCount,
          medCount: medCount,
          shortCount: shortCount,
          rng: rng,
        );

        for (final cand in candidates.take(15)) {
          final int len = _lengthForTier(
            wantTier, curVeryLongMin, curVeryLongMax, curLongMin, type, rng);

          final path = _growPath(
            startRow: cand.row,
            startCol: cand.col,
            exitDir: cand.dir,
            maskPacked: maskPacked,
            occupiedPacked: occupiedPacked,
            targetLen: len,
            rng: rng,
            gridSize: gridSize,
            tangleFactor: wantTier == _LenTier.veryLong ? tangleFactor : 0.0,
          );

          final int minAcceptableLen = _minAcceptableLen(
              wantTier, curVeryLongMin, curLongMin, type);

          if (path != null && path.length >= minAcceptableLen) {
            final blockedCount = _evalPlacement(
              maskCells: maskCells,
              maskPacked: maskPacked,
              currentOccupiedPacked: occupiedPacked,
              newPath: path,
              gridSize: gridSize,
            );
            if (blockedCount == 0) {
              bestCand  = cand;
              bestPath  = path;
              minBlocked = 0;
              break;
            }
            if (blockedCount < minBlocked) {
              minBlocked = blockedCount;
              bestCand   = cand;
              bestPath   = path;
            }
          }
        }

        // Fallback cascade: try shorter tiers
        if (bestPath == null && type != LevelType.tutorial) {
          bestPath = _fallbackPlacement(
            wantTier: wantTier,
            candidates: candidates,
            curVeryLongMin: curVeryLongMin,
            curVeryLongMax: curVeryLongMax,
            curLongMin: curLongMin,
            maskPacked: maskPacked,
            occupiedPacked: occupiedPacked,
            gridSize: gridSize,
            rng: rng,
            bestCandOut: (c) => bestCand = c,
            minBlockedOut: (b) => minBlocked = b,
          );
        }

        if (bestCand != null && bestPath != null && minBlocked < 1000) {
          _placeArrow(arrows, bestPath, bestCand!.dir,
              levelNumber, counter++, occupied, occupiedPacked);
          if (bestPath.length >= curVeryLongMin)      veryLongCount++;
          else if (bestPath.length >= curLongMin)     longCount++;
          else if (bestPath.length >= 3)              medCount++;
          else                                          shortCount++;
          failures = 0;
        } else {
          failures++;
          if (failures > 50 &&
              bestPath == null &&
              occupiedPacked.length >= maskPacked.length * 0.5) break;
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  PHASE 2 — 2-cell pair sweep (fills remaining gaps)
    // ═══════════════════════════════════════════════════════════════════════════
    if (type != LevelType.tutorial) {
      final double phase2MaxFill = _phase2MaxFill(levelNumber, type);
      final int phase2TargetCells = (maskPacked.length * phase2MaxFill).round();
      final int maxAllowedBlocks  = 0;

      // ── Sub-pass 2a: exit-constrained length-2 arrows ────────────────────
      {
        int failures = 0;
        while (failures < 60 && occupiedPacked.length < phase2TargetCells) {
          final candidates = _exitCandidates(
              maskCells, occupiedPacked, gridSize, maxAllowedBlocks);
          if (candidates.isEmpty) break;

          _shuffleCandidatesFromCenter(candidates, gridSize, rng);

          _Cand?        bestCand;
          List<List<int>>? bestPath;
          int minBlocked = 9999;

          for (final cand in candidates.take(20)) {
            final path = _growPath(
              startRow: cand.row,
              startCol: cand.col,
              exitDir: cand.dir,
              maskPacked: maskPacked,
              occupiedPacked: occupiedPacked,
              targetLen: 2,
              rng: rng,
              gridSize: gridSize,
            );
            if (path != null && path.length == 2) {
              final bc = _evalPlacement(
                maskCells: maskCells,
                maskPacked: maskPacked,
                currentOccupiedPacked: occupiedPacked,
                newPath: path,
                gridSize: gridSize,
              );
              if (bc == 0) {
                bestCand = cand; bestPath = path; minBlocked = 0; break;
              }
              if (bc < minBlocked) {
                minBlocked = bc; bestCand = cand; bestPath = path;
              }
            }
          }

          if (bestCand != null && bestPath != null && minBlocked < 1000) {
            _placeArrow(arrows, bestPath, bestCand.dir,
                levelNumber, counter++, occupied, occupiedPacked);
            failures = 0;
          } else {
            failures++;
          }
        }
      }

      // ── Sub-pass 2b: greedy adjacent-pair sweep (clean-exit only) ──────────
      {
        bool madeProgress = true;
        while (madeProgress && occupiedPacked.length < phase2TargetCells) {
          madeProgress = false;
          final emptyCells = maskCells
              .where((c) => !occupiedPacked.contains(c[0] * 1000 + c[1]))
              .toList()
            ..shuffle(rng);

          for (final cell in emptyCells) {
            final r = cell[0], c = cell[1];
            if (occupiedPacked.contains(r * 1000 + c)) continue;

            final nbOffsets = [[-1,0],[1,0],[0,-1],[0,1]]..shuffle(rng);
            for (final nb in nbOffsets) {
              final tr = r + nb[0], tc = c + nb[1];
              if (!maskPacked.contains(tr * 1000 + tc)) continue;
              if (occupiedPacked.contains(tr * 1000 + tc)) continue;

              final ArrowDirection dir1, dir2;
              if      (nb[0] ==  1) { dir1 = ArrowDirection.up;    dir2 = ArrowDirection.down; }
              else if (nb[0] == -1) { dir1 = ArrowDirection.down;  dir2 = ArrowDirection.up;   }
              else if (nb[1] ==  1) { dir1 = ArrowDirection.left;  dir2 = ArrowDirection.right; }
              else                   { dir1 = ArrowDirection.right; dir2 = ArrowDirection.left;  }

              int headRow, headCol, tailRow, tailCol;
              ArrowDirection chosenDir;

              if (_canExitClean(r, c, dir1, occupiedPacked, gridSize)) {
                headRow = r;  headCol = c;  tailRow = tr; tailCol = tc;
                chosenDir = dir1;
              } else if (_canExitClean(tr, tc, dir2, occupiedPacked, gridSize)) {
                headRow = tr; headCol = tc; tailRow = r;  tailCol = c;
                chosenDir = dir2;
              } else {
                continue;
              }

              arrows.add(ArrowModel(
                id: 'a_${levelNumber}_${counter++}',
                row: headRow, col: headCol,
                direction: chosenDir,
                isPartOfPattern: true,
                path: [[headRow, headCol], [tailRow, tailCol]],
                mechanic: SnakeMechanic.standard,
              ));
              occupied.add('$r,$c');
              occupied.add('$tr,$tc');
              occupiedPacked.add(r * 1000 + c);
              occupiedPacked.add(tr * 1000 + tc);
              madeProgress = true;
              break;
            }
          }
        }
      }

      // ── Sub-pass 2c: fallback greedy sweep (no clean-exit requirement) ──────
      {
        bool madeProgress = true;
        while (madeProgress && occupiedPacked.length < phase2TargetCells) {
          madeProgress = false;
          final emptyCells = maskCells
              .where((c) => !occupiedPacked.contains(c[0] * 1000 + c[1]))
              .toList()
            ..shuffle(rng);

          for (final cell in emptyCells) {
            final r = cell[0], c = cell[1];
            if (occupiedPacked.contains(r * 1000 + c)) continue;

            final nbOffsets = [[-1,0],[1,0],[0,-1],[0,1]]..shuffle(rng);
            for (final nb in nbOffsets) {
              final tr = r + nb[0], tc = c + nb[1];
              if (!maskPacked.contains(tr * 1000 + tc)) continue;
              if (occupiedPacked.contains(tr * 1000 + tc)) continue;

              final ArrowDirection dir1, dir2;
              if      (nb[0] ==  1) { dir1 = ArrowDirection.up;    dir2 = ArrowDirection.down; }
              else if (nb[0] == -1) { dir1 = ArrowDirection.down;  dir2 = ArrowDirection.up;   }
              else if (nb[1] ==  1) { dir1 = ArrowDirection.left;  dir2 = ArrowDirection.right; }
              else                   { dir1 = ArrowDirection.right; dir2 = ArrowDirection.left;  }

              final tries = rng.nextBool()
                  ? [[r, c, tr, tc, dir1], [tr, tc, r, c, dir2]]
                  : [[tr, tc, r, c, dir2], [r, c, tr, tc, dir1]];

              for (final t in tries) {
                final hr = t[0] as int, hc = t[1] as int;
                final tailR = t[2] as int, tailC = t[3] as int;
                final dir = t[4] as ArrowDirection;
                if (_canExitClean(hr, hc, dir, occupiedPacked, gridSize)) {
                  arrows.add(ArrowModel(
                    id: 'a_${levelNumber}_${counter++}',
                    row: hr, col: hc,
                    direction: dir,
                    isPartOfPattern: true,
                    path: [[hr, hc], [tailR, tailC]],
                    mechanic: SnakeMechanic.standard,
                  ));
                  occupied.add('$hr,$hc');
                  occupied.add('$tailR,$tailC');
                  occupiedPacked.add(hr * 1000 + hc);
                  occupiedPacked.add(tailR * 1000 + tailC);
                  madeProgress = true;
                  break;
                }
              }
              if (madeProgress) break;
            }
          }
        }
      }
    }

    // ═══════════════════════════════════════════════════════════════════════════
    //  PHASE 3 — Orphan minimisation + direction-dot coloring + color pairs
    // ═══════════════════════════════════════════════════════════════════════════

    // Absorb isolated single empty cells into adjacent arrow tails
    if (type != LevelType.tutorial && occupied.length < mask.length) {
      _absorbOrphans(arrows, occupied, occupiedPacked, mask, gridSize);
    }

    if (arrows.isEmpty) return null;

    // Minimum arrow density check (30% of mask)
    final minArrowCoverage = (mask.length * 0.30).floor();
    if (occupied.length < minArrowCoverage && type != LevelType.tutorial) {
      _log('Level $levelNumber Attempt $attempt: too sparse\n');
      return null;
    }

    final emptyCount = mask.length - occupied.length;
    const double maxOrphansPct = 0.26;
    final maxOrphans = (mask.length * maxOrphansPct).ceil().clamp(5, 300);

    if (fillEntireGrid && emptyCount > maxOrphans) {
      _log('Level $levelNumber Attempt $attempt: too many orphans $emptyCount/$maxOrphans\n');
      return null;
    }

    // Create orphan dots with V2 difficulty-scaled coloring
    final orphanDots = <OrphanDot>[];
    if (emptyCount > 0) {
      final emptyKeysPacked = maskCells
          .where((c) => !occupiedPacked.contains(c[0] * 1000 + c[1]))
          .map((c) => c[0] * 1000 + c[1])
          .toSet();
      final orphanMap = <int, OrphanDotType>{};

      // ── V2 Direction dot color probability ───────────────────────────────────
      final double colorProb = _colorProbFor(levelNumber, type);

      for (int i = arrows.length - 1; i >= 0; i--) {
        final arrow = arrows[i];
        ArrowDirection currentDir = arrow.direction;
        final head = arrow.path[0];
        var d = currentDir.delta;
        int nr = head[0] + d[0], nc = head[1] + d[1];
        final visited = <int>{};

        while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
          final kp = nr * 1000 + nc;
          if (visited.contains(kp)) break;
          visited.add(kp);

          if (emptyKeysPacked.contains(kp)) {
            if (!orphanMap.containsKey(kp)) {
              if (rng.nextDouble() < colorProb) {
                bool tooClose = false;
                for (final entry in orphanMap.entries) {
                  if (entry.value == OrphanDotType.neutral) continue;
                  final pk = entry.key;
                  final er = pk ~/ 1000, ec = pk % 1000;
                  final minDotDist = (gridSize * 0.20).floor().clamp(2, 6);
                  if ((er - nr).abs() + (ec - nc).abs() < minDotDist) {
                    tooClose = true; break;
                  }
                }
                if (!tooClose) {
                  final turns = rng.nextBool()
                      ? [currentDir.turnRight, currentDir.turnLeft]
                      : [currentDir.turnLeft,  currentDir.turnRight];
                  bool assigned = false;
                  for (final candDir in turns) {
                    orphanMap[kp] = _dotTypeForDir(candDir);
                    if (_greedySolveWithMap(gridSize, arrows, orphanMap) != null) {
                      currentDir = candDir;
                      assigned = true;
                      break;
                    } else {
                      orphanMap.remove(kp);
                    }
                  }
                  if (!assigned) {
                    orphanMap[kp] = _dotTypeForDir(currentDir);
                    if (_greedySolveWithMap(gridSize, arrows, orphanMap) == null) {
                      orphanMap[kp] = OrphanDotType.neutral;
                    }
                  }
                } else {
                  orphanMap[kp] = OrphanDotType.neutral;
                }
              } else {
                orphanMap[kp] = OrphanDotType.neutral;
              }
            } else {
              final dotType = orphanMap[kp]!;
              if      (dotType == OrphanDotType.up)    currentDir = ArrowDirection.up;
              else if (dotType == OrphanDotType.down)  currentDir = ArrowDirection.down;
              else if (dotType == OrphanDotType.left)  currentDir = ArrowDirection.left;
              else if (dotType == OrphanDotType.right) currentDir = ArrowDirection.right;
            }
          }

          d = currentDir.delta;
          nr += d[0]; nc += d[1];
        }
      }

      for (final kp in emptyKeysPacked) {
        if (!orphanMap.containsKey(kp)) {
          orphanMap[kp] = OrphanDotType.neutral;
        }
      }

      for (final entry in orphanMap.entries) {
        final r = entry.key ~/ 1000, c = entry.key % 1000;
        orphanDots.add(OrphanDot(row: r, col: c, type: entry.value));
        occupied.add('$r,$c');
      }
    }

    // ── V2: Color pair mechanic mix ───────────────────────────────────────────
    // STRICT GATE: no pairs before level 16 for any level type
    if (levelNumber == 2 ||
        (type != LevelType.tutorial && levelNumber >= 16)) {
      _mechanicMixV2(
          arrows, levelNumber, type, rng, gridSize, orphanDots);
    }

    final level = LevelModel(
      levelNumber: levelNumber,
      gridSize: gridSize,
      arrows: arrows,
      patternName: _nameFor(type, levelNumber),
      difficulty: _difficultyFor(levelNumber, type),
      maskShape: maskShape,
      mask: mask,
      orphanDots: orphanDots,
    );

    // Solvability check
    if (gridSize > 20) {
      final greedyOrder = _greedySolve(level);
      if (greedyOrder == null) {
        _log('Level $levelNumber Attempt $attempt: greedy FAILED\n');
        return null;
      }
      _log('Level $levelNumber Attempt $attempt: SUCCEEDED (greedy)\n');
      return level.copyWith(solutionOrder: greedyOrder);
    }

    final quickSolution = LevelSolver.solve(level, 5000);
    if (quickSolution == null) {
      _log('Level $levelNumber Attempt $attempt: solver failed\n');
      return null;
    }
    _log('Level $levelNumber Attempt $attempt: SUCCEEDED\n');
    return level.copyWith(solutionOrder: quickSolution);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  V2 HELPERS — New/changed from V1
  // ═══════════════════════════════════════════════════════════════════════════

  // ── V2: Tangle factor ──────────────────────────────────────────────────────
  /// Returns a tangle factor in [0.0, 1.0].
  /// V2 starts at 0.20 from level 4 instead of 0.0 — makes early levels
  /// visually interesting even without mechanics.
  static double _tangleFactorFor(int levelNumber, LevelType type) {
    if (type == LevelType.tutorial) return 0.0;
    double base;
    if      (levelNumber <= 6)   base = 0.50; // level 4-6:   immediate strong tangle
    else if (levelNumber <= 12)  base = 0.70; // level 7-12:  very high tangle
    else if (levelNumber <= 20)  base = 0.85; // level 13-20: extreme tangle
    else                         base = 1.0;  // level 21+:   maximum zig-zag

    if      (type == LevelType.boss) base = (base + 0.20).clamp(0.50, 1.0);
    else if (type == LevelType.god)  base = (base + 0.30).clamp(0.65, 1.0);
    return base;
  }

  // ── V2: 4-tier selection ───────────────────────────────────────────────────
  /// V2: 4-tier weighted selection: 50% VeryLong, 30% Long, 10% Medium, 10% Short.
  static _LenTier _selectTier({
    required LevelType type,
    required int failures,
    required int veryLongCount,
    required int longCount,
    required int medCount,
    required int shortCount,
    required Random rng,
  }) {
    if (type == LevelType.tutorial) return _LenTier.medium;
    if (failures > 15)             return _LenTier.medium;

    final total = veryLongCount + longCount + medCount + shortCount;
    if (total == 0) return _LenTier.veryLong; // always start with very long

    final vlRatio  = veryLongCount / total;
    final lRatio   = longCount     / total;
    final medRatio = medCount      / total;

    // Target: 50% VL, 30% L, 10% M, 10% S
    if (vlRatio  < 0.50) return _LenTier.veryLong;
    if (lRatio   < 0.30) return _LenTier.long;
    if (medRatio < 0.10) return _LenTier.medium;
    return _LenTier.short;
  }

  static int _lengthForTier(_LenTier tier, int veryLongMin, int veryLongMax,
      int longMin, LevelType type, Random rng) {
    switch (tier) {
      case _LenTier.veryLong:
        final range = max(1, veryLongMax - veryLongMin + 1);
        return veryLongMin + rng.nextInt(range);
      case _LenTier.long:
        final longMax = max(longMin, veryLongMin - 1);
        final range   = max(1, longMax - longMin + 1);
        return longMin + rng.nextInt(range);
      case _LenTier.medium:
        return type == LevelType.tutorial
            ? 2 + rng.nextInt(3)
            : 3 + rng.nextInt(3);
      case _LenTier.short:
        return 2;
    }
  }

  static int _minAcceptableLen(_LenTier tier, int curVeryLongMin,
      int curLongMin, LevelType type) {
    switch (tier) {
      case _LenTier.veryLong: return curVeryLongMin;
      case _LenTier.long:     return curLongMin;
      case _LenTier.medium:   return 3;
      case _LenTier.short:    return 2;
    }
  }

  // ── V2: Phase 2 max fill rate ─────────────────────────────────────────────
  static double _phase2MaxFill(int levelNumber, LevelType type) {
    if (type == LevelType.god)  return 0.98; // God levels 98% grid coverage
    if (type == LevelType.boss) return 0.94; // Boss levels 94% grid coverage

    if      (levelNumber <= 10)  return 0.80;
    else if (levelNumber <= 30)  return 0.88;
    else                         return 0.95;
  }

  // ── V2: Direction dot color probability ──────────────────────────────────
  static double _colorProbFor(int levelNumber, LevelType type) {
    // STRICT GATE: no direction dots before level 21 (any type)
    if (levelNumber <= 20) return 0.0;
    if (levelNumber == 395 || levelNumber == 437) return 0.0;

    if (type == LevelType.god) {
      if      (levelNumber < 35)  return 0.80;
      else if (levelNumber < 60)  return 0.88;
      else                        return 0.95;
    }
    if (type == LevelType.boss) {
      if      (levelNumber < 35)  return 0.70;
      else if (levelNumber < 60)  return 0.82;
      else                        return 0.92;
    }
    // Normal levels >= 21
    if      (levelNumber < 40)  return 0.60;
    else if (levelNumber < 80)  return 0.80;
    else                        return 0.92;
  }

  // ── V2: Color pair mechanic mix ───────────────────────────────────────────
  static void _mechanicMixV2(List<ArrowModel> arrows, int level, LevelType type,
      Random rng, int gridSize, List<OrphanDot> orphanDots) {
    if (arrows.length < 4) return;

    // STRICT GATE: no pairs before level 16
    if (level <= 15) return;

    int pairs;
    if (type == LevelType.god) {
      if      (level < 30)   pairs = 3;
      else if (level < 60)   pairs = (arrows.length * 0.25).floor().clamp(3, 7);
      else if (level < 150)  pairs = (arrows.length * 0.35).floor().clamp(4, 10);
      else                   pairs = (arrows.length * 0.40).floor().clamp(5, 14);
    } else if (type == LevelType.boss) {
      if      (level < 30)   pairs = 2;
      else if (level < 60)   pairs = (arrows.length * 0.20).floor().clamp(2, 5);
      else if (level < 150)  pairs = (arrows.length * 0.28).floor().clamp(3, 8);
      else                   pairs = (arrows.length * 0.35).floor().clamp(4, 12);
    } else if (level == 2) {
      pairs = 1;
    } else {
      // Normal levels >= 16: AT LEAST 1 PAIR
      if      (level < 25)   pairs = 1;
      else if (level < 45)   pairs = (arrows.length * 0.15).floor().clamp(1, 3);
      else if (level < 80)   pairs = (arrows.length * 0.22).floor().clamp(2, 5);
      else if (level < 150)  pairs = (arrows.length * 0.28).floor().clamp(3, 8);
      else if (level < 300)  pairs = (arrows.length * 0.32).floor().clamp(4, 10);
      else                   pairs = (arrows.length * 0.38).floor().clamp(5, 14);
    }

    pairs = pairs.clamp(1, 15); // Max 15 color pairs hard cap

    if (level == 395 || level == 437) pairs = 0;
    if (pairs == 0) return;

    final orphanMap = <String, OrphanDotType>{};
    for (final od in orphanDots) { orphanMap[od.key] = od.type; }

    // PERF (behaviour-identical): a pair is only accepted when BOTH arrows have
    // a fully clear exit ray. That property depends only on paths (which never
    // change while pairing), so compute it once instead of rebuilding a
    // whole-board cell set for every candidate pair. On a 100%-filled board
    // most arrows are blocked, which previously made this O(arrows^2 * cells).
    final Set<String> allCellsOnce = <String>{};
    for (final a in arrows) {
      for (final pt in a.path) { allCellsOnce.add('${pt[0]},${pt[1]}'); }
    }
    final List<bool> rayClear = List<bool>.generate(arrows.length,
        (i) => _simulateExitClear(arrows[i], gridSize, allCellsOnce, orphanMap));

    // ── Edge vs Center arrow classification ──────────────────────────────────
    // Edge distance <= edgeThreshold is Edge; > edgeThreshold is Center.
    final edgeThreshold = (gridSize <= 12) ? 1 : (gridSize * 0.25).floor();

    final edgeIndices = <int>[];
    final centerIndices = <int>[];
    final allStdIndices = <int>[];

    for (int i = 0; i < arrows.length; i++) {
      if (arrows[i].mechanic == SnakeMechanic.standard) {
        allStdIndices.add(i);
        final dist = _edgeDistance(arrows[i].row, arrows[i].col, gridSize);
        if (dist <= edgeThreshold) {
          edgeIndices.add(i);
        } else {
          centerIndices.add(i);
        }
      }
    }
    edgeIndices.shuffle(rng);
    centerIndices.shuffle(rng);
    allStdIndices.shuffle(rng);

    int actualPairs = 0;

    // Pass 1: Primary Pairing — Pair ONE Edge Arrow with ONE Center Arrow
    for (int e = 0; e < edgeIndices.length && actualPairs < pairs; e++) {
      final li = edgeIndices[e];
      if (arrows[li].mechanic != SnakeMechanic.standard) continue;

      for (int c = 0; c < centerIndices.length; c++) {
        final ki = centerIndices[c];
        if (arrows[ki].mechanic != SnakeMechanic.standard) continue;

        if (!rayClear[li] || !rayClear[ki]) continue;

        // ── Spatial separation across canvas ──────────────────────────────
        final zone1 = (arrows[li].row * 3 ~/ gridSize, arrows[li].col * 3 ~/ gridSize);
        final zone2 = (arrows[ki].row * 3 ~/ gridSize, arrows[ki].col * 3 ~/ gridSize);
        final dist  = (arrows[li].row - arrows[ki].row).abs() +
                      (arrows[li].col - arrows[ki].col).abs();
        final minPairDist = (gridSize * 0.25).floor().clamp(2, 15);
        if (zone1 == zone2 || dist < minPairDist) continue;

        final allCells = <String>{};
        for (final a in arrows) {
          for (final pt in a.path) allCells.add('${pt[0]},${pt[1]}');
        }
        final otherThanKey  = Set<String>.from(allCells)
          ..removeAll(arrows[ki].path.map((p) => '${p[0]},${p[1]}'));
        final otherThanLock = Set<String>.from(allCells)
          ..removeAll(arrows[li].path.map((p) => '${p[0]},${p[1]}'));

        // Pairwise exit-ray gate — identical to the one Pass 2 / Pass 3 already
        // apply. Each partner's exit ray must clear every other arrow's body,
        // including its partner's. Without it Pass 1 can emit a pair whose rays
        // cross each other, which the verifier rejects as a mutual deadlock
        // (and which _greedySolve tolerates, because a pair may legitimately
        // exit across its partner's body when both leave together).
        final keyClear  = _simulateExitClear(arrows[ki], gridSize, otherThanKey,  orphanMap);
        final lockClear = _simulateExitClear(arrows[li], gridSize, otherThanLock, orphanMap);
        if (!keyClear || !lockClear) continue;

        final oldKi = arrows[ki], oldLi = arrows[li];
        arrows[ki] = arrows[ki].copyWith(
            mechanic: SnakeMechanic.colorLock, colorGroup: actualPairs);
        arrows[li] = arrows[li].copyWith(
            mechanic: SnakeMechanic.colorLock, colorGroup: actualPairs);

          final tempLevel = LevelModel(
            levelNumber: level,
            gridSize: gridSize,
            arrows: arrows,
            patternName: 'temp',
            difficulty: Difficulty.easy,
            mask: arrows
                .expand((a) => a.path.map((p) => '${p[0]},${p[1]}'))
                .toSet(),
            orphanDots: orphanDots,
          );

          final solvable = gridSize > 20
              ? _greedySolve(tempLevel) != null
              : LevelSolver.solve(tempLevel, 2000) != null;

          if (solvable) {
            actualPairs++;
            break;
          } else {
            arrows[ki] = oldKi;
            arrows[li] = oldLi;
          }
        }
      }

    // Pass 2: Secondary Pairing — Fallback if Edge+Center pool couldn't fulfill all requested pairs
    if (actualPairs < pairs) {
      for (int i = 0; i < allStdIndices.length && actualPairs < pairs; i++) {
        final li = allStdIndices[i];
        if (arrows[li].mechanic != SnakeMechanic.standard) continue;

        for (int j = i + 1; j < allStdIndices.length; j++) {
          final ki = allStdIndices[j];
          if (arrows[ki].mechanic != SnakeMechanic.standard) continue;
          if (!rayClear[li] || !rayClear[ki]) continue;

          final zone1 = (arrows[li].row * 3 ~/ gridSize, arrows[li].col * 3 ~/ gridSize);
          final zone2 = (arrows[ki].row * 3 ~/ gridSize, arrows[ki].col * 3 ~/ gridSize);
          final dist  = (arrows[li].row - arrows[ki].row).abs() +
                        (arrows[li].col - arrows[ki].col).abs();
          final minPairDist = (gridSize * 0.25).floor().clamp(2, 15);
          if (zone1 == zone2 || dist < minPairDist) continue;

          final allCells = <String>{};
          for (final a in arrows) {
            for (final pt in a.path) allCells.add('${pt[0]},${pt[1]}');
          }
          final otherThanKey  = Set<String>.from(allCells)
            ..removeAll(arrows[ki].path.map((p) => '${p[0]},${p[1]}'));
          final otherThanLock = Set<String>.from(allCells)
            ..removeAll(arrows[li].path.map((p) => '${p[0]},${p[1]}'));

          final keyClear  = _simulateExitClear(arrows[ki], gridSize, otherThanKey, orphanMap);
          final lockClear = _simulateExitClear(arrows[li], gridSize, otherThanLock, orphanMap);

          if (keyClear && lockClear) {
            final oldKi = arrows[ki], oldLi = arrows[li];
            arrows[ki] = arrows[ki].copyWith(
                mechanic: SnakeMechanic.colorLock, colorGroup: actualPairs);
            arrows[li] = arrows[li].copyWith(
                mechanic: SnakeMechanic.colorLock, colorGroup: actualPairs);

            final tempLevel = LevelModel(
              levelNumber: level,
              gridSize: gridSize,
              arrows: arrows,
              patternName: 'temp',
              difficulty: Difficulty.easy,
              mask: arrows
                  .expand((a) => a.path.map((p) => '${p[0]},${p[1]}'))
                  .toSet(),
              orphanDots: orphanDots,
            );

            final solvable = gridSize > 20
                ? _greedySolve(tempLevel) != null
                : LevelSolver.solve(tempLevel, 2000) != null;

            if (solvable) {
              actualPairs++;
              break;
            } else {
              arrows[ki] = oldKi;
              arrows[li] = oldLi;
            }
          }
        }
      }
    }

    // Pass 3: Ultimate Fallback if level >= 16 and actualPairs == 0 (Guarantee AT LEAST 1 pair!)
    if (actualPairs == 0 && (level >= 16 || level == 2)) {
      for (int i = 0; i < allStdIndices.length && actualPairs < 1; i++) {
        final li = allStdIndices[i];
        if (arrows[li].mechanic != SnakeMechanic.standard) continue;

        for (int j = i + 1; j < allStdIndices.length; j++) {
          final ki = allStdIndices[j];
          if (arrows[ki].mechanic != SnakeMechanic.standard) continue;
          if (!rayClear[li] || !rayClear[ki]) continue;

          final allCells = <String>{};
          for (final a in arrows) {
            for (final pt in a.path) allCells.add('${pt[0]},${pt[1]}');
          }
          final otherThanKey  = Set<String>.from(allCells)
            ..removeAll(arrows[ki].path.map((p) => '${p[0]},${p[1]}'));
          final otherThanLock = Set<String>.from(allCells)
            ..removeAll(arrows[li].path.map((p) => '${p[0]},${p[1]}'));

          final keyClear  = _simulateExitClear(arrows[ki], gridSize, otherThanKey, orphanMap);
          final lockClear = _simulateExitClear(arrows[li], gridSize, otherThanLock, orphanMap);

          if (keyClear && lockClear) {
            final oldKi = arrows[ki], oldLi = arrows[li];
            arrows[ki] = arrows[ki].copyWith(
                mechanic: SnakeMechanic.colorLock, colorGroup: 0);
            arrows[li] = arrows[li].copyWith(
                mechanic: SnakeMechanic.colorLock, colorGroup: 0);

            final tempLevel = LevelModel(
              levelNumber: level,
              gridSize: gridSize,
              arrows: arrows,
              patternName: 'temp',
              difficulty: Difficulty.easy,
              mask: arrows
                  .expand((a) => a.path.map((p) => '${p[0]},${p[1]}'))
                  .toSet(),
              orphanDots: orphanDots,
            );

            final solvable = gridSize > 20
                ? _greedySolve(tempLevel) != null
                : LevelSolver.solve(tempLevel, 2000) != null;

            if (solvable) {
              actualPairs++;
              break;
            } else {
              arrows[ki] = oldKi;
              arrows[li] = oldLi;
            }
          }
        }
      }
    }

    // ── Post-placement whole-system validation ──────────────────────────────
    // Every pair was validated at the moment it was added, but the greedy solve
    // run at pair-1 time cannot know which pairs will follow. Several pairs can
    // interact to form a cycle deadlock that only appears in the fully
    // assembled board. Re-simulate now that all pairs are placed; if the whole
    // system still deadlocks, demote the LAST pair (highest colorGroup) and
    // re-check, until the board is solvable or no pairs remain.
    //
    // Termination: each step removes one pair, so at worst every pair is
    // demoted and a standard-only board is solvable by construction.
    // Determinism: no re-shuffling — the same seed yields the same pair
    // selection and therefore the same demotion cascade.
    int validPairs = actualPairs;
    while (validPairs > 0) {
      final testLevel = LevelModel(
        levelNumber: level,
        gridSize: gridSize,
        arrows: arrows,
        patternName: 'validate',
        difficulty: Difficulty.easy,
        mask: arrows
            .expand((a) => a.path.map((p) => '${p[0]},${p[1]}'))
            .toSet(),
        orphanDots: orphanDots,
      );
      final greedyOk = gridSize > 20
          ? _greedySolve(testLevel) != null
          : LevelSolver.solve(testLevel, 3000) != null;
      // Second gate — the verifier's own pairwise criterion. The greedy solve
      // alone cannot catch this class of failure: _simulateExit permits a
      // pair's ray to cross its partner's body (both leave together), while the
      // verifier rejects that unconditionally.
      final noPairDeadlock = !_hasColorLockDeadlock(arrows, gridSize, orphanMap);
      if (greedyOk && noPairDeadlock) break;
      // Deadlock detected — demote the LAST pair (highest colorGroup).
      _demoteLastPair(arrows, validPairs - 1);
      validPairs--;
    }
    actualPairs = validPairs;
  }

  /// Demotes the ColorLock pair whose group id is [pairIndex] back to plain
  /// standard arrows.
  ///
  /// NOTE: `ArrowModel.copyWith` merges via `colorGroup: colorGroup ??
  /// this.colorGroup`, so passing `colorGroup: null` silently KEEPS the old
  /// value. The arrow is therefore rebuilt from scratch here so the pairing is
  /// genuinely cleared.
  static void _demoteLastPair(List<ArrowModel> arrows, int pairIndex) {
    for (int i = 0; i < arrows.length; i++) {
      if (arrows[i].colorGroup == pairIndex &&
          arrows[i].mechanic == SnakeMechanic.colorLock) {
        final a = arrows[i];
        arrows[i] = ArrowModel(
          id: a.id,
          row: a.row,
          col: a.col,
          direction: a.direction,
          state: a.state,
          isPartOfPattern: a.isPartOfPattern,
          mechanic: SnakeMechanic.standard,
          path: a.path,
        );
      }
    }
  }

  /// True when any ColorLock pair on the board has one partner's exit ray
  /// crossing the other's body — the exact condition `pregenerate_levels.dart`'s
  /// `_verifyLevel` flags as "ColorLock mutual deadlock in group N".
  static bool _hasColorLockDeadlock(List<ArrowModel> arrows, int gridSize,
      Map<String, OrphanDotType> orphanMap) {
    final groups = <int, List<int>>{};
    for (int i = 0; i < arrows.length; i++) {
      final g = arrows[i].colorGroup;
      if (g != null && arrows[i].mechanic == SnakeMechanic.colorLock) {
        groups.putIfAbsent(g, () => []).add(i);
      }
    }
    for (final members in groups.values) {
      if (members.length != 2) continue;
      final a1 = arrows[members[0]];
      final a2 = arrows[members[1]];
      final a1Cells = a1.path.map((p) => '${p[0]},${p[1]}').toSet();
      final a2Cells = a2.path.map((p) => '${p[0]},${p[1]}').toSet();
      // Verifier rejects when EITHER direction shows a ray hit.
      if (_exitRayHitsSet(a1, gridSize, a2Cells, orphanMap) ||
          _exitRayHitsSet(a2, gridSize, a1Cells, orphanMap)) {
        return true;
      }
    }
    return false;
  }

  /// Exact mirror of the verifier's `_exitPassesThroughSet`: walks [arrow]'s
  /// exit ray (redirecting at orphan dots) and reports whether it visits any
  /// cell of [targetSet]. Revisiting a cell reports false, matching the
  /// verifier. The target test deliberately runs BEFORE the dot table, so a dot
  /// sitting on a partner's body cell does not mask the hit — this is the one
  /// place where this differs from `_simulateExitClear`, which checks dots first
  /// and treats the set as a full occupancy map rather than a target set.
  static bool _exitRayHitsSet(ArrowModel arrow, int gridSize,
      Set<String> targetSet, Map<String, OrphanDotType> orphanDots) {
    ArrowDirection currentDir = arrow.direction;
    final head = arrow.path[0];
    var d = currentDir.delta;
    int nr = head[0] + d[0];
    int nc = head[1] + d[1];
    final visited = <String>{};

    while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
      final key = '$nr,$nc';
      if (visited.contains(key)) return false;
      visited.add(key);

      if (targetSet.contains(key)) return true;

      if (orphanDots.containsKey(key)) {
        final dotType = orphanDots[key]!;
        if      (dotType == OrphanDotType.up)    currentDir = ArrowDirection.up;
        else if (dotType == OrphanDotType.down)  currentDir = ArrowDirection.down;
        else if (dotType == OrphanDotType.left)  currentDir = ArrowDirection.left;
        else if (dotType == OrphanDotType.right) currentDir = ArrowDirection.right;
      }

      d = currentDir.delta;
      nr += d[0];
      nc += d[1];
    }
    return false;
  }

  // ── V2: Shape selection with no-repeat rule ────────────────────────────────
  static MaskShape _shapeFor(LevelType type, Random rng, int levelNumber) {
    switch (type) {
      case LevelType.tutorial:
        return MaskShape.square;
      case LevelType.normal:
        return MaskShape.longRectangle;

      case LevelType.boss:
        return _pickShapeWithHistory(
          MaskGeneratorV2.bossShapeNames, _bossShapeHistory, rng);

      case LevelType.god:
        return _pickShapeWithHistory(
          MaskGeneratorV2.godShapeNames, _godShapeHistory, rng);
    }
  }

  static MaskShape _pickShapeWithHistory(
      List<String> allNames,
      ListQueue<String> history,
      Random rng) {
    final available = allNames.where((n) => !history.contains(n)).toList();
    final pool = available.isEmpty ? allNames : available;
    final chosen = pool[rng.nextInt(pool.length)];
    history.addLast(chosen);
    if (history.length > _shapeHistoryMaxLen) history.removeFirst();
    return MaskShape.values.firstWhere(
      (s) => s.name == chosen,
      orElse: () => MaskShape.square,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  UNCHANGED FROM V1 — Preserved exactly for correctness
  // ═══════════════════════════════════════════════════════════════════════════

  static void _placeArrow(
    List<ArrowModel> arrows, List<List<int>> path,
    ArrowDirection dir, int levelNumber, int counter,
    Set<String> occupied, Set<int> occupiedPacked,
  ) {
    final head = path[0];
    arrows.add(ArrowModel(
      id: 'a_${levelNumber}_$counter',
      row: head[0], col: head[1],
      direction: dir,
      isPartOfPattern: true,
      path: path,
      mechanic: SnakeMechanic.standard,
    ));
    for (final pt in path) {
      occupied.add('${pt[0]},${pt[1]}');
      occupiedPacked.add(pt[0] * 1000 + pt[1]);
    }
  }

  static void _shuffleCandidatesFromCenter(
      List<_Cand> candidates, int gridSize, Random rng) {
    final centerRow = gridSize / 2;
    final centerCol = gridSize / 2;
    candidates.sort((a, b) {
      final distA = (a.row - centerRow).abs() + (a.col - centerCol).abs();
      final distB = (b.row - centerRow).abs() + (b.col - centerCol).abs();
      final scoreA = distA + a.blockedCount * 3.0 + (rng.nextDouble() * 3.0 - 1.5);
      final scoreB = distB + b.blockedCount * 3.0 + (rng.nextDouble() * 3.0 - 1.5);
      return scoreA.compareTo(scoreB);
    });
  }

  static List<_Cand> _exitCandidates(List<List<int>> maskCells,
      Set<int> occupiedPacked, int gridSize, int maxAllowedBlocks) {
    final out = <_Cand>[];
    for (final cell in maskCells) {
      final r = cell[0], c = cell[1];
      if (occupiedPacked.contains(r * 1000 + c)) continue;
      for (final dir in ArrowDirection.values) {
        final d = dir.delta;
        int nr = r + d[0], nc = c + d[1];
        int blockedCount = 0;
        while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
          if (occupiedPacked.contains(nr * 1000 + nc)) blockedCount++;
          nr += d[0]; nc += d[1];
        }
        if (blockedCount <= maxAllowedBlocks) {
          out.add(_Cand(r, c, dir, blockedCount: blockedCount));
        }
      }
    }
    return out;
  }

  /// Path growth with tangle algorithm + anti-square + self-avoiding.
  /// V2 ASSERTION: verifies no self-intersection and no U-turn in debug builds.
  static List<List<int>>? _growPath({
    required int startRow,
    required int startCol,
    required ArrowDirection exitDir,
    required Set<int> maskPacked,
    required Set<int> occupiedPacked,
    required int targetLen,
    required Random rng,
    required int gridSize,
    double tangleFactor = 0.0,
  }) {
    final exitPath = _getExitPathPacked(startRow, startCol, exitDir, gridSize);
    final path     = <List<int>>[[startRow, startCol]];
    final pathPacked = <int>{startRow * 1000 + startCol};
    int cr = startRow, cc = startCol;
    var growDir = exitDir.opposite;
    int straight = 0;

    final double turnBias   = 0.65 + tangleFactor * 0.20;
    final int    maxStraight = tangleFactor >= 0.7 ? 2 : 3;

    for (int step = 1; step < targetLen; step++) {
      final valid = <ArrowDirection>[];
      for (final d in ArrowDirection.values) {
        if (d == growDir.opposite) continue;
        final nd = d.delta;
        final nr = cr + nd[0], nc = cc + nd[1];
        final np = nr * 1000 + nc;
        if (!maskPacked.contains(np)) continue;
        if (occupiedPacked.contains(np)) continue;
        if (exitPath.contains(np)) continue;
        if (pathPacked.contains(np)) continue;

        // Anti-square: reject if new cell touches any path cell other than current
        bool wouldFormLoop = false;
        for (final nb in [[-1,0],[1,0],[0,-1],[0,1]]) {
          final adjP = (nr + nb[0]) * 1000 + (nc + nb[1]);
          if (adjP != cr * 1000 + cc && pathPacked.contains(adjP)) {
            wouldFormLoop = true; break;
          }
        }
        if (wouldFormLoop) continue;
        valid.add(d);
      }
      if (valid.isEmpty) break;

      if (step == 1 && !valid.contains(growDir)) return null;

      final mustTurn  = straight >= maxStraight;
      final turns     = valid.where((d) => d != growDir).toList();
      final straights = valid.where((d) => d == growDir).toList();

      ArrowDirection chosen;
      if (step == 1) {
        chosen = growDir;
      } else if (mustTurn && turns.isNotEmpty) {
        chosen = _packedPick(turns, cr, cc, occupiedPacked, rng);
      } else if (valid.length == 1) {
        chosen = valid[0];
      } else if (rng.nextDouble() < turnBias && turns.isNotEmpty) {
        chosen = _packedPick(turns, cr, cc, occupiedPacked, rng);
      } else if (straights.isNotEmpty) {
        chosen = straights[0];
      } else {
        chosen = _packedPick(turns, cr, cc, occupiedPacked, rng);
      }

      straight = chosen == growDir ? straight + 1 : 0;
      final nd = chosen.delta;
      cr += nd[0]; cc += nd[1];
      path.add([cr, cc]);
      pathPacked.add(cr * 1000 + cc);
      growDir = chosen;
    }

    final result = path.length >= 2 ? path : null;

    // ── V2 Debug Assertion: self-avoiding verification ────────────────────────
    assert(() {
      if (result == null) return true;
      final seen = <int>{};
      for (int i = 0; i < result.length; i++) {
        final pk = result[i][0] * 1000 + result[i][1];
        assert(!seen.contains(pk),
          'V2: Self-intersection at step $i (row=${result[i][0]}, col=${result[i][1]})');
        seen.add(pk);
        if (i >= 2) {
          final dr1 = result[i-1][0] - result[i-2][0];
          final dc1 = result[i-1][1] - result[i-2][1];
          final dr2 = result[i][0]   - result[i-1][0];
          final dc2 = result[i][1]   - result[i-1][1];
          assert(!(dr2 == -dr1 && dc2 == -dc1),
            'V2: U-turn (180° reversal) at step $i');
        }
      }
      return true;
    }());

    return result;
  }

  static ArrowDirection _packedPick(List<ArrowDirection> dirs,
      int cr, int cc, Set<int> occupiedPacked, Random rng) {
    if (dirs.length == 1) return dirs[0];
    int best = -1;
    final bestDirs = <ArrowDirection>[];
    for (final d in dirs) {
      final nd = d.delta;
      final nr = cr + nd[0], nc = cc + nd[1];
      int score = 0;
      for (final nb in [[-1,0],[1,0],[0,-1],[0,1]]) {
        if (occupiedPacked.contains((nr + nb[0]) * 1000 + (nc + nb[1]))) score++;
      }
      if (score > best) { best = score; bestDirs.clear(); bestDirs.add(d); }
      else if (score == best) bestDirs.add(d);
    }
    return bestDirs[rng.nextInt(bestDirs.length)];
  }

  static int _evalPlacement({
    required List<List<int>> maskCells,
    required Set<int> maskPacked,
    required Set<int> currentOccupiedPacked,
    required List<List<int>> newPath,
    required int gridSize,
  }) {
    final bool runLookAhead = gridSize < 20 &&
        currentOccupiedPacked.length >= maskPacked.length * 0.7;
    if (!runLookAhead) return 0;
    return _countBlockedEmptyCells(
      maskCells: maskCells,
      maskPacked: maskPacked,
      currentOccupiedPacked: currentOccupiedPacked,
      newPath: newPath,
      gridSize: gridSize,
    );
  }

  static List<List<int>>? _fallbackPlacement({
    required _LenTier wantTier,
    required List<_Cand> candidates,
    required int curVeryLongMin,
    required int curVeryLongMax,
    required int curLongMin,
    required Set<int> maskPacked,
    required Set<int> occupiedPacked,
    required int gridSize,
    required Random rng,
    required void Function(_Cand) bestCandOut,
    required void Function(int) minBlockedOut,
  }) {
    List<List<int>>? bestPath;
    int minBlocked = 9999;
    _Cand? bestCand;

    void tryTier(int Function() lenGen, int minLen) {
      for (final cand in candidates.take(15)) {
        final len  = lenGen();
        final path = _growPath(
          startRow: cand.row, startCol: cand.col, exitDir: cand.dir,
          maskPacked: maskPacked, occupiedPacked: occupiedPacked,
          targetLen: len, rng: rng, gridSize: gridSize,
        );
        if (path != null && path.length >= minLen) {
          final bc = _evalPlacement(
            maskCells: [], maskPacked: maskPacked,
            currentOccupiedPacked: occupiedPacked,
            newPath: path, gridSize: gridSize,
          );
          if (bc == 0) { bestCand = cand; bestPath = path; minBlocked = 0; return; }
          if (bc < minBlocked) { minBlocked = bc; bestCand = cand; bestPath = path; }
        }
      }
    }

    if (wantTier == _LenTier.veryLong) {
      tryTier(() {
        final longMax = max(curLongMin, curVeryLongMin - 1);
        return curLongMin + rng.nextInt(max(1, longMax - curLongMin + 1));
      }, curLongMin);
    }

    if (bestPath == null &&
        (wantTier == _LenTier.veryLong || wantTier == _LenTier.long)) {
      tryTier(() => 3 + rng.nextInt(3), 3);
    }

    if (bestCand != null) {
      bestCandOut(bestCand!);
      minBlockedOut(minBlocked);
    }
    return bestPath;
  }

  static bool _canExitClean(int headRow, int headCol, ArrowDirection dir,
      Set<int> occupiedPacked, int gridSize) {
    final d = dir.delta;
    int nr = headRow + d[0], nc = headCol + d[1];
    while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
      if (occupiedPacked.contains(nr * 1000 + nc)) return false;
      nr += d[0]; nc += d[1];
    }
    return true;
  }

  static Set<int> _getExitPathPacked(
      int startRow, int startCol, ArrowDirection exitDir, int gridSize) {
    final path = <int>{};
    final d = exitDir.delta;
    int nr = startRow + d[0], nc = startCol + d[1];
    while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
      path.add(nr * 1000 + nc);
      nr += d[0]; nc += d[1];
    }
    return path;
  }

  static int _edgeDistance(int row, int col, int gridSize) {
    return [row, gridSize - 1 - row, col, gridSize - 1 - col]
        .reduce((a, b) => a < b ? a : b);
  }

  static bool _simulateExitClear(ArrowModel arrow, int gridSize,
      Set<String> occupied, Map<String, OrphanDotType> orphanDots) {
    final myPathSet = arrow.path.map((p) => '${p[0]},${p[1]}').toSet();
    ArrowDirection currentDir = arrow.direction;
    final head = arrow.path[0];
    var d = currentDir.delta;
    int nr = head[0] + d[0], nc = head[1] + d[1];
    final visited = <String>{};

    while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
      final key = '$nr,$nc';
      if (visited.contains(key)) return false;
      visited.add(key);
      if (orphanDots.containsKey(key)) {
        final dotType = orphanDots[key]!;
        if      (dotType == OrphanDotType.up)    currentDir = ArrowDirection.up;
        else if (dotType == OrphanDotType.down)  currentDir = ArrowDirection.down;
        else if (dotType == OrphanDotType.left)  currentDir = ArrowDirection.left;
        else if (dotType == OrphanDotType.right) currentDir = ArrowDirection.right;
      } else if (occupied.contains(key) && !myPathSet.contains(key)) {
        return false;
      }
      d = currentDir.delta;
      nr += d[0]; nc += d[1];
    }
    return true;
  }

  static OrphanDotType _dotTypeForDir(ArrowDirection dir) {
    switch (dir) {
      case ArrowDirection.up:    return OrphanDotType.up;
      case ArrowDirection.down:  return OrphanDotType.down;
      case ArrowDirection.left:  return OrphanDotType.left;
      case ArrowDirection.right: return OrphanDotType.right;
    }
  }

  static _Params _paramsFor(
      int level, LevelType type, int gridSize, Set<String> mask) {
    int avgLen, arrowCount;
    if (level <= 3) {
      avgLen = 2; arrowCount = 4;
    } else {
      if (level == 395 || level == 437) {
        avgLen = 6;
      } else if (level <= 15) {
        avgLen = 3;
      } else if (level <= 50) {
        avgLen = 4;
      } else {
        avgLen = 5;
      }
      arrowCount =
          ((mask.length * 1.0) / avgLen).round().clamp(4, 300);
    }
    return _Params(arrowCount, avgLen);
  }

  static Difficulty _difficultyFor(int level, LevelType type) {
    if (type == LevelType.tutorial) return Difficulty.tutorial;
    if (type == LevelType.god)      return Difficulty.legend;
    if (type == LevelType.boss) {
      if (level <= 20)  return Difficulty.hard;
      if (level <= 50)  return Difficulty.expert;
      if (level <= 100) return Difficulty.master;
      return Difficulty.legend;
    }
    if (level <= 20)  return Difficulty.easy;
    if (level <= 50)  return Difficulty.medium;
    if (level <= 100) return Difficulty.hard;
    if (level <= 200) return Difficulty.expert;
    if (level <= 400) return Difficulty.master;
    return Difficulty.legend;
  }

  static String _nameFor(LevelType type, int level) {
    switch (type) {
      case LevelType.boss:     return 'Boss $level';
      case LevelType.god:      return 'God $level';
      case LevelType.tutorial: return 'Tutorial';
      default:                 return 'Level $level';
    }
  }

  static LevelModel _fallback(
      int levelNumber, int gridSize, Set<String> mask, LevelType type) {
    final arrows = <ArrowModel>[];
    final mid = gridSize ~/ 2;
    int i = 0;
    for (int col = 0; col < gridSize && i < 4; col++) {
      if (!mask.contains('$mid,$col')) continue;
      arrows.add(ArrowModel(
        id: 'fb_${levelNumber}_$i',
        row: mid, col: col,
        direction: ArrowDirection.right,
        isPartOfPattern: true,
        path: [[mid, col]],
      ));
      i++;
    }
    return LevelModel(
      levelNumber: levelNumber,
      gridSize: gridSize,
      arrows: arrows,
      patternName: 'fallback',
      difficulty: Difficulty.easy,
      solutionOrder: arrows.reversed.map((a) => a.id).toList(),
      mask: mask,
    );
  }

  static int _countBlockedEmptyCells({
    required List<List<int>> maskCells,
    required Set<int> maskPacked,
    required Set<int> currentOccupiedPacked,
    required List<List<int>> newPath,
    required int gridSize,
  }) {
    final newPathPacked = <int>{};
    for (final pt in newPath) newPathPacked.add(pt[0] * 1000 + pt[1]);

    bool isOccupied(int packed) =>
        currentOccupiedPacked.contains(packed) || newPathPacked.contains(packed);

    final rowsToCheck   = newPath.map((pt) => pt[0]).toSet();
    final colsToCheck   = newPath.map((pt) => pt[1]).toSet();
    final adjacentKeys  = <int>{};
    for (final pt in newPath) {
      for (final offset in [[-1,0],[1,0],[0,-1],[0,1]]) {
        adjacentKeys.add((pt[0] + offset[0]) * 1000 + (pt[1] + offset[1]));
      }
    }

    int blocked = 0;
    for (final cell in maskCells) {
      final r = cell[0], c = cell[1];
      final packed = r * 1000 + c;
      if (isOccupied(packed)) continue;
      final isNear = rowsToCheck.contains(r) || colsToCheck.contains(c) ||
          adjacentKeys.contains(packed);
      if (!isNear) continue;

      int emptyNeighbors = 0;
      for (final nb in [[-1,0],[1,0],[0,-1],[0,1]]) {
        final np = (r + nb[0]) * 1000 + (c + nb[1]);
        if (maskPacked.contains(np) && !isOccupied(np)) emptyNeighbors++;
      }
      if (emptyNeighbors == 0) { blocked += 100; continue; }

      bool hasExit = false;
      for (final dir in ArrowDirection.values) {
        final d = dir.delta;
        final backPacked = (r - d[0]) * 1000 + (c - d[1]);
        if (!maskPacked.contains(backPacked) || isOccupied(backPacked)) continue;
        int nr = r + d[0], nc = c + d[1];
        bool pathClear = true;
        while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
          if (isOccupied(nr * 1000 + nc)) { pathClear = false; break; }
          nr += d[0]; nc += d[1];
        }
        if (pathClear) { hasExit = true; break; }
      }
      if (!hasExit) blocked += 100;
    }
    return blocked;
  }

  /// P1.5 — Iterative orphan absorption to a fixpoint (density increment #1).
  ///
  /// Replaces the original single-pass absorb. It keeps extending arrow tails
  /// into adjacent empty cells until no further extension is possible. Chaining
  /// single-cell extensions is what lifts coverage above the old one-shot pass.
  ///
  /// Solvability guard: an empty cell is absorbed only when it does NOT lie on
  /// the current clear exit ray of any *other* arrow. Growing a body into
  /// another arrow's clear exit would block that arrow and risk a deadlock.
  /// The absorber's own exit is unaffected — we only grow the tail (head +
  /// direction, which define the exit ray, never change) and the runtime
  /// [_computeExitInfo] treats an arrow's own body as transparent
  /// (`other.id == arrow.id` is skipped). The final solver verification
  /// downstream remains the last safety net.
  static void _absorbOrphans(List<ArrowModel> arrows, Set<String> occupied,
      Set<int> occupiedPacked, Set<String> mask, int gridSize) {
    bool pathHas(List<List<int>> path, int r, int c) {
      for (final pt in path) {
        if (pt[0] == r && pt[1] == c) return true;
      }
      return false;
    }

    /// True when (r,c) sits on [a]'s own forward exit line (collinear with the
    /// head in [a]'s direction). Growing [a] into such a cell never blocks [a].
    bool onOwnRay(ArrowModel a, int r, int c) {
      if (a.path.length < 2) return false;
      final d = a.direction.delta;
      int nr = a.path[0][0] + d[0], nc = a.path[0][1] + d[1];
      int guard = 0;
      while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize &&
          guard++ <= gridSize) {
        if (nr == r && nc == c) return true;
        nr += d[0];
        nc += d[1];
      }
      return false;
    }

    /// How many arrows' clear exit rays currently pass through each empty cell.
    /// An arrow's own body is transparent to its ray (runtime skips self), so we
    /// trace through it and only stop at another arrow's body. Recomputed once
    /// per sweep; it only shrinks as we absorb (occupancy grows, truncating
    /// rays), so a stale value is always a safe over-estimate.
    Map<int, int> computeRayCounts() {
      final counts = <int, int>{};
      for (final a in arrows) {
        if (a.path.length < 2) continue;
        final own = <int>{};
        for (final pt in a.path) {
          own.add(pt[0] * 1000 + pt[1]);
        }
        final d = a.direction.delta;
        int nr = a.path[0][0] + d[0], nc = a.path[0][1] + d[1];
        while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
          final pk = nr * 1000 + nc;
          if (own.contains(pk)) {
            // own body — transparent, keep tracing
          } else if (occupiedPacked.contains(pk)) {
            break; // another arrow blocks here; ray ends
          } else {
            counts[pk] = (counts[pk] ?? 0) + 1;
          }
          nr += d[0];
          nc += d[1];
        }
      }
      return counts;
    }

    bool changed = true;
    while (changed) {
      changed = false;
      final rayCounts = computeRayCounts();

      // Snapshot current orphans for this sweep (packed ints).
      final orphans = <int>[];
      for (final k in mask) {
        final comma = k.indexOf(',');
        final r = int.parse(k.substring(0, comma));
        final c = int.parse(k.substring(comma + 1));
        final pk = r * 1000 + c;
        if (!occupiedPacked.contains(pk)) orphans.add(pk);
      }

      for (final pk in orphans) {
        if (occupiedPacked.contains(pk)) continue;

        final r = pk ~/ 1000;
        final c = pk % 1000;

        for (int i = 0; i < arrows.length; i++) {
          final arrow = arrows[i];
          final tail = arrow.path.last;
          if ((tail[0] - r).abs() + (tail[1] - c).abs() != 1) continue;

          // Solvability guard: skip if this cell lies on another arrow's clear
          // exit ray (its own ray does not count — self is transparent).
          int cnt = rayCounts[pk] ?? 0;
          if (cnt > 0 && onOwnRay(arrow, r, c)) cnt -= 1;
          if (cnt > 0) continue;

          // Loop / 2x2-square guard: the new tail cell must not be
          // orthogonally adjacent to any of THIS arrow's own body cells other
          // than the current tail.
          bool wouldFormLoop = false;
          if (arrow.path.length >= 3) {
            for (final nb in const [[-1, 0], [1, 0], [0, -1], [0, 1]]) {
              final adjR = r + nb[0], adjC = c + nb[1];
              if (adjR == tail[0] && adjC == tail[1]) continue;
              if (pathHas(arrow.path, adjR, adjC)) {
                wouldFormLoop = true;
                break;
              }
            }
          }
          if (wouldFormLoop) continue;

          final newPath = List<List<int>>.from(arrow.path)..add([r, c]);
          arrows[i] = arrow.copyWith(path: newPath);
          occupied.add('$r,$c');
          occupiedPacked.add(pk);
          changed = true;
          break;
        }
      }
    }
  }

  // ── Greedy solver (identical to V1) ────────────────────────────────────────

  static List<String>? _greedySolveWithMap(
      int gridSize, List<ArrowModel> arrows, Map<int, OrphanDotType> orphanMap,
      {List<int>? roundsOut}) {
    int rounds = 0;
    final board = Uint16List(gridSize * gridSize);
    for (int i = 0; i < arrows.length; i++) {
      for (final pt in arrows[i].path) {
        board[pt[0] * gridSize + pt[1]] = i + 1;
      }
    }
    final orphanTypes  = Uint8List(gridSize * gridSize);
    final orphanActive = List<bool>.filled(gridSize * gridSize, false);
    orphanMap.forEach((packed, type) {
      final r = packed ~/ 1000, c = packed % 1000;
      final idx = r * gridSize + c;
      orphanTypes[idx]  = type.index;
      orphanActive[idx] = true;
    });

    final partnerOf  = List<int>.filled(arrows.length, -1);
    final grpBuckets = <int, List<int>>{};
    for (int i = 0; i < arrows.length; i++) {
      final g = arrows[i].colorGroup;
      if (g != null) grpBuckets.putIfAbsent(g, () => []).add(i);
    }
    for (final v in grpBuckets.values) {
      if (v.length == 2) { partnerOf[v[0]] = v[1]; partnerOf[v[1]] = v[0]; }
    }

    final active    = List<bool>.filled(arrows.length, true);
    final order     = <String>[];
    int remaining   = arrows.length;
    final exitVisited = Uint16List(gridSize * gridSize);
    int exitToken   = 0;

    List<int>? tryExit(int ai, int pi) {
      exitToken++;
      ArrowDirection dir = arrows[ai].direction;
      final h = arrows[ai].path[0];
      var d = dir.delta;
      int nr = h[0] + d[0], nc = h[1] + d[1];
      final consumed = <int>[];
      while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
        final idx = nr * gridSize + nc;
        if (exitVisited[idx] == exitToken) return null;
        exitVisited[idx] = exitToken;
        if (orphanActive[idx]) {
          consumed.add(idx);
          final t = orphanTypes[idx];
          if      (t == 0) dir = ArrowDirection.up;
          else if (t == 1) dir = ArrowDirection.down;
          else if (t == 2) dir = ArrowDirection.left;
          else if (t == 3) dir = ArrowDirection.right;
        } else {
          final val = board[idx];
          if (val != 0 && val != ai + 1 && (pi == -1 || val != pi + 1)) return null;
        }
        d = dir.delta; nr += d[0]; nc += d[1];
      }
      return consumed;
    }

    void clearArrow(int idx) {
      active[idx] = false;
      remaining--;
      for (final pt in arrows[idx].path) board[pt[0] * gridSize + pt[1]] = 0;
      order.add(arrows[idx].id);
    }

    bool madeProgress = true;
    final seenGroups  = <int>{};
    while (madeProgress && remaining > 0) {
      madeProgress = false;
      rounds++;
      seenGroups.clear();
      for (int i = 0; i < arrows.length; i++) {
        if (!active[i]) continue;
        final p = partnerOf[i];
        if (p == -1) continue;
        final g = arrows[i].colorGroup!;
        if (seenGroups.contains(g)) continue;
        seenGroups.add(g);
        if (!active[p]) continue;
        final c1 = tryExit(i, p), c2 = tryExit(p, i);
        if (c1 != null && c2 != null) {
          final consumed = <int>{...c1, ...c2};
          for (final f in consumed) orphanActive[f] = false;
          clearArrow(i); clearArrow(p);
          madeProgress = true;
        }
      }
      for (int i = 0; i < arrows.length; i++) {
        if (!active[i] || partnerOf[i] != -1) continue;
        final c = tryExit(i, -1);
        if (c != null) {
          for (final f in c) orphanActive[f] = false;
          clearArrow(i);
          madeProgress = true;
        }
      }
    }
    roundsOut?.add(rounds);
    return remaining == 0 ? order : null;
  }

  static List<String>? _greedySolve(LevelModel level) {
    final orphanMap = <int, OrphanDotType>{};
    for (final od in level.orphanDots) {
      orphanMap[od.row * 1000 + od.col] = od.type;
    }
    return _greedySolveWithMap(level.gridSize, level.arrows, orphanMap);
  }

  static void _log(String msg) {
    try {
      File('attempt_log_v2.txt').writeAsStringSync(msg,
          mode: FileMode.append, flush: true);
    } catch (_) {}
  }
}

// ═══════════════════════════════════════════════════════════════════════════════
//  Internal helpers
// ═══════════════════════════════════════════════════════════════════════════════

enum _LenTier { veryLong, long, medium, short }

class _Cand {
  final int row, col, blockedCount;
  final ArrowDirection dir;
  _Cand(this.row, this.col, this.dir, {this.blockedCount = 0});
}

class _Params {
  final int arrowCount, avgLen;
  _Params(this.arrowCount, this.avgLen);
}
