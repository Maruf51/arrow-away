import 'dart:async';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../data/models/level.dart';
import 'components/grid_component.dart';
import 'game_state.dart';

class ArrowPuzzleGame extends FlameGame {
  // ── State ─────────────────────────────────────────────────────────────────────
  final LevelModel level;
  final GameState gameState;
  GridComponent? gridComponent;

  // ── Callbacks to Flutter ──────────────────────────────────────────────────────
  final void Function() onLevelComplete;
  final void Function() onGameOver;
  final void Function() onLifeLost;
  Rect? _exitViewportSceneRect;

  ArrowPuzzleGame({
    required this.level,
    required this.gameState,
    required this.onLevelComplete,
    required this.onGameOver,
    required this.onLifeLost,
  });

  @override
  Color backgroundColor() => Colors.transparent;

  @override
  Future<void> onLoad() async {
    final (gridSize, gridX, gridY) = _calcLayout(size);

    gridComponent = GridComponent(
      gameState: gameState,
      gridPixelSize: gridSize,
      position: Vector2(gridX, gridY),
    );
    final viewport = _exitViewportSceneRect;
    if (viewport != null) {
      gridComponent!.updateExitViewportSceneRect(viewport);
    }

    add(gridComponent!);
  }

  @override
  void onGameResize(Vector2 size) {
    super.onGameResize(size);

    final (gridSize, gridX, gridY) = _calcLayout(size);

    if (gridComponent != null) {
      gridComponent!.position = Vector2(gridX, gridY);
      gridComponent!.resize(gridSize);
      final viewport = _exitViewportSceneRect;
      if (viewport != null) {
        gridComponent!.updateExitViewportSceneRect(viewport);
      }
    }
  }

  void updateExitViewportSceneRect(Rect sceneRect) {
    _exitViewportSceneRect = sceneRect;
    gridComponent?.updateExitViewportSceneRect(sceneRect);
  }

  (double gridSize, double gridX, double gridY) _calcLayout(Vector2 screenSize) {
    final levelType = AppConstants.levelTypeFor(level.levelNumber);
    // Clamp scale to 1.0: values > 1.0 make gridPixelWidth > screenSize,
    // giving a negative gridX so edge cells fall outside the Flutter SizedBox
    // and their touch events get clipped. canvasScaleForType can still be set
    // > 1.0 for visual zoom by the InteractiveViewer, not the Flame layout.
    final scale = AppConstants.canvasScaleForType(levelType).clamp(0.1, 1.0);

    double activeCols = level.gridSize.toDouble();
    double activeRows = level.gridSize.toDouble();

    if (level.mask.isNotEmpty) {
      int minR = 999, maxR = -1, minC = 999, maxC = -1;
      for (final cell in level.mask) {
        final parts = cell.split(',');
        final r = int.parse(parts[0]);
        final c = int.parse(parts[1]);
        if (r < minR) minR = r;
        if (r > maxR) maxR = r;
        if (c < minC) minC = c;
        if (c > maxC) maxC = c;
      }
      if (minR <= maxR && minC <= maxC) {
        activeRows = (maxR - minR + 1).toDouble();
        activeCols = (maxC - minC + 1).toDouble();
      }
    }

    final maxW = screenSize.x * scale;
    final maxH = screenSize.y * scale;

    final cellW = maxW / activeCols;
    final cellH = maxH / activeRows;
    final cellSize = cellW < cellH ? cellW : cellH;

    final gridPixelWidth  = level.gridSize * cellSize;
    final gridPixelHeight = level.gridSize * cellSize;

    final gridX = (screenSize.x - gridPixelWidth) / 2;
    final gridY = (screenSize.y - gridPixelHeight) / 2;

    return (gridPixelWidth, gridX, gridY);
  }

  // ── Gesture freeze ───────────────────────────────────────────────────────────
  // The board is zoomed/panned by a Flutter InteractiveViewer wrapped AROUND the
  // game, so while a pinch/pan is running the Flutter side only needs to
  // re-composite the last frame at the new transform. Re-running update() and
  // render() for every arrow on every one of those frames is pure waste on a
  // weak CPU. Freezing the engine for the duration of the gesture removes that
  // work; the last frame stays on screen and the game resumes when the finger
  // lifts.
  bool _gestureFrozen = false;
  int _freezeToken = 0;

  void setGestureFrozen(bool frozen) {
    if (frozen == _gestureFrozen) return;
    _gestureFrozen = frozen;
    final token = ++_freezeToken;
    if (frozen) {
      pauseEngine();
      // Failsafe: never leave the game frozen if an end event is ever missed.
      Future<void>.delayed(const Duration(seconds: 8), () {
        if (_gestureFrozen && token == _freezeToken) setGestureFrozen(false);
      });
    } else {
      resumeEngine();
    }
  }

  /// Reset board to initial state (restart level)
  void resetLevel() {
    gameState.resetLevel();
    gridComponent?.rebuild();
  }
}
