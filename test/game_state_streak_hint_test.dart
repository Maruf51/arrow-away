import 'package:flutter_test/flutter_test.dart';

import 'package:arrow_escape/data/models/arrow.dart';
import 'package:arrow_escape/data/models/level.dart';
import 'package:arrow_escape/game/game_state.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('streak starts at the second clear tap and hint chooses a safe arrow', () {
    final level = LevelModel(
      levelNumber: 20,
      gridSize: 5,
      arrows: [
        ArrowModel(
          id: 'first',
          row: 0,
          col: 0,
          direction: ArrowDirection.left,
        ),
        ArrowModel(
          id: 'second',
          row: 4,
          col: 4,
          direction: ArrowDirection.right,
        ),
      ],
      patternName: 'test',
      difficulty: Difficulty.easy,
    );
    final gameState = GameState(
      level: level,
      onLevelComplete: () {},
      onGameOver: () {},
      onLifeLost: () {},
      onDeadlock: () {},
    );

    expect(gameState.findHintArrowId(), 'first');
    expect(gameState.lives, 3);
    expect(gameState.tapArrow('first'), TapResult.exited);
    expect(gameState.visibleTapStreak, 0);
    expect(gameState.tapArrow('second'), TapResult.exited);
    expect(gameState.visibleTapStreak, 2);
    expect(gameState.maxTapStreak, 2);
  });

  test('arrow dot progress counts unique cells and resets with the level', () {
    final level = LevelModel(
      levelNumber: 20,
      gridSize: 5,
      arrows: [
        ArrowModel(
          id: 'first',
          row: 0,
          col: 0,
          direction: ArrowDirection.right,
          path: [
            [0, 0],
            [0, 1],
          ],
        ),
        ArrowModel(
          id: 'second',
          row: 1,
          col: 0,
          direction: ArrowDirection.right,
          path: [
            [1, 0],
          ],
        ),
      ],
      patternName: 'test',
      difficulty: Difficulty.easy,
    );
    final gameState = GameState(
      level: level,
      onLevelComplete: () {},
      onGameOver: () {},
      onLifeLost: () {},
      onDeadlock: () {},
    );

    expect(gameState.totalArrowDots, 3);
    expect(gameState.arrowDotsRemaining, 3);

    gameState.handleArrowCellCleared(0, 1);
    gameState.handleArrowCellCleared(0, 1);
    expect(gameState.arrowDotsRemaining, 2);

    gameState.handleArrowCellCleared(4, 4);
    expect(gameState.arrowDotsRemaining, 2);

    gameState.resetLevel();
    expect(gameState.arrowDotsRemaining, 3);
  });
}