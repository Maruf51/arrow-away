import 'dart:math' as math;

import 'package:flame/components.dart';
import 'package:flame/effects.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/constants.dart';
import '../../core/app_colors.dart';
import '../../data/models/arrow.dart';
import '../../data/models/level.dart';
import '../game_state.dart';
import '../../ui/renderer/PairVisuals.dart';

// ── Pair glyph unit shapes ───────────────────────────────────────────────────
// Built once at radius 1 and scaled when drawn, so the per-frame tail marker
// allocates no Path objects.
final Path _kGlyphTriangle = Path()
  ..moveTo(0, -1)
  ..lineTo(0.9, 0.7)
  ..lineTo(-0.9, 0.7)
  ..close();
final Path _kGlyphDiamond = Path()
  ..moveTo(0, -1)
  ..lineTo(1, 0)
  ..lineTo(0, 1)
  ..lineTo(-1, 0)
  ..close();

/// One flowing neon-flow liquid segment.
///
/// Stored as a NORMALISED arc-length fraction (0.0–1.0) of the body rather
/// than pixels, so it stays valid across cellSize changes and path updates
/// without needing to be regenerated.
@immutable
class _LiquidSeg {
  const _LiquidSeg(this.startFrac, this.lengthFrac);
  final double startFrac;
  final double lengthFrac;
}

/// Renders a multi-cell arrow that winds through the grid.
///
/// path[0] = HEAD (carries the arrowhead triangle, exits first)
/// path[last] = TAIL (exits last — the "rope pulled through" effect)
///
/// Tapping anywhere on the body initiates a head-first sliding exit:
/// the arrowhead pulls out in the arrow's direction, the body follows
/// segment by segment, and the tail disappears last.
///
/// Tap routing itself lives in GridComponent (it resolves the NEAREST arrow
/// to the touch and forwards the down/up/cancel events here), so the arrow
/// that was actually touched is always the one that reacts — even when the
/// hit boxes of two neighbouring arrows overlap.
///
/// LONG PRESS: holding for 300 ms shows a dashed glowing preview of the
/// arrow's exit path through any deflection dots to the board edge.
class ArrowComponent extends PositionComponent with HasPaint {
  ArrowModel arrowModel;
  double cellSize;
  final GameState gameState;
  final LevelType levelType;

  bool _isAnimating = false;
  bool _isBlockedAnimating = false;
  bool _freezeNonExitAnimations = false;
  double _blockDuration = 0.0;
  double _blockTime = 0.0;
  double _maxBlockSlide = 0.0;
  double _slideOffset = 0.0;

  // ── Long-press preview ───────────────────────────────────────────────────
  static const double _kLongPressThreshold = 0.30; // 300 ms
  double _longPressAccum = 0.0;
  bool _isTouchDown = false;
  bool _isPreviewMode = false;
  List<Offset>? _previewPath; // pixel coords from head-step-1 → off-screen
  double _previewPhase = 0.0; // marching-ants animation phase (0–1)
  double _flowPhase = 0.0; // neon-flow liquid advance (0–1 of body arc length)
  double _hintRemaining = 0.0;
  final Paint _hintPaint = Paint()..style = PaintingStyle.stroke;

  // ── Exit state ────────────────────────────────────────────────────────────
  bool _isExiting = false;
  double _exitProgress = 0.0;
  double _exitDuration = 0.35;

  /// Release-wave: exit-progress fractions (0–1 of the whole exit) at which
  /// the sliding tail vacates each body cell (see _startExitAnimation).
  ///
  /// Stored in FIRING order — tail cell first (progress 0.0), head cell last
  /// — so the values are strictly ascending and [update] can fire them with
  /// one forward cursor. Index i pairs with [_popCells] index i.
  List<double> _popProgressThresholds = const [];

  /// Body cells paired 1:1 with [_popProgressThresholds] (same order).
  List<List<int>> _popCells = const [];

  int _popCursor = 0; // next threshold index to fire

  /// Pre-built deflected exit track (farthest → head), null = straight exit
  List<Offset>? _deflectedExtension;
  Rect? _exitViewportSceneRect;
  Offset _gridSceneOffset = Offset.zero;

  // ── Caching for static paths and coordinates ─────────────────────────────
  List<Offset>? _cachedPathPx;
  List<Offset>? _cachedTrack;
  List<double>? _cachedDist;
  double? _cachedHeadDist;
  double? _cachedTailDist;
  Path? _cachedBodyPath;
  Path? _cachedCaretPath;
  Path? _cachedLiquidNeonCaretPath;
  Path? _cachedLiquidNeonFacePath;
  Path? _cachedLiquidNeonInnerPath;

  final Paint _paintBodyClassic = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;
  final Paint _paintCaretFillClassic = Paint()..style = PaintingStyle.fill;

  // ── Hoisted neon-flow paints ─────────────────────────────────────────────
  // Exactly one Paint per draw call in the neon-flow render path.
  // Only .color / .strokeWidth are mutated during render.
  final Paint _paintBodyGlow = Paint(); // soft halo (body + head)
  final Paint _paintBorder = Paint(); // white outline (body + head)
  final Paint _paintBody = Paint(); // red tube
  final Paint _paintCaretFill = Paint(); // red head
  final Paint _paintLiquid = Paint(); // fluid core (white)
  final Paint _paintInnerHead = Paint(); // white triangle inside the head

  // ── Hoisted color-lock pair marker paints ────────────────────────────────
  // Reused across every arrow every frame; only .color is mutated.
  final Paint _paintRingWhite = Paint()..style = PaintingStyle.fill;
  final Paint _paintGlyphFill = Paint()..style = PaintingStyle.fill;
  final Paint _paintGlyphStroke = Paint()
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  /// Deterministically generated once per arrow; see [_buildLiquidSegs].
  List<_LiquidSeg>? _cachedLiquidSegs;

  // ── Cached arc-length vertices of the neon-flow body path ────────────────
  // Rebuilt only when the polyline identity changes (create / path change /
  // cellSize change), then walked per frame to place the liquid segments.
  List<Offset>? _flowSource;
  List<Offset> _flowVertices = const [];
  List<double> _flowDist = const [];
  double _flowLength = 0.0;

  void _invalidateCache() {
    _cachedPathPx = null;
    _cachedTrack = null;
    _cachedDist = null;
    _cachedHeadDist = null;
    _cachedTailDist = null;
    _cachedBodyPath = null;
    _cachedCaretPath = null;
    _cachedLiquidNeonCaretPath = null;
    _cachedLiquidNeonFacePath = null;
    _cachedLiquidNeonInnerPath = null;
    _flowSource = null;
  }

