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
}