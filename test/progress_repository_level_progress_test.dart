import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arrow_escape/data/models/level.dart';
import 'package:arrow_escape/data/repositories/progress_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('replaying an earlier level does not lower the latest level', () async {
    SharedPreferences.setMockInitialValues({
      'currentLevel': 40,
      'highestUnlockedLevel': 40,
    });
    final prefs = await SharedPreferences.getInstance();
    final progress = ProgressRepository(prefs);

    await progress.recordLevelComplete(_completedLevel(5));

    expect(progress.currentLevel, 40);
    expect(progress.highestUnlockedLevel, 40);

    await progress.recordLevelComplete(_completedLevel(40));

    expect(progress.currentLevel, 41);
    expect(progress.highestUnlockedLevel, 41);
    expect(prefs.getInt('currentLevel'), 41);
  });
}

LevelResult _completedLevel(int levelNumber) => LevelResult(
      levelNumber: levelNumber,
      stars: 3,
      score: 100,
      movesUsed: 0,
      livesLost: 0,
      completed: true,
      completedAt: DateTime(2026),
    );
