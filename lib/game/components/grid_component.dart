import 'dart:async';
import 'dart:ui' as ui;
import 'package:flame/components.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/app_colors.dart';
import '../../data/models/level.dart';
import '../../data/models/arrow.dart';
import '../game_state.dart';
import 'arrow_component.dart';

/// Renders the puzzle grid, mask boundary dots, and all arrow components.
///
/// Tap routing happens HERE rather than on each arrow: Flame hands a tap to
/// the top-most component containing the point, which picks an arbitrary
/// (last-added) arrow whenever two expanded hit boxes overlap. Instead the
/// grid resolves the arrow whose body is CLOSEST to the touch, remembers it
/// for the lifetime of the pointer, and forwards down/up/cancel to it — so
/// the arrow the player actually touched reacts, and a tap can't be lost
/// when the finger drifts between two arrows before lifting.
///
/// IMPORTANT: the mask used for RENDERING must match the mask used when the
/// level was generated.  We regenerate it from the stored [MaskShape] so we
/// never drift between generator and renderer.
class GridComponent extends PositionComponent with TapCallbacks {
  final GameState gameState;
  double gridPixelSize;

  final Map<String, ArrowComponent> _arrowComponents = {};
  late Set<String> _mask;
  late LevelType _levelType;

  ui.Image? _cachedDotGridImage;
  static final Paint _dotGridPaint = Paint();
  bool _isRecachingDotGrid = false;
  int _dotGridCacheGeneration = 0;
  bool _isDarkCached = AppColors.isDark;

  // ── Release-wave pop animation (arrow-escape "release" effect) ──────────
  // cell key "r,c" -> elapsed seconds since pop started
  final Map<String, double> _poppingCells = {};
  // Gentle: the ring stays small and takes its time — a soft ripple, not a
  // shockwave (was 0.35 s with a ring growing to 55% of the cell).
  static const double _popDurationSec = 0.55;
  static const double _popPeakScale = 1.85;

  // ── Tap routing ─────────────────────────────────────────────────────────────
  /// pointer id -> the arrow that received this pointer's onTapDown.
  /// The same arrow always receives the matching onTapUp/onTapCancel, no
  /// matter where the finger has drifted to in the meantime.
  final Map<int, ArrowComponent> _pointerTargets = {};

  /// How far (as a fraction of a cell) a tap may land from an arrow's body
  /// cell and still count as a hit on it. Generous enough that sloppy taps
  /// land, tight enough that plain empty board space stays inert.
  static const double _tapReachInCells = 0.35;

  /// Hoisted paint for the pop overlay — one Paint reused across all pops
  /// and every frame; never constructed inside render().
  final Paint _popPaint = Paint()..style = PaintingStyle.fill;

  static final Paint _orphanPlatePaint = Paint()
    ..color = const Color(0xFFFFAA00)
    ..style = PaintingStyle.fill;

  static final Paint _orphanOutlinePaint = Paint()
    ..color = Colors.black.withValues(alpha: 0.18)
    ..style = PaintingStyle.stroke;

  static final Paint _orphanLinePaint = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  static final Paint _orphanArrowFill = Paint()
    ..color = Colors.white
    ..style = PaintingStyle.fill;

  static final Path _orphanArrowPath = Path()
    ..moveTo(0.28, 0.0)
    ..lineTo(0.04, -0.18)
    ..lineTo(0.10, 0.0)
    ..lineTo(0.04, 0.18)
    ..close();

  void _invalidateDotGrid() {
    _dotGridCacheGeneration++;
    _cachedDotGridImage?.dispose();
    _cachedDotGridImage = null;
  }

  @override
  void onRemove() {
    _invalidateDotGrid();
    _pointerTargets.clear();
    gameState.onCellPopRequested = null;
    super.onRemove();
  }

  GridComponent({
    required this.gameState,
    required this.gridPixelSize,
    required Vector2 position,
  }) : super(position: position);

  double get cellSize => gridPixelSize / gameState.level.gridSize;

  @override
  Future<void> onLoad() async {
    size = Vector2.all(gridPixelSize);
    _levelType = AppConstants.levelTypeFor(gameState.level.levelNumber);
    _refreshMask();
    _buildArrows();
    gameState.onCellPopRequested = triggerCellPop;
  }

  // ── Tail-cell pop ─────────────────────────────────────────────────────────