  bool _arePathsEqual(List<List<int>> a, List<List<int>> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i][0] != b[i][0] || a[i][1] != b[i][1]) return false;
    }
    return true;
  }

  // Group colors for colorLock / colorKey pairs are retrieved dynamically
  // from AppColors.getGroupColor.

  ArrowComponent({
    required this.arrowModel,
    required this.cellSize,
    required this.gameState,
    this.levelType = LevelType.normal,
  }) : super(size: Vector2.all(cellSize * gameState.level.gridSize));

  void updateCellSize(double newSize) {
    cellSize = newSize;
    size = Vector2.all(newSize * gameState.level.gridSize);
    _invalidateCache();
  }

  void updateExitViewport(Rect sceneRect, Offset gridSceneOffset) {
    _exitViewportSceneRect = sceneRect;
    _gridSceneOffset = gridSceneOffset;
  }

  void setGestureFrozen(bool frozen) {
    _freezeNonExitAnimations = frozen;
  }

  // ── Hit test: tap anywhere along the arrow body ───────────────────────────

  /// True while the arrow is sliding off the board. Exiting arrows are no
  /// longer interactive, so the grid skips them when resolving a tap.
  bool get isExiting => _isExiting;

  void showHint() {
    _hintRemaining = 3.2;
  }

  @override
  bool containsLocalPoint(Vector2 point) {
    if (_isExiting) return false;
    final margin = cellSize * 0.25;
    for (final pt in arrowModel.path) {
      final cellLeft = pt[1] * cellSize - margin;
      final cellRight = (pt[1] + 1) * cellSize + margin;
      final cellTop = pt[0] * cellSize - margin;
      final cellBottom = (pt[0] + 1) * cellSize + margin;
      if (point.x >= cellLeft &&
          point.x <= cellRight &&
          point.y >= cellTop &&
          point.y <= cellBottom) {
        return true;
      }
    }
    return false;
  }

  /// Called by GridComponent when this arrow won the tap resolution.
  void onTapDown(TapDownEvent event) {
    _isTouchDown = true;
    _longPressAccum = 0.0;
  }

  /// Called by GridComponent for the pointer that tapped THIS arrow, even if
  /// the finger drifted off the body before lifting — so a tap can never be
  /// silently dropped because the release point fell between two arrows.
  void onTapUp(TapUpEvent event) {
    final wasPreview = _isPreviewMode;
    _isTouchDown = false;
    _longPressAccum = 0.0;
    _isPreviewMode = false;
    _previewPath = null;
    if (wasPreview) return; // long-press released — don’t trigger a move
    if (_isAnimating) return;
    _triggerMove();
  }

  void onTapCancel(TapCancelEvent event) {
    _isTouchDown = false;
    _longPressAccum = 0.0;
    _isPreviewMode = false;
    _previewPath = null;
  }

  void _triggerMove() {
    if (_isAnimating) return;
    _isAnimating = true;

    final result = gameState.tapArrow(arrowModel.id);
    switch (result) {
      case TapResult.exited:
        _startExitAnimation();
        break;
      case TapResult.blocked:
        _playBlockAnimation();
        break;
      case TapResult.locked:
        _playLockedAnimation();
        break;
      case TapResult.ignored:
        _isAnimating = false;
        break;
    }
  }

  // ── Exit: head-first pull-through ────────────────────────────────────────

  void _startExitAnimation() {
    if (gameState.vibrationEnabled) {
      HapticFeedback.lightImpact();
    }
    double speedMultiplier = 1.0;
    if (gameState.arrowSpeedIndex == 0) {
      speedMultiplier = 1.6; // Slow
    } else if (gameState.arrowSpeedIndex == 2) {
      speedMultiplier = 0.55; // Fast
    }

    // Build the exit track NOW so the duration can be measured against the
    // real travelled distance instead of body length. The render path reuses
    // these caches (they are the same objects the render branch fills in).
    _deflectedExtension = _buildDeflectedExtension();
    final pathPx = arrowModel.path
        .map((pt) =>
            Offset((pt[1] + 0.5) * cellSize, (pt[0] + 0.5) * cellSize))
        .toList();
    _cachedPathPx = pathPx;

    final track = <Offset>[];
    final int extCount;
    if (_deflectedExtension != null) {
      track.addAll(_deflectedExtension!);
      extCount = _deflectedExtension!.length;
    } else {
      extCount = _straightExtensionCount();
      final delta = arrowModel.direction.delta;
      final headPx = pathPx.first;
      for (int i = extCount; i >= 1; i--) {
        track.add(
            headPx + Offset(delta[1] * i * cellSize, delta[0] * i * cellSize));
      }
    }
    track.addAll(pathPx);
    _cachedTrack = track;

    final dist = <double>[0.0];
    for (int i = 1; i < track.length; i++) {
      dist.add(dist[i - 1] + (track[i] - track[i - 1]).distance);
    }
    _cachedDist = dist;
    _cachedHeadDist = dist[extCount];
    _cachedTailDist = dist.last;

    // ── Constant linear speed across ALL arrow lengths ───────────────────
    // Duration is proportional to the actual distance the body travels
    // (off-board extension + body length), so every arrow glides at the
    // same cells-per-second regardless of length. The on-board portion is
    // still proportional to body length, which is what is visible.
    final travelCells = dist.last / cellSize;
    _exitDuration = travelCells * 0.085 * speedMultiplier;
    _exitProgress = 0.0;
    _isExiting = true;

    // ── Per-cell release-wave thresholds ───────────────────────────────
    // The tail starts at arc [_cachedTailDist] and slides towards 0 while
    // [update] advances _exitProgress linearly, so body cell i (arc
    // dist[extCount + i]) is vacated exactly when the tail sweeps past it:
    //     progress_i = (tailDist - dist[extCount + i]) / tailDist
    // The TAIL cell is vacated first (progress 0) and the HEAD cell last, so
    // the cells are stored in that firing order. The previous scheme paired
    // the thresholds head-first and fired them on "remaining <= t", which
    // also satisfied every later (larger) threshold in the same frame — so
    // all dots burst at once, right as the arrow fully escaped.
    _popProgressThresholds = releaseWaveThresholds(
      trackDist: dist,
      extCount: extCount,
      bodyCells: pathPx.length,
    );
    _popCells = [
      for (int i = pathPx.length - 1; i >= 0; i--)
        <int>[arrowModel.path[i][0], arrowModel.path[i][1]],
    ];
    _popCursor = 0;

    // Clear only the shape/path caches — NOT the track caches just built
    // above (render reuses those; _invalidateCache() would discard them).
    _cachedBodyPath = null;
    _cachedCaretPath = null;
    _cachedLiquidNeonCaretPath = null;
    _cachedLiquidNeonFacePath = null;
    _cachedLiquidNeonInnerPath = null;
    _flowSource = null;
  }

  /// Exit-progress fractions (0–1) at which the sliding tail vacates each
  /// body cell, returned in FIRING order: tail cell first (0.0) … head cell
  /// last. Strictly ascending, which lets [update] fire them with one
  /// forward cursor (one dot pop per crossing).
  ///
  /// [trackDist] is the cumulative arc length of the exit track and
  /// [extCount] the number of leading extension points, i.e. body cell `i`
  /// sits at `trackDist[extCount + i]`. The tail starts at the last body
  /// cell's arc and travels towards 0, so cell `i` is vacated at
  /// `(tail - trackDist[extCount + i]) / tail`.
  @visibleForTesting
  static List<double> releaseWaveThresholds({
    required List<double> trackDist,
    required int extCount,
    required int bodyCells,
  }) {
    final tailDist = trackDist[extCount + bodyCells - 1];
    return [
      for (int i = bodyCells - 1; i >= 0; i--)
        (tailDist - trackDist[extCount + i]) / tailDist,
    ];
  }

  /// Pre-computes the full exit track for arrows that pass through orphan dots.
  /// Returns a list of Offsets from FARTHEST point → first-step-from-head,
  /// or null if the exit is a plain straight line.
  List<Offset>? _buildDeflectedExtension() {
    final orphanDots = Map<String, OrphanDotType>.from(gameState.orphanDots);
    for (final dot in gameState.getConsumedDotsForArrow(arrowModel.id)) {
      orphanDots[dot.key] = dot.type;
    }
    if (orphanDots.isEmpty) return null;

    ArrowDirection currentDir = arrowModel.direction;
    final head = arrowModel.path[0];
    final gridSize = gameState.level.gridSize;
    final pts = <Offset>[];
    var d = currentDir.delta;
    int nr = head[0] + d[0];
    int nc = head[1] + d[1];
    final visited = <String>{};
    bool hasDeflection = false;

    while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
      final key = '$nr,$nc';
      if (visited.contains(key)) break;
      visited.add(key);
      pts.add(Offset((nc + 0.5) * cellSize, (nr + 0.5) * cellSize));

      if (orphanDots.containsKey(key)) {
        final dotType = orphanDots[key]!;
        if (dotType == OrphanDotType.up) {
          hasDeflection = true;
          currentDir = ArrowDirection.up;
        } else if (dotType == OrphanDotType.down) {
          hasDeflection = true;
          currentDir = ArrowDirection.down;
        } else if (dotType == OrphanDotType.left) {
          hasDeflection = true;
          currentDir = ArrowDirection.left;
        } else if (dotType == OrphanDotType.right) {
          hasDeflection = true;
          currentDir = ArrowDirection.right;
        }
      }

      d = currentDir.delta;
      nr += d[0];
      nc += d[1];
    }

    if (!hasDeflection) return null;

    final viewport = _exitViewportSceneRect;
    if (viewport == null) {
      for (int i = 0; i <= 1; i++) {
        pts.add(Offset(
            (nc + d[1] * i + 0.5) * cellSize,
            (nr + d[0] * i + 0.5) * cellSize));
      }
    } else {
      Offset localCenter(int row, int col) =>
          Offset((col + 0.5) * cellSize, (row + 0.5) * cellSize) +
          _gridSceneOffset;
      bool isPastViewport(int row, int col) {
        final center = localCenter(row, col);
        return switch (currentDir) {
          ArrowDirection.up => center.dy < viewport.top,
          ArrowDirection.down => center.dy > viewport.bottom,
          ArrowDirection.left => center.dx < viewport.left,
          ArrowDirection.right => center.dx > viewport.right,
        };
      }

      while (!isPastViewport(nr, nc)) {
        pts.add(Offset((nc + 0.5) * cellSize, (nr + 0.5) * cellSize));
        nr += d[0];
        nc += d[1];
      }
      pts.add(Offset((nc + 0.5) * cellSize, (nr + 0.5) * cellSize));
    }

    return pts.reversed.toList(); // farthest → closest to head
  }

  /// How many extension cells the exit track needs ahead of the head.
  ///
  /// Only as far as the head has to travel to stand one full cell OUTSIDE
  /// the grid, plus a one-cell buffer for the tail to slide clear. The old
  /// value (`gridSize + 2` cells, measured from the head) made every arrow
  /// fly across up to ~10 empty cells after it had already left the board —
  /// on the LAST arrow that meant waiting almost a second after the win was
  /// visually earned (on 27×27+ boards: over two seconds). On-board travel
  /// (the part the player actually watches) is unchanged, and exit speed
  /// stays constant because [_exitDuration] is derived from the real track
  /// length.
  int _straightExtensionCount() {
    final boardClearance = straightExtensionCells(
      head: arrowModel.path[0],
      delta: arrowModel.direction.delta,
      gridSize: gameState.level.gridSize,
    );
    final viewport = _exitViewportSceneRect;
    if (viewport == null) return boardClearance;

    final head = arrowModel.path[0];
    final headCenter = Offset(
          (head[1] + 0.5) * cellSize,
          (head[0] + 0.5) * cellSize,
        ) +
        _gridSceneOffset;
    final viewportClearance = viewportExtensionCells(
      headCenter: headCenter,
      direction: arrowModel.direction,
      cellSize: cellSize,
      viewport: viewport,
    );
    return math.max(boardClearance, viewportClearance);
  }

  @visibleForTesting
  static int viewportExtensionCells({
    required Offset headCenter,
    required ArrowDirection direction,
    required double cellSize,
    required Rect viewport,
  }) {
    final distance = switch (direction) {
      ArrowDirection.up => headCenter.dy - viewport.top,
      ArrowDirection.down => viewport.bottom - headCenter.dy,
      ArrowDirection.left => headCenter.dx - viewport.left,
      ArrowDirection.right => viewport.right - headCenter.dx,
    };
    return (distance / cellSize).ceil() + 1;
  }

  /// Pure form of [_straightExtensionCount] (extracted for tests): cells
  /// from the head to one cell beyond the board edge in [delta]'s direction,
  /// plus one buffer cell.
  @visibleForTesting
  static int straightExtensionCells({
    required List<int> head,
    required List<int> delta,
    required int gridSize,
  }) {
    final cellsToClearBoard = switch ((delta[0], delta[1])) {
      (-1, 0) => head[0] + 1, // up:    row r → row -1
      (1, 0) => gridSize - head[0], // down:  row r → row gridSize
      (0, -1) => head[1] + 1, // left:  col c → col -1
      _ => gridSize - head[1], // right: col c → col gridSize
    };
    return cellsToClearBoard + 1;
  }

  // ── Block: direction-aware shake ─────────────────────────────────────────

  List<Offset> _buildBlockedExtension() {
    ArrowDirection currentDir = arrowModel.direction;
    final head = arrowModel.path[0];
    final gridSize = gameState.level.gridSize;
    final pts = <Offset>[];
    var d = currentDir.delta;
    int nr = head[0] + d[0];
    int nc = head[1] + d[1];
    final visited = <String>{};

    while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
      final key = '$nr,$nc';
      if (visited.contains(key)) break;
      visited.add(key);

      // Check if blocked by another arrow
      bool occupied = false;
      for (final other in gameState.arrows) {
        if (other.id == arrowModel.id) continue;
        if (other.state == ArrowState.sliding) continue;
        for (final pt in other.path) {
          if (pt[0] == nr && pt[1] == nc) {
            occupied = true;
            break;
          }
        }
        if (occupied) break;
      }

      if (occupied) {
        break;
      }

      pts.add(Offset((nc + 0.5) * cellSize, (nr + 0.5) * cellSize));

      if (gameState.orphanDots.containsKey(key)) {
        final dotType = gameState.orphanDots[key]!;
        if (dotType == OrphanDotType.up) {
          currentDir = ArrowDirection.up;
        } else if (dotType == OrphanDotType.down) {
          currentDir = ArrowDirection.down;
        } else if (dotType == OrphanDotType.left) {
          currentDir = ArrowDirection.left;
        } else if (dotType == OrphanDotType.right) {
          currentDir = ArrowDirection.right;
        }
      }

      d = currentDir.delta;
      nr += d[0];
      nc += d[1];
    }

    // Always add overshoot in final direction
    final lastPoint = pts.isNotEmpty
        ? pts.last
        : Offset((head[1] + 0.5) * cellSize, (head[0] + 0.5) * cellSize);
    final overshootPoint =
        lastPoint + Offset(d[1] * cellSize * 0.25, d[0] * cellSize * 0.25);
    pts.add(overshootPoint);

    return pts.reversed.toList();
  }

  void _playBlockAnimation() {
    if (gameState.vibrationEnabled) {
      HapticFeedback.mediumImpact();
    }
    _invalidateCache();

    if (_cachedPathPx == null) {
      _cachedPathPx = arrowModel.path
          .map((pt) =>
              Offset((pt[1] + 0.5) * cellSize, (pt[0] + 0.5) * cellSize))
          .toList();
    }
    final pathPx = _cachedPathPx!;
    final blockedExt = _buildBlockedExtension();
    final track = <Offset>[...blockedExt, ...pathPx];
    final dist = <double>[0.0];
    for (int i = 1; i < track.length; i++) {
      dist.add(dist[i - 1] + (track[i] - track[i - 1]).distance);
    }

    _cachedTrack = track;
    _cachedDist = dist;
    _cachedHeadDist = dist[blockedExt.length];
    _cachedTailDist = dist[blockedExt.length + arrowModel.path.length - 1];

    _maxBlockSlide = _cachedHeadDist!;
    _blockDuration = 0.12 + (blockedExt.length - 1) * 0.06;
    _blockTime = 0.0;
    _isBlockedAnimating = true;
  }

  // ── ColorLock: lateral rattle ────────────────────────────────────────────

  void _playLockedAnimation() {
    if (gameState.vibrationEnabled) {
      HapticFeedback.mediumImpact();
    }
    final ox = position.x, oy = position.y;
    add(SequenceEffect([
      MoveEffect.to(Vector2(ox + 4, oy), EffectController(duration: 0.06)),
      MoveEffect.to(Vector2(ox - 4, oy), EffectController(duration: 0.06)),
      MoveEffect.to(Vector2(ox + 3, oy), EffectController(duration: 0.05)),
      MoveEffect.to(Vector2(ox - 3, oy), EffectController(duration: 0.05)),
      MoveEffect.to(Vector2(ox, oy), EffectController(duration: 0.04)),
    ], onComplete: () => _isAnimating = false));
  }

  // ── Update ────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    if (_freezeNonExitAnimations && !_isExiting) return;
    super.update(dt);
    _hintRemaining = (_hintRemaining - dt).clamp(0.0, 3.2);

    // ── Long-press accumulator ────────────────────────────────────────────
    if (_isTouchDown && !_isAnimating && !_isExiting) {
      _longPressAccum += dt;
      if (!_isPreviewMode && _longPressAccum >= _kLongPressThreshold) {
        _isPreviewMode = true;
        _previewPath = _buildPreviewPath();
      }
    }
    if (_isPreviewMode) {
      _previewPhase = (_previewPhase + dt * 1.4) % 1.0; // march speed
    }
    if (_usesLiquidNeonSkin) {
      // Liquid segments sweep tail → head at 22% of the body per second.
      _flowPhase = (_flowPhase + dt * 0.22) % 1.0;
    }

    if (_isExiting) {
      _exitProgress += dt / _exitDuration;
      if (_exitProgress >= 1.0) {
        removeFromParent();
        gameState.handleArrowExitCompleted(arrowModel.id);
        return;
      }

      // ── Release wave: pop each grid dot as the tail vacates its cell ───
      // Thresholds are stored in FIRING order (strictly ascending, tail cell
      // first / head cell last) and paired with _popCells, so a single
      // forward cursor pops exactly one dot per crossing — a wave running
      // along the body at the same speed the arrow slides out, instead of
      // every dot bursting at once when the arrow finally escapes.
      if (_popCursor < _popProgressThresholds.length) {
        final thresholds = _popProgressThresholds;
        while (_popCursor < thresholds.length &&
            _exitProgress >= thresholds[_popCursor]) {
          final cell = _popCells[_popCursor];
          gameState.onCellPopRequested?.call(cell[0], cell[1]);
          _popCursor++;
        }
      }
    }

    if (_isBlockedAnimating) {
      _blockTime += dt;
      final half = _blockDuration / 2;
      if (_blockTime < half) {
        final t = _blockTime / half;
        _slideOffset = Curves.easeOut.transform(t) * _maxBlockSlide;
      } else if (_blockTime < _blockDuration) {
        final t = (_blockTime - half) / half;
        _slideOffset = (1.0 - Curves.easeIn.transform(t)) * _maxBlockSlide;
      } else {
        _slideOffset = 0.0;
        _isBlockedAnimating = false;
        _isAnimating = false;
        _invalidateCache();
      }
    }

    if (_isExiting || _isBlockedAnimating) {
      return; // Skip syncing if animating exit or block
    }
  }

  /// Called by the grid's single model pass instead of rescanning game state
  /// independently for every arrow each frame.
  void syncModel(ArrowModel updated) {
    if (_isExiting || _isBlockedAnimating) return;
    if (identical(updated, arrowModel)) return;

    if (updated.state == ArrowState.sliding && !_isExiting && !_isAnimating) {
      _isAnimating = true;
      _startExitAnimation();
    } else if (updated.state == ArrowState.blocked && !_isAnimating) {
      _isAnimating = true;
      _playBlockAnimation();
    }
    if (updated.state != arrowModel.state ||
        updated.direction != arrowModel.direction ||
        !_arePathsEqual(updated.path, arrowModel.path)) {
      _invalidateCache();
    }
    arrowModel = updated;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  RENDER
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void render(Canvas canvas) {
    if (arrowModel.path.isEmpty) return;

    // ── 1. Resolve pathPx ─────────────────────────────────────────────────
    if (_cachedPathPx == null) {
      _cachedPathPx = arrowModel.path
          .map((pt) =>
              Offset((pt[1] + 0.5) * cellSize, (pt[0] + 0.5) * cellSize))
          .toList();
    }
    final pathPx = _cachedPathPx!;

    final List<Offset> pts;
    final bool isAnimatingNow = _isExiting || _isBlockedAnimating;

    if (isAnimatingNow) {
      // ── 2. Build or retrieve the extended track for exit animation ─────
      if (_cachedTrack == null) {
        final delta = arrowModel.direction.delta;
        final headPx = pathPx.first;

        final track = <Offset>[];
        final int extCount;
        if (_deflectedExtension != null) {
          track.addAll(_deflectedExtension!);
          extCount = _deflectedExtension!.length;
        } else {
          extCount = _straightExtensionCount();
          for (int i = extCount; i >= 1; i--) {
            track.add(headPx +
                Offset(delta[1] * i * cellSize, delta[0] * i * cellSize));
          }
        }
        track.addAll(pathPx);
        _cachedTrack = track;

        // ── 3. Cumulative distances along the track ─────────────────────
        final dist = <double>[0.0];
        for (int i = 1; i < track.length; i++) {
          dist.add(dist[i - 1] + (track[i] - track[i - 1]).distance);
        }
        _cachedDist = dist;
        _cachedHeadDist = dist[extCount];
        _cachedTailDist = dist[extCount + arrowModel.path.length - 1];
      }

      final track = _cachedTrack!;
      final dist = _cachedDist!;
      final headDist = _cachedHeadDist!;
      final tailDist = _cachedTailDist!;

      // ── 4. Compute animated head/tail positions ──────────────────────
      final double animHead, animTail;
      if (_isExiting) {
        final traveled = (_exitProgress * tailDist).clamp(0.0, tailDist);
        animHead = (headDist - traveled).clamp(0.0, headDist);
        animTail = (tailDist - traveled).clamp(0.0, tailDist);
      } else {
        final traveled = _slideOffset.clamp(0.0, tailDist);
        animHead = (headDist - traveled).clamp(0.0, headDist);
        animTail = (tailDist - traveled).clamp(0.0, tailDist);
      }

      pts = _slice(track, dist, animHead, animTail);

      // Draw consumed orphan dots that the arrow head hasn't reached yet
      if (_isExiting) {
        final consumedDots = gameState.getConsumedDotsForArrow(arrowModel.id);
        for (final dot in consumedDots) {
          final dotPx =
              Offset((dot.col + 0.5) * cellSize, (dot.row + 0.5) * cellSize);
          double? dotDist;
          for (int i = 0; i < track.length; i++) {
            if ((track[i] - dotPx).distanceSquared < 0.01) {
              dotDist = dist[i];
              break;
            }
          }
          if (dotDist != null && animHead > dotDist) {
            _drawOrphanDot(canvas, dotPx, dot.type, cellSize);
          }
        }
      }
    } else {
      // Bypass track calculations entirely if stationary
      pts = pathPx;
    }

    if (pts.isEmpty) return;

    // ── 5. Resolve color and stroke width ───────────────────────────────
    final mainColor = _color();
    final sw = cellSize * (_usesLiquidNeonSkin ? 0.44 : 0.30);

    canvas.save();

    if (_hintRemaining > 0 && !isAnimatingNow) {
      final phase = 3.2 - _hintRemaining;
      final pulse = (math.sin(phase * math.pi * 2) + 1) / 2;
      _hintPaint
        ..color = const Color(0xFFFFD45E).withValues(alpha: 0.55 + pulse * 0.4)
        ..strokeWidth = cellSize * 0.08;
      canvas.drawCircle(
        pts.first,
        cellSize * (0.62 + pulse * 0.18),
        _hintPaint,
      );
    }

    // ── 6. Draw body ─────────────────────────────────────────────────────
    final Path bodyPath;
    if (isAnimatingNow) {
      bodyPath = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++)
        bodyPath.lineTo(pts[i].dx, pts[i].dy);
    } else {
      if (_cachedBodyPath == null) {
        final path = Path()..moveTo(pts.first.dx, pts.first.dy);
        for (int i = 1; i < pts.length; i++) path.lineTo(pts[i].dx, pts[i].dy);
        _cachedBodyPath = path;
      }
      bodyPath = _cachedBodyPath!;
    }

    if (_usesLiquidNeonSkin) {
      _drawLiquidNeonArrow(canvas, bodyPath, pts, sw);
    } else {
      _paintBodyClassic
        ..color = mainColor
        ..strokeWidth = sw;
      canvas.drawPath(bodyPath, _paintBodyClassic);

      // ── 7. Draw arrowhead at the head end (pts.first) ──────────────
      _drawHead(canvas, pts, mainColor, sw);
    }

    // ── 8. Long-press preview overlay ───────────────────────────────────
    if (_isPreviewMode) {
      final preview = _previewPath;
      if (preview != null && preview.length >= 2) {
        final isBlocked = gameState.isArrowBlocked(arrowModel.id);
        _drawPreviewPath(canvas, preview, isBlocked);
      }
    }

    canvas.restore();
  }

  // ── Arrowhead ─────────────────────────────────────────────────────────────

  void _drawHead(Canvas canvas, List<Offset> pts, Color mainColor, double sw) {
    final Path caretPath;
    final bool isAnimatingNow = _isExiting || _isBlockedAnimating;

    if (isAnimatingNow) {
      caretPath = _buildCaretPath(pts, sw);
    } else {
      if (_cachedCaretPath == null) {
        _cachedCaretPath = _buildCaretPath(pts, sw);
      }
      caretPath = _cachedCaretPath!;
    }

    _paintCaretFillClassic.color = mainColor;
    canvas.drawPath(caretPath, _paintCaretFillClassic);

    // ── Color Lock Partner Marker at Tail Node ───────────────────────────
    // (color, glyph) identifies the pair: 12 colors x 3 glyphs = 36 distinct
    // pairs, so no two pairs on a level look the same.
    final groupId = arrowModel.colorGroup;
    if (arrowModel.mechanic == SnakeMechanic.colorLock &&
        groupId != null &&
        pts.isNotEmpty) {
      final tailPx = pts.last;
      final visual = PairVisuals.resolve(groupId);
      final badgeRadius = sw * 0.90;

      // White badge behind the glyph.
      canvas.drawCircle(
        tailPx,
        badgeRadius,
        _paintRingWhite..color = Colors.white,
      );
      _drawPairGlyph(canvas, tailPx, badgeRadius, visual.color, visual.glyph);
    }
  }

  /// Draws a pair glyph inscribed in a badge of radius [r]. Uses hoisted
  /// paints and unit-scale paths, so nothing is allocated per frame.
  void _drawPairGlyph(
      Canvas canvas, Offset center, double r, Color color, PairGlyph glyph) {
    // Inscribed radius for the glyph itself (small margin inside the badge).
    final g = r * 0.62;
    switch (glyph) {
      case PairGlyph.ring:
        canvas.drawCircle(
          center,
          g * 0.85,
          _paintGlyphStroke
            ..color = color
            ..strokeWidth = r * 0.38,
        );
        break;
      case PairGlyph.triangle:
        _drawUnitGlyph(
          canvas,
          _kGlyphTriangle,
          center,
          g,
          _paintGlyphFill..color = color,
        );
        break;
      case PairGlyph.diamond:
        _drawUnitGlyph(
          canvas,
          _kGlyphDiamond,
          center,
          g,
          _paintGlyphFill..color = color,
        );
        break;
    }
  }

  void _drawUnitGlyph(
      Canvas canvas, Path unit, Offset center, double scale, Paint paint) {
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.scale(scale);
    canvas.drawPath(unit, paint);
    canvas.restore();
  }

  Path _buildCaretPath(List<Offset> pts, double sw,
      {bool liquidNeon = false, bool liquidNeonFace = false}) {
    final prev = pts.length > 1 ? pts[1] : pts.first;
    final dv = pts.first - prev;
    final len = dv.distance;

    final d = arrowModel.direction.delta;
    final dx = len > 0.01 ? dv.dx / len : d[1].toDouble();
    final dy = len > 0.01 ? dv.dy / len : d[0].toDouble();

    // The head tip position
    final tipLength = liquidNeonFace ? 0.50 : 0.46;
    final tip = pts.first +
        Offset(dx * cellSize * tipLength, dy * cellSize * tipLength);

    final hd = cellSize * (liquidNeon ? (liquidNeonFace ? 0.50 : 0.46) : 0.50);
    final hw = cellSize * (liquidNeon ? (liquidNeonFace ? 0.50 : 0.37) : 0.42);

    final base = tip - Offset(dx * hd, dy * hd);
    final px = -dy, py = dx; // perpendicular

    return Path()
      ..moveTo(base.dx + px * hw, base.dy + py * hw)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(base.dx - px * hw, base.dy - py * hw)
      ..close();
  }

  /// Builds the small white triangle that sits inside the neon-flow arrowhead,
  /// so the head reads as a proper arrow rather than a plain caret.
  Path _buildLiquidNeonInnerPath(List<Offset> pts) {
    if (pts.isEmpty) return Path();
    final prev = pts.length > 1 ? pts[1] : pts.first;
    final dv = pts.first - prev;
    final len = dv.distance;
    final d = arrowModel.direction.delta;
    final dx = len > 0.01 ? dv.dx / len : d[1].toDouble();
    final dy = len > 0.01 ? dv.dy / len : d[0].toDouble();

    // Sits fully inside the caret face: shorter reach, narrower base.
    final depth = cellSize * 0.20;
    final halfWidth = cellSize * 0.115;
    final tip = pts.first + Offset(dx * cellSize * 0.34, dy * cellSize * 0.34);
    final base = tip - Offset(dx * depth, dy * depth);
    final px = -dy, py = dx;

    return Path()
      ..moveTo(base.dx + px * halfWidth, base.dy + py * halfWidth)
      ..lineTo(tip.dx, tip.dy)
      ..lineTo(base.dx - px * halfWidth, base.dy - py * halfWidth)
      ..close();
  }

  bool get _usesLiquidNeonSkin => gameState.arrowSkin == 'liquid_neon';

  // ── Neon Flow skin ─────────────────────────────────────────────────────

  // Flat, blur-free tube layers keep the reference look inexpensive to draw.
  static const Color _liquidGlow = Color(0xFFFF1744);
  static const Color _liquidHalo = Color(0xFFFF6685);

  /// Neon Flow render path — exactly 5 draw calls per arrow:
  ///   1. Soft glow halo (body + head)
  ///   2. White border (body + head)
  ///   3. Red tube body (stroke)
  ///   4. Red head fill + inner white triangle (fill) — batched via paint reuse
  ///   5. Liquid segments (white core, stroke)
  void _drawLiquidNeonArrow(
      Canvas canvas, Path bodyPath, List<Offset> pts, double sw) {
    // Get or build caret paths.
    final Path caretPath;
    final Path caretFacePath;
    final Path innerHeadPath;
    if (_isExiting || _isBlockedAnimating) {
      caretPath = _buildCaretPath(pts, sw, liquidNeon: true);
      caretFacePath =
          _buildCaretPath(pts, sw, liquidNeon: true, liquidNeonFace: true);
      innerHeadPath = _buildLiquidNeonInnerPath(pts);
    } else {
      _cachedLiquidNeonCaretPath ??= _buildCaretPath(pts, sw, liquidNeon: true);
      _cachedLiquidNeonFacePath ??=
          _buildCaretPath(pts, sw, liquidNeon: true, liquidNeonFace: true);
      _cachedLiquidNeonInnerPath ??= _buildLiquidNeonInnerPath(pts);
      caretPath = _cachedLiquidNeonCaretPath!;
      caretFacePath = _cachedLiquidNeonFacePath!;
      innerHeadPath = _cachedLiquidNeonInnerPath!;
    }

    // Combined path for body + head (used for halo and border).
    final Path combinedPath = Path()
      ..addPath(bodyPath, Offset.zero)
      ..addPath(caretPath, Offset.zero);

    // 1. Thin linear halo (body + head) — very thin, subtle glow.
    canvas.drawPath(
        combinedPath,
        _paintBodyGlow
          ..color = _liquidHalo.withValues(alpha: 0.25)
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw * 0.35
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    // 2. White border (body + head) — thin, crisp stroke.
    canvas.drawPath(
        combinedPath,
        _paintBorder
          ..color = Colors.white.withValues(alpha: 0.9)
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw * 0.18
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    // 3. Red tube body — medium stroke.
    canvas.drawPath(
        bodyPath,
        _paintBody
          ..color = _liquidGlow
          ..style = PaintingStyle.stroke
          ..strokeWidth = sw * 0.82
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);

    // 4. Red head fill + inner white triangle (batched: same paint reused).
    canvas.drawPath(
        caretFacePath,
        _paintCaretFill
          ..color = _liquidGlow
          ..style = PaintingStyle.fill);
    canvas.drawPath(
        innerHeadPath,
        _paintInnerHead
          ..color = Colors.white
          ..style = PaintingStyle.fill);

    // 5. Liquid segments — only 1-2 short segments per arrow, white core.
    final liquidPath = _buildLiquidPath(pts);
    if (liquidPath != null) {
      canvas.drawPath(
          liquidPath,
          _paintLiquid
            ..color = Colors.white.withValues(alpha: 0.96)
            ..style = PaintingStyle.stroke
            ..strokeWidth = sw * 0.35
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round);
    }

    _drawLiquidColorLockRing(canvas, pts, sw);
  }

  // ── Liquid flow segments ──────────────────────────────────────────────────
  //
  // The body path is a polyline through cell centres, so it is cached once
  // with exact vertex distances. Each frame we only walk visible corners;
  // no PathMetric or extractPath.

  /// Rebuilds [_flowVertices] / [_flowDist] for the given polyline.
  void _rebuildFlowCache(List<Offset> pts) {
    final vertices = <Offset>[];
    final dist = <double>[];
    _flowSource = pts;

    if (pts.isEmpty) {
      _flowVertices = vertices;
      _flowDist = dist;
      _flowLength = 0;
      return;
    }

    vertices.add(pts.first);
    dist.add(0.0);

    var acc = 0.0;
    for (int i = 1; i < pts.length; i++) {
      final segmentLength = (pts[i] - pts[i - 1]).distance;
      if (segmentLength <= 0.0) continue;
      acc += segmentLength;
      vertices.add(pts[i]);
      dist.add(acc);
    }

    _flowVertices = vertices;
    _flowDist = dist;
    _flowLength = acc;
  }

  /// Index of the first sample at or after arc-length [d].
  int _flowIndexFor(double d) {
    final dist = _flowDist;
    if (dist.isEmpty) return 0;
    if (d <= 0.0) return 0;
    if (d >= _flowLength) return dist.length - 1;

    var lo = 0, hi = dist.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (dist[mid] < d) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// Exact point at arc-length [d] along the cached polyline.
  Offset _flowPointAt(double d) {
    final vertices = _flowVertices;
    if (vertices.isEmpty) return Offset.zero;
    final i = _flowIndexFor(d);
    if (i <= 0) return vertices.first;
    if (i >= vertices.length) return vertices.last;

    final d0 = _flowDist[i - 1];
    final d1 = _flowDist[i];
    final t = d1 > d0 ? (d - d0) / (d1 - d0) : 0.0;
    return Offset.lerp(vertices[i - 1], vertices[i], t)!;
  }

  /// Builds the per-arrow liquid segment layout, once.
  ///
  /// Uses `Random(arrowModel.id.hashCode())` so the layout is deterministic
  /// per arrow — the same arrow always looks the same, and nothing is
  /// regenerated per frame. Segments are stored as normalised fractions
  /// (0.0–1.0 of body arc length), so they remain correct across cellSize
  /// changes without a rebuild.
  ///
  /// Small arrows (≤3 cells): 1 segment, 8–18% of body length.
  /// Medium/large arrows: 2 segments, 6–16% each (one small, one medium).
  List<_LiquidSeg> _buildLiquidSegs() {
    // NOTE: String.hashCode is a getter (no parentheses) — it is stable
    // per string, so this seed is deterministic across runs.
    final rng = math.Random(arrowModel.id.hashCode);

    // Arrow length in cells determines segment count.
    final cellCount = arrowModel.path.length;
    final isSmall = cellCount <= 3;

    final count = isSmall ? 1 : 2; // small: 1 segment, others: 2
    final segs = <_LiquidSeg>[];

    for (var i = 0; i < count; i++) {
      // Small fluid segments: 5–20% of body length each.
      final segLen = 0.05 + rng.nextDouble() * 0.15;
      final startFrac = rng.nextDouble() * (1.0 - segLen);
      segs.add(_LiquidSeg(startFrac, segLen));
    }

    return segs;
  }

  /// Builds ONE Path containing every visible liquid segment for this frame.
  ///
  /// Segments flow from tail → head: as [_flowPhase] advances, the window
  /// start sweeps along the body and wraps around. A segment that wraps past
  /// the body end is emitted as two sub-paths in the same Path, so the whole
  /// effect still costs exactly one drawPath call.
  Path? _buildLiquidPath(List<Offset> pts) {
    if (pts.isEmpty) return null;

    // Rebuild the arc-length table only when the geometry actually changes
    // (arrow created / path changed / cellSize resized).
    if (!identical(pts, _flowSource)) {
      _rebuildFlowCache(pts);
    }
    final length = _flowLength;
    if (length <= 0.0) return null;

    final segs = _cachedLiquidSegs ??= _buildLiquidSegs();
    final path = Path();
    var any = false;

    for (final seg in segs) {
      final segLen = seg.lengthFrac * length;
      if (segLen <= 0.0) continue;

      // Path index 0 is the head, so decreasing arc distance moves tail → head.
      final start = (seg.startFrac * length - _flowPhase * length) % length;
      final wrappedStart = start < 0.0 ? start + length : start;
      final end = wrappedStart + segLen;

      if (end <= length) {
        _appendArc(path, wrappedStart, end);
        any = true;
      } else {
        // Wraps from the head back to the tail in the same Path.
        _appendArc(path, wrappedStart, length);
        _appendArc(path, 0.0, end - length);
        any = true;
      }
    }

    return any ? path : null;
  }

  /// Appends the polyline covering arc-length [from] → [to] to [path].
  void _appendArc(Path path, double from, double to) {
    if (to <= from) return;
    final start = _flowPointAt(from);
    path.moveTo(start.dx, start.dy);

    var i = _flowIndexFor(from);
    while (i < _flowVertices.length && _flowDist[i] <= to) {
      final p = _flowVertices[i];
      path.lineTo(p.dx, p.dy);
      i++;
    }

    final end = _flowPointAt(to);
    path.lineTo(end.dx, end.dy);
  }

  void _drawLiquidColorLockRing(Canvas canvas, List<Offset> pts, double sw) {
    final groupId = arrowModel.colorGroup;
    if (arrowModel.mechanic != SnakeMechanic.colorLock ||
        groupId == null ||
        pts.isEmpty) {
      return;
    }

    final tailPx = pts.last;
    final visual = PairVisuals.resolve(groupId);
    // Same (color, glyph) identity as the classic skin. The neon body stroke
    // is thicker (sw = 0.44 cell vs 0.30), so the badge scales with sw to
    // keep the same on-screen size. Only drawn on colorLock levels, so it is
    // outside the 5-call steady-state budget above.
    final double badge = sw * 0.90;
    canvas.drawCircle(
      tailPx,
      badge,
      _paintRingWhite..color = Colors.white.withValues(alpha: 0.95),
    );
    _drawPairGlyph(canvas, tailPx, badge, visual.color, visual.glyph);
  }

  // ── Long-press preview path builder & renderer ──────────────────────────

  /// Computes the pixel-space exit path from the arrow head outward,
  /// following direction-changing orphan dots, until the arrow would
  /// leave the grid. Returns a list of [Offset]s from the first cell
  /// AFTER the head to an off-screen point (so the line appears to
  /// vanish at the edge).
  List<Offset>? _buildPreviewPath() {
    final orphanDots = gameState.orphanDots;
    ArrowDirection currentDir = arrowModel.direction;
    final head = arrowModel.path[0];
    final gridSize = gameState.level.gridSize;
    final pts = <Offset>[];

    // Start directly from the center of the arrow head
    final headPx =
        Offset((head[1] + 0.5) * cellSize, (head[0] + 0.5) * cellSize);
    pts.add(headPx);

    var d = currentDir.delta;
    int nr = head[0] + d[0];
    int nc = head[1] + d[1];
    final visited = <String>{};

    while (nr >= 0 && nr < gridSize && nc >= 0 && nc < gridSize) {
      final key = '$nr,$nc';
      if (visited.contains(key)) break;
      visited.add(key);
      pts.add(Offset((nc + 0.5) * cellSize, (nr + 0.5) * cellSize));

      if (orphanDots.containsKey(key)) {
        final dotType = orphanDots[key]!;
        switch (dotType) {
          case OrphanDotType.up:
            currentDir = ArrowDirection.up;
            break;
          case OrphanDotType.down:
            currentDir = ArrowDirection.down;
            break;
          case OrphanDotType.left:
            currentDir = ArrowDirection.left;
            break;
          case OrphanDotType.right:
            currentDir = ArrowDirection.right;
            break;
          default:
            break;
        }
      }

      d = currentDir.delta;
      nr += d[0];
      nc += d[1];
    }

    // Add 2 off-screen points so the line fades cleanly past the border.
    for (int i = 1; i <= 2; i++) {
      pts.add(Offset(
          (nc + d[1] * i + 0.5) * cellSize, (nr + d[0] * i + 0.5) * cellSize));
    }

    return pts.isEmpty ? null : pts;
  }

  /// Draws the preview line as a solid glowing shadow path.
  void _drawPreviewPath(Canvas canvas, List<Offset> preview, bool isBlocked) {
    if (preview.length < 2) return;

    // Build a continuous path
    final rawPath = Path()..moveTo(preview.first.dx, preview.first.dy);
    for (int i = 1; i < preview.length; i++) {
      rawPath.lineTo(preview[i].dx, preview[i].dy);
    }

    final Color shadowColor = isBlocked
        ? const Color(0xFFFF3B30) // Shade of red for blocked shadow
        : const Color(0xFF34C759); // Shade of green for clear shadow

    final Color coreColor = isBlocked
        ? const Color(0xFFE53935) // Shade of red for blocked core line
        : const Color(0xFF2E7D32); // Shade of green for clear core line

    // --- Soft glowing shadow layer (wide, blurred) ---
    canvas.drawPath(
      rawPath,
      Paint()
        ..color = shadowColor.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.45 // Broader shadow (previously 0.32)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6.0),
    );

    // --- Core guideline layer (narrow, solid) ---
    canvas.drawPath(
      rawPath,
      Paint()
        ..color = coreColor
        ..style = PaintingStyle.stroke
        ..strokeWidth = cellSize * 0.08
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  // ── Color resolution ────────────────────────────────────────────────────

  static const List<Color> _rainbowColors = [
    Color(0xFFFF334B), // Vivid Red
    Color(0xFFFF7A00), // Vibrant Orange
    Color(0xFFFFD000), // Bright Yellow
    Color(0xFF00E676), // Electric Green
    Color(0xFF00E5FF), // Bright Cyan
    Color(0xFF2979FF), // Electric Blue
    Color(0xFFA855F7), // Royal Purple
    Color(0xFFFF2A8D), // Hot Pink
  ];

  Color _color() {
    if (arrowModel.state == ArrowState.blocked || _isBlockedAnimating) {
      return const Color(0xFFCC2200); // Vibrant red error color on block
    }
    if (arrowModel.colorGroup != null) {
      return AppColors.getGroupColor(arrowModel.colorGroup!);
    }
    if (gameState.arrowSkin == 'rainbow') {
      final seed = arrowModel.row * 7 +
          arrowModel.col * 13 +
          arrowModel.id.hashCode.abs();
      return _rainbowColors[seed % _rainbowColors.length];
    }
    return AppColors.arrowUp;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  PATH INTERPOLATION
  // ═══════════════════════════════════════════════════════════════════════════

  /// Extract the visible portion of the track between [from] and [to] distance.
  /// Returns Offsets in "head→tail" order (from = head end, to = tail end).
  List<Offset> _slice(
      List<Offset> track, List<double> dist, double from, double to) {
    if (from >= to) {
      if (from == to && track.isNotEmpty) {
        return [_lerp(track, dist, from)];
      }
      return [];
    }
    final pts = <Offset>[_lerp(track, dist, from)];
    for (int i = 0; i < dist.length; i++) {
      if (dist[i] > from && dist[i] < to) pts.add(track[i]);
    }
    pts.add(_lerp(track, dist, to));
    return pts;
  }

  Offset _lerp(List<Offset> track, List<double> dist, double s) {
    if (s <= dist.first) return track.first;
    if (s >= dist.last) return track.last;
    for (int i = 0; i < dist.length - 1; i++) {
      if (s >= dist[i] && s <= dist[i + 1]) {
        final t = (s - dist[i]) / (dist[i + 1] - dist[i]);
        return Offset.lerp(track[i], track[i + 1], t)!;
      }
    }
    return track.last;
  }

  static void _drawOrphanDot(
      Canvas canvas, Offset center, OrphanDotType type, double cs) {
    if (type == OrphanDotType.neutral)
      return; // Neutral empty dots can be left empty

    const Color baseColor = Color(0xFFFFAA00); // Gold/orange redirect plate

    // Solid dot body (plate) - enlarged to be highly visible
    canvas.drawCircle(
      center,
      cs * 0.36, // Much larger plate (72% of cell size!)
      Paint()
        ..color = baseColor
        ..style = PaintingStyle.fill,
    );

    // Darker outline for contrast
    canvas.drawCircle(
      center,
      cs * 0.36,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = cs * 0.045,
    );

    // Drawing the arrow in the middle of the gold plate
    if (type != OrphanDotType.neutral) {
      final ArrowDirection dir;
      switch (type) {
        case OrphanDotType.up:
          dir = ArrowDirection.up;
          break;
        case OrphanDotType.down:
          dir = ArrowDirection.down;
          break;
        case OrphanDotType.left:
          dir = ArrowDirection.left;
          break;
        case OrphanDotType.right:
          dir = ArrowDirection.right;
          break;
        default:
          return;
      }

      final double angle = dir.rotationRadians; // Right is 0 rad

      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(angle);

      final linePaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = cs * 0.075 // Thick lines
        ..strokeCap = StrokeCap.round;

      // Draw the arrow shaft in the middle
      canvas.drawLine(Offset(-cs * 0.22, 0), Offset(cs * 0.06, 0), linePaint);

      // Draw a large centered arrowhead pointing right
      final arrowheadPath = Path()
        ..moveTo(cs * 0.28, 0) // Tip of the arrow
        ..lineTo(cs * 0.04, -cs * 0.18) // Back corner top
        ..lineTo(cs * 0.10, 0) // Recess center point
        ..lineTo(cs * 0.04, cs * 0.18) // Back corner bottom
        ..close();

      canvas.drawPath(
        arrowheadPath,
        Paint()
          ..color = Colors.white
          ..style = PaintingStyle.fill,
      );

      canvas.restore();
    } else {
      // Draw a small solid white dot in the center of neutral dots for a
      // clean focal point
      canvas.drawCircle(
        center,
        cs * 0.075,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.85)
          ..style = PaintingStyle.fill,
      );
    }
  }
}