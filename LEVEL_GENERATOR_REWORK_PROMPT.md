# PROMPT — Rework the Arrow Escape Level Generator for Full-Board Fill

> Copy everything from "ROLE" to the end into a strong coding model. It is self-contained.

---

## ROLE

You are a senior Dart/Flutter game engineer. You will rewrite the level generator for the
puzzle game **Arrow Escape** so that every generated level's board is **densely packed with
arrows** (looks "full") instead of being littered with large empty-looking regions, while
**guaranteeing every level stays solvable** under the exact runtime rules below.

The code you produce must be drop-in compatible with the existing project. Do not change the
runtime game engine (`game_state.dart`, `arrow_component.dart`, `grid_component.dart`), the data
models, or the binary codec — only the generator (and you may add helper files).

---

## OBJECTIVE (single most important thing)

Today the board only *looks* full when you count invisible "neutral" orphan dots. Measured on
the 500 shipped levels: **arrow-body coverage averages 86.6% (median 87.2%, max 93.4%); 0 levels
reach 100% arrow coverage; ~13% of cells on average are orphan dots, and the majority of those
are NEUTRAL (invisible), which render as empty board space.**

Rework the generator so that:
- **Arrow-body coverage of the playable mask is maximized — target >= 97% for normal levels and
  >= 98% for Boss/God levels** (the mask, not the full square grid).
- **Neutral (invisible) orphan dots are driven toward zero** (target <= 3% of cells, ideally 0).
- Any cell that is NOT an arrow body should, wherever possible, be a **colored direction
  deflector dot** that is part of some arrow's exit path (i.e., gameplay-relevant, visible, and
  load-bearing), not cosmetic filler.
- **Every level remains solvable** and **deadlock-free**, verified with the SAME rules the
  runtime uses.

---

## HARD RULE — READ FIRST (why literal 100% is impossible)

Literal 100% arrow coverage is **mathematically unsolvable** in this game and you must NOT
produce it. Reason: when an arrow is fired, `GameState._computeExitInfo` traces a ray from the
arrow head in its `direction`; if **any other arrow's body cell** lies on that ray, the move is
BLOCKED. If every cell is an arrow body, every exit ray is blocked -> no first move exists ->
instant deadlock. Therefore there must always remain a set of free cells and/or dots that form a
valid clear-order.

So the objective is: **maximum feasible arrow density with a guaranteed solvable clear-order**,
NOT literal 100%. Use free cells and deflector dots as the "breathing room" that makes a
clear-order exist, and make those remaining cells as few and as gameplay-meaningful as possible.

---

## GAME MECHANICS — SOURCE OF TRUTH (implement solvability against THIS, exactly)

Board = `gridSize x gridSize`. A `mask: Set<String>` of `"row,col"` keys defines the playable
cells (square / long-rectangle for normal levels; silhouette shapes for Boss/God).

Each arrow (`ArrowModel`):
- `path: List<List<int>>` — `path[0]` is the HEAD (has the arrowhead); consecutive cells are
  orthogonally adjacent (differ by exactly 1 in row OR col); path is self-avoiding (no repeats,
  no 180 deg U-turns, no closed squares).
- `direction: ArrowDirection` — points AWAY from `path[1]`, i.e. the direction the head slides
  out of the board.
- `mechanic: SnakeMechanic` — `standard` or `colorLock`.
- `colorGroup: int?` — two arrows sharing a non-null `colorGroup` are a **color pair**: they are
  fired together and BOTH exit rays must be clear when ignoring each other.

Firing / exit simulation (`_computeExitInfo` semantics — reproduce this EXACTLY in your solver):
```
dir = arrow.direction
(r, c) = arrow.path[0]            // head
step one cell in dir
visited = {}
while inside grid:
    key = "r,c"
    if key in visited: return BLOCKED          // deflection loop
    visited.add(key)
    if key is an orphan dot:
        consume it
        if dot is up/down/left/right: dir = that direction   // deflect
        if dot is neutral: pass through (no turn)
    else if key is covered by another arrow's body:
        return BLOCKED
    advance one cell in dir
return EXIT_OK
```
- Color pair: compute exit for each of the two arrows while ignoring the other; if either is
  blocked, the pair is blocked.
- WIN = all arrows exited. DEADLOCK = no arrow can legally move.
- Deflector dots are CONSUMED (removed) the first time an arrow traverses them.


---

## DATA MODELS — EXACT (do not change)