  /// Starts a release-wave pop on the grid dot at [row],[col].
  /// Called via GameState.onCellPopRequested by ArrowComponent, once per
  /// body cell, at the moment the exiting tail vacates that cell — so only
  /// the dot the arrow just left animates, as a wave running along the body.
  /// Only cells inside the mask will actually render a pop (the render
  /// pass skips keys not present in the mask, so empty cells never pop).
  void triggerCellPop(int row, int col) {
    _poppingCells['$row,$col'] = 0.0;
  }

  // ── Tap routing ─────────────────────────────────────────────────────────────
  //
  // The grid covers the whole board, so it is the component Flame delivers
  // taps to (the arrows themselves are no longer TapCallbacks). It resolves
  // which arrow was actually touched and keeps it for the whole pointer
  // sequence: the arrow that received onTapDown is guaranteed to receive the
  // matching onTapUp / onTapCancel.

  @override
  void onTapDown(TapDownEvent event) {
    final target = _resolveArrow(event.localPosition);
    if (target == null) return;
    _pointerTargets[event.pointerId] = target;
    target.onTapDown(event);
  }

  @override
  void onTapUp(TapUpEvent event) {
    final target = _pointerTargets.remove(event.pointerId);
    target?.onTapUp(event);
  }

  @override
  void onTapCancel(TapCancelEvent event) {
    final target = _pointerTargets.remove(event.pointerId);
    target?.onTapCancel(event);
  }

  /// The arrow whose body cell is closest to [point] (grid-local pixels),
  /// or null when no arrow is within the tap reach ([_tapReachInCells]).
  ArrowComponent? _resolveArrow(Vector2 point) {
    final candidates = <ArrowComponent>[];
    final paths = <List<List<int>>>[];
    for (final arrow in gameState.arrows) {
      final comp = _arrowComponents[arrow.id];
      if (comp == null || comp.isExiting) continue; // arrows already leaving
      candidates.add(comp);
      paths.add(arrow.path);
    }
    if (candidates.isEmpty) return null;
    final index = resolveArrowIndex(paths, point, cellSize);
    return index < 0 ? null : candidates[index];
  }

  /// Pure hit-resolution used by [_resolveArrow]: returns the index of the
  /// arrow whose nearest body cell is closest to [point] (squared-distance
  /// comparison), or -1 when every arrow is farther than the tap reach.
  ///
  /// Two hit boxes can overlap — arrows sitting in neighbouring cells expand
  /// into each other — so "does this point hit the arrow" is the wrong
  /// question; "which arrow is this point closer to" always answers the
  /// way the player sees it. Exact ties are broken by cell centre and then
  /// by list order, so the result is deterministic.
  @visibleForTesting
  static int resolveArrowIndex(
    List<List<List<int>>> paths,
    Vector2 point,
    double cellSize,
  ) {
    final reach = cellSize * _tapReachInCells;
    final reachSq = reach * reach;

    int bestIndex = -1;
    double bestSq = double.infinity;
    double bestCenterSq = double.infinity;

    for (int a = 0; a < paths.length; a++) {
      double cellSq = double.infinity;
      double centerSq = double.infinity;

      for (final cell in paths[a]) {
        final left = cell[1] * cellSize;
        final right = left + cellSize;
        final top = cell[0] * cellSize;
        final bottom = top + cellSize;

        final dx = point.x < left
            ? left - point.x
            : (point.x > right ? point.x - right : 0.0);
        final dy = point.y < top
            ? top - point.y
            : (point.y > bottom ? point.y - bottom : 0.0);
        final dSq = dx * dx + dy * dy;

        final centerX = (cell[1] + 0.5) * cellSize;
        final centerY = (cell[0] + 0.5) * cellSize;
        final cx = point.x - centerX;
        final cy = point.y - centerY;
        final cSq = cx * cx + cy * cy;

        if (dSq < cellSq) {
          cellSq = dSq;
          centerSq = cSq;
        } else if (dSq == cellSq && cSq < centerSq) {
          centerSq = cSq;
        }
      }

      if (cellSq > reachSq) continue; // too far from this arrow
      if (cellSq < bestSq || (cellSq == bestSq && centerSq < bestCenterSq)) {
        bestIndex = a;
        bestSq = cellSq;
        bestCenterSq = centerSq;
      }
    }
    return bestIndex;
  }

