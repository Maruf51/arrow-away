import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_escape/data/models/arrow.dart';
import 'package:arrow_escape/data/models/level.dart';
import 'package:arrow_escape/game/components/arrow_component.dart';
import 'package:arrow_escape/game/game_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  GameState createGameState({
    required List<ArrowModel> arrows,
    List<OrphanDot> orphanDots = const [],
  }) {
    return GameState(
      level: LevelModel(
        levelNumber: 20,
        gridSize: 7,
        arrows: arrows,
        patternName: 'test',
        difficulty: Difficulty.easy,
        orphanDots: orphanDots,
      ),
      onLevelComplete: () {},
      onGameOver: () {},
      onLifeLost: () {},
      onDeadlock: () {},
    );
  }

  test('exit trace follows a deflector turn to the blocking arrow', () {
    final gameState = createGameState(
      arrows: [
        ArrowModel(
          id: 'moving',
          row: 5,
          col: 2,
          direction: ArrowDirection.up,
          path: const [
            [5, 2],
            [6, 2],
          ],
        ),
        ArrowModel(
          id: 'blocker',
          row: 3,
          col: 5,
          direction: ArrowDirection.left,
        ),
      ],
      orphanDots: const [
        OrphanDot(row: 3, col: 2, type: OrphanDotType.right),
      ],
    );

    final trace = gameState.exitTraceForArrow('moving');

    expect(gameState.isArrowBlocked('moving'), isTrue);
    expect(trace.cells, [
      [4, 2],
      [3, 2],
      [3, 3],
      [3, 4],
    ]);
    expect(trace.direction, ArrowDirection.right);
  });

  test('paired arrow is ignored while tracing its partner route', () {
    final gameState = createGameState(
      arrows: [
        ArrowModel(
          id: 'pair-a',
          row: 2,
          col: 0,
          direction: ArrowDirection.right,
          colorGroup: 1,
        ),
        ArrowModel(
          id: 'pair-b',
          row: 2,
          col: 2,
          direction: ArrowDirection.down,
          colorGroup: 1,
        ),
        ArrowModel(
          id: 'blocker',
          row: 2,
          col: 4,
          direction: ArrowDirection.left,
        ),
      ],
    );

    final trace = gameState.exitTraceForArrow('pair-a');

    expect(trace.cells, [
      [2, 1],
      [2, 2],
      [2, 3],
    ]);
    expect(trace.direction, ArrowDirection.right);
  });

  test('blocked extension visibly turns toward the obstacle after a dot', () {
    final extension = ArrowComponent.blockedExtensionPoints(
      cells: const [
        [3, 1],
        [3, 2],
      ],
      head: const [3, 0],
      direction: ArrowDirection.down,
      cellSize: 20,
    );

    expect(extension.first, const Offset(50, 80));
    expect(extension[1], const Offset(50, 70));
  });

}