`lib/data/models/arrow.dart`:
```dart
enum ArrowDirection { up, down, left, right }   // up=[-1,0] down=[1,0] left=[0,-1] right=[0,1]
enum SnakeMechanic { standard, colorLock }
enum ArrowState { idle, sliding, blocked, exited, locked }

class ArrowModel {
  final String id; int row; int col; ArrowDirection direction; ArrowState state;
  bool isPartOfPattern; final List<List<int>> path; // path[0]=head
  final SnakeMechanic mechanic; final int? colorGroup;
}
```
`lib/data/models/level.dart`:
```dart
enum OrphanDotType { up, down, left, right, neutral }   // neutral index = 4
class OrphanDot { final int row; final int col; final OrphanDotType type; }
class LevelModel {
  final int levelNumber; final int gridSize; final List<ArrowModel> arrows;
  final String patternName; final Difficulty difficulty; final MaskShape maskShape;
  final Set<String> mask; final List<OrphanDot> orphanDots; final List<String> solutionOrder;
  LevelModel copyWith({...}); // NOTE: copyWith merges colorGroup via `colorGroup ?? old`,
                              // so passing colorGroup:null KEEPS the old value.
}
enum MaskShape { square, longRectangle, heart, star, diamond, hexagon, blob, circle,
                 cat, dog, frog, fox, tiger, panda, fish, bird, butterfly, /* boss/god set */ }
enum Difficulty { tutorial, easy, medium, hard, expert, master, legend }
```

---

## LEVEL SCHEDULE & PARAMS — MUST PRESERVE (from lib/core/constants.dart)

- Grid sizes: tutorial 10x10; normal 15x15 (L4) -> 24x24 (L19), 25x25 (L20) -> 35x35 (L500);
  Boss/God 27x27 -> 40x40 over ~20 cycles. Special overrides: L213->32, L395->35, L437->36.
- Type cadence (7-cycle after 3 tutorials): positions 1-3 Normal, 4 Boss, 5-6 Normal, 7 God.
  (`pos = ((level - 3 - 1) % 7) + 1`; pos 7 = god, pos 4 = boss.)
- Tangle factor (max zig-zag): L4-6 ~0.50, L7-12 ~0.70, L13-20 ~0.85, L21+ 1.0;
  Boss +0.20, God +0.30 (clamped <= 1.0).
- Deflector color probability (colored vs neutral dots): 0 before L21; then ramps
  (normal ~0.60 -> 0.92; boss ~0.70 -> 0.92; god ~0.80 -> 0.95). Gate color PAIRS off before L16.
- Color-pair counts scale by level & type (Boss >= 1, God >= 2; normal ramps 1 -> 6). Colored
  deflectors must keep a minimum Manhattan spacing (current: `clamp(gridSize*0.20, 2, 6)`)
  from other colored deflectors; too-close ones degrade to neutral.
- Determinism: `Random(seed)` with `seed = levelNumber * 7919 + 314159`. Same level number ->
  identical output. Tutorial levels 1-3 are hand-authored straight arrows (keep them, but you MAY
  raise their density too).
- Keep the no-repeat shape history for Boss/God (last 5 shapes each) if you keep shape variety.

---

## CURRENT GENERATOR — HOW IT WORKS & WHY IT UNDER-FILLS (context)

File: `lib/data/level_generator/level_generator_v2.dart`. Pipeline: mask -> Phase 1 (place
VeryLong/Long/Medium/Short arrows, each requiring a clean exit at placement time) -> Phase 2
(2-cell fill sweep, capped by `_phase2MaxFill` in [0.80, 0.98], each pair must pass `_canExitClean`)
-> `_absorbOrphans` (extends an arrow tail by ONE isolated adjacent cell only) -> Phase 3 (color
remaining empty cells as deflector/neutral dots) -> mechanic mix (color pairs) -> verify
(greedy sim for gridSize>20, DFS `LevelSolver.solve` for <= 20).

Root causes of the sparse look:
1. Phase 1 bails as soon as no >=3-cell arrow fits with a clean exit.
2. Phase 2 is capped well below full and demands clean exits.
3. `_absorbOrphans` is minimal (one cell, adjacency-only).
4. Look-ahead `_evalPlacement` only runs for `gridSize < 20` above 70% occupancy, so large grids
   (most of the game) get no push to pack tighter.
5. Leftovers become NEUTRAL dots (invisible) -> empty appearance.

Existing helper interfaces you can reuse or replace (current signatures):
- `MaskGeneratorV2.shapeByName(String name, int gridSize, Random rng) -> Set<String>`
- `LevelSolver.solve(LevelModel level, int timeLimitMs) -> List<String>?` (DFS clear-order)
- greedy sim: `_greedySolveWithMap(int gridSize, List<ArrowModel> arrows, Map<int,OrphanDotType>)`
- deflector-aware pair exit check: `_simulateExitClear(arrow, gridSize, occupied, orphanDots)`