  // ── Mask ──────────────────────────────────────────────────────────────────

  /// Rebuilds the mask from the stored MaskShape on the level model.
  /// Uses a deterministic seed derived from level + shape so the shape
  /// is always the same instance for this level (blob needs a seed).
  void _refreshMask() {
    _mask = gameState.level.mask;
  }

  // ── Arrow components ──────────────────────────────────────────────────────

  void _buildArrows() {
    removeAll(children.whereType<ArrowComponent>());
    _arrowComponents.clear();

    for (final arrow in gameState.arrows) {
      final comp = ArrowComponent(
        arrowModel: arrow,
        cellSize: cellSize,
        gameState: gameState,
        levelType: _levelType,
      )..position = Vector2(0, 0);
      _arrowComponents[arrow.id] = comp;
      add(comp);
    }
  }

  void rebuild() {
    _refreshMask();
    _buildArrows();
    _poppingCells.clear();
    _pointerTargets.clear();
    _invalidateDotGrid();
  }

  /// Previous grid pixel size, used to detect a real resize vs a spurious
  /// onGameResize call that re-runs on every widget rebuild (Flame's
  /// GameWidget calls onGameResize from a LayoutBuilder, which rebuilds
  /// whenever parent setState fires — e.g. after an arrow escapes).
  ///
  /// Without a tolerance, resize() would invalidate the cached dot-grid
  /// image on every arrow escape and the async recache would leave the
  /// board without dots for a frame or more — the visible "flicker".
  double _lastGridPixelSize = -1;

  static const double _resizeEpsilonPx = 0.5;

  void resize(double newGridPixelSize) {
    final sizeChanged =
        (_lastGridPixelSize < 0) ||
            ((gridPixelSize - newGridPixelSize).abs() > _resizeEpsilonPx);

    gridPixelSize = newGridPixelSize;
    size = Vector2.all(gridPixelSize);
    for (final child in children) {
      if (child is ArrowComponent) child.updateCellSize(cellSize);
    }

    if (sizeChanged) {
      _lastGridPixelSize = newGridPixelSize;
      _invalidateDotGrid();
    }
  }

  Future<void> _recacheDotGrid() async {
    final gridSize = gameState.level.gridSize;
    final cs = cellSize;
    final dimPx = (gridSize * cs).ceil();
    if (dimPx <= 0) return;

    _isRecachingDotGrid = true;
    final generation = _dotGridCacheGeneration;

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);

    final baseDot = (cs * 0.045).clamp(0.6, 1.6);

    final inPaint = Paint()
      ..color = AppColors.isDark ? const Color(0x3CFFFFFF) : const Color(0xFFC8BFB0)
      ..style = PaintingStyle.fill;

    for (int row = 0; row < gridSize; row++) {
      for (int column = 0; column < gridSize; column++) {
        if (!_mask.contains('$row,$column')) continue;

        canvas.drawCircle(
          Offset((column + 0.5) * cs, (row + 0.5) * cs),
          baseDot,
          inPaint,
        );
      }
    }

    final picture = recorder.endRecording();
    try {
      final image = await picture.toImage(dimPx, dimPx);
      if (generation != _dotGridCacheGeneration) {
        image.dispose();
        return;
      }
      _cachedDotGridImage = image;
    } finally {
      picture.dispose();
      _isRecachingDotGrid = false;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  //  RENDER
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  void render(Canvas canvas) {
    final cs = cellSize;

    if (_isDarkCached != AppColors.isDark) {
      _isDarkCached = AppColors.isDark;
      _invalidateDotGrid();
    }
    if (_cachedDotGridImage == null && !_isRecachingDotGrid) {
      unawaited(_recacheDotGrid());
    }
    final image = _cachedDotGridImage;
    if (image != null) {
      canvas.drawImage(image, Offset.zero, _dotGridPaint);
    }

    // ── Orphan deflector dots (drawn on top of background dots) ────────────
    final orphanDots = gameState.orphanDots;
    for (final entry in orphanDots.entries) {
      final parts = entry.key.split(',');
      final dotR = int.parse(parts[0]);
      final dotC = int.parse(parts[1]);
      _drawOrphanDot(canvas, Offset((dotC + 0.5) * cs, (dotR + 0.5) * cs),
          entry.value, cs);
    }    // ── Release-wave pop overlay (drawn after dots + orphans, before children ─
    if (_poppingCells.isNotEmpty) {
      final baseDot = (cs * 0.045).clamp(0.6, 1.6);
      final dotColor =
          AppColors.isDark ? const Color(0xC0FFFFFF) : const Color(0xFFB8AF9E);
      final dotColorFaint = dotColor.withValues(alpha: 0.45);
      final ringColor = AppColors.isDark
          ? const Color(0x88FFFFFF)
          : const Color(0xFFB8AF9E).withValues(alpha: 0.75);

      _poppingCells.forEach((key, elapsed) {
        final parts = key.split(',');
        final pr = int.parse(parts[0]);
        final pc = int.parse(parts[1]);
        if (!_mask.contains(key)) return; // only cells actually in the mask

        final t = (elapsed / _popDurationSec).clamp(0.0, 1.0);
        // Radial release: ring expands from the dot outward and fades, while
        // the dot itself flares bright then fades back to normal.
        final wobble = 1.0 - t;
        final flareScale = 1.0 + (_popPeakScale - 1.0) * wobble * wobble;

        final cx = (pc + 0.5) * cs;
        final cy = (pr + 0.5) * cs;
        final center = Offset(cx, cy);

        // 1. Fading flare dot on top of the static dot.
        _popPaint.color = t < 0.5 ? dotColor : dotColorFaint;
        canvas.drawCircle(center, baseDot * flareScale, _popPaint);

        // 2. Expanding ring — 9% of cell size, growing to 29% while fading
        //    (kept deliberately small so neighbouring dots stay readable).
        final ringT = t.clamp(0.0, 1.0);
        _popPaint.color = ringColor.withValues(
            alpha: ringColor.a * (1.0 - ringT) * (1.0 - ringT));
        canvas.drawCircle(
          center,
          cs * (0.09 + 0.20 * ringT),
          _popPaint..style = PaintingStyle.stroke
            ..strokeWidth = cs * 0.040 * (1.0 - ringT * 0.5),
        );
        _popPaint.style = PaintingStyle.fill; // reset for next pop entry
      });
    }

    super.render(canvas);
  }

  static void _drawOrphanDot(
      Canvas canvas, Offset center, OrphanDotType type, double cs) {
    if (type == OrphanDotType.neutral) return;

    canvas.drawCircle(center, cs * 0.36, _orphanPlatePaint);

    _orphanOutlinePaint.strokeWidth = cs * 0.045;
    canvas.drawCircle(center, cs * 0.36, _orphanOutlinePaint);

    final ArrowDirection direction;
    switch (type) {
      case OrphanDotType.up:
        direction = ArrowDirection.up;
        break;
      case OrphanDotType.down:
        direction = ArrowDirection.down;
        break;
      case OrphanDotType.left:
        direction = ArrowDirection.left;
        break;
      case OrphanDotType.right:
        direction = ArrowDirection.right;
        break;
      default:
        return;
    }

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(direction.rotationRadians);

    _orphanLinePaint.strokeWidth = cs * 0.075;
    canvas.drawLine(
        Offset(-cs * 0.22, 0), Offset(cs * 0.06, 0), _orphanLinePaint);

    canvas.save();
    canvas.scale(cs);
    canvas.drawPath(_orphanArrowPath, _orphanArrowFill);
    canvas.restore();

    canvas.restore();
  }

  // ── Update ────────────────────────────────────────────────────────────────

  @override
  void update(double dt) {
    // ── Advance tail-cell pops ──────────────────────────────────────────
    if (_poppingCells.isNotEmpty) {
      final done = <String>[];
      for (final entry in _poppingCells.entries) {
        final t = entry.value + dt;
        if (t >= _popDurationSec) {
          done.add(entry.key);
        } else {
          _poppingCells[entry.key] = t;
        }
      }
      for (final k in done) {
        _poppingCells.remove(k);
      }
    }

    final arrows = gameState.arrows;
    if (_arrowComponents.length != arrows.length) {
      final current = arrows.map((a) => a.id).toSet();
      final gone =
          _arrowComponents.keys.where((id) => !current.contains(id)).toList();
      for (final id in gone) {
        _arrowComponents[id]?.removeFromParent();
        _arrowComponents.remove(id);
      }
    }
    for (final arrow in arrows) {
      _arrowComponents[arrow.id]?.syncModel(arrow);
    }
    super.update(dt);
  }
}