---

## WHAT THE NEW GENERATOR MUST DO

1. **Backwards construction, but keep packing.** Place arrows from a cleared board so solvability
   is structural, but do NOT stop early. When a tight region can't fit a multi-cell arrow, still
   consume it productively:
   - Prefer extending an existing arrow tail into the gap when it preserves the clear-order.
   - Prefer turning the cell into a colored deflector that lies on some arrow's exit ray.
   - Only fall back to a neutral dot when neither is possible, and minimize these.
2. **Maximize density.** Target arrow coverage >= 97% (normal) / >= 98% (Boss/God) of the mask;
   neutral dots <= 3%. Track and report these metrics per level.
3. **Guarantee solvability with runtime-exact rules.** After building, run the deflector-aware
   exit simulation + greedy clear-order (gridSize>20) and DFS `LevelSolver.solve` (<= 20). If no
   clear-order exists, relax (free up a minimal set of cells / demote the last color pair) and
   retry — never ship a deadlock.
4. **Preserve everything in "LEVEL SCHEDULE & PARAMS"** (grid sizes, cadence, tangle, dot color
   probability, pair counts, deflector spacing, determinism seed, hand-authored tutorials).
5. **Performance.** Levels are generated in a background isolate; grids go up to 40x40 (1600
   cells). Whole-level generation must stay fast (target < ~1-2s per level; use typed data /
   packed int keys like `row*1000+col`, avoid per-cell allocation in hot loops).
6. **Output contract.** Return a valid `LevelModel` that encodes cleanly through
   `lib/data/level_binary_codec.dart` (delta-encoded paths, mask bitmask, deflector dots) and is
   consumable by `LevelRepository`. Do not break `fromJson/toJson` or the `.bin` pipeline.
7. **No engine changes.** Solvability must hold under the UNCHANGED `game_state.dart` exit logic.

---

## INTEGRATION POINTS (exact — wire your new code here)

- Entry: `static LevelModel generateLevel(int levelNumber)` in `LevelGeneratorV2`
  (keep this class name + method; `LevelRepository` calls it in an isolate).
- Repository: `lib/data/repositories/level_repository.dart` calls
  `LevelGeneratorV2.generateLevel(n)`; it loads `assets/levels.bin` first, else generates.
- Codec: `lib/data/level_binary_codec.dart` (encode/decode arrows, mask, dots).
- Masks: `lib/data/level_generator/mask_generator_v2.dart`.
- Rendering (do not change, but respect): neutral dots draw only the faint background dot;
  colored dots draw an orange deflector. Arrow cells draw the arrow.

---

## ACCEPTANCE CRITERIA / VERIFICATION (your output must satisfy all)

For a sample of levels across all type bands (early normal, mid, late, boss, god, L213/395/437):
1. Arrow-body coverage of mask >= 97% (normal) / >= 98% (boss/god); report the actual numbers.
2. Neutral orphan dots <= 3% of mask cells (target 0); leftover cells are colored deflectors.
3. `LevelSolver.solve(...)` (<= 20) or greedy clear-order (> 20) returns a NON-NULL solution.
4. No deadlock: from the initial board there is at least one legal first move, and the clear-order
   empties the board.
5. Color pairs: both arrows' exit rays are clear when ignoring each other (no mutual block).
6. Colored deflectors keep the minimum Manhattan spacing rule.
7. Every arrow path is self-avoiding: no repeated cells, no 180 deg U-turn, no closed square;
   `direction` points away from `path[1]`.
8. Deterministic: same `levelNumber` -> byte-identical `LevelModel`.
9. The existing verify pipeline still passes:
   `test/verify_helpers.dart`, `test/verify_chunk_helper.dart`, `test/verify_final_bin_test.dart`,
   and the chunked `run_verify.ps1` -> `assets/levels.bin` build (`test/build_levels_bin_test.dart`).
10. Provide a small Dart/CLI or test harness that prints, per level: `arrowCoverage%`,
    `neutralDot%`, `deflectorDot%`, `solvable (bool)`, `genTimeMs`.

---

## DELIVERABLE FORMAT

Return:
1. The rewritten generator (single file preferred: keep `LevelGeneratorV2.generateLevel`, or a
   new file + thin shim), fully compiling Dart — no placeholders, no TODOs.
2. Any new helper files.
3. The verification harness described above.
4. A short note listing the achieved coverage % and solvability across a representative sample.

Constraints: match existing code style (Dart, `static` helpers, packed-int cell keys, `_log` for
debug), only use packages already in the project (`dart:math`, `dart:typed_data`,
`dart:collection`, `dart:convert`). Do not add new dependencies. Do not modify the engine,
models, or codec.

