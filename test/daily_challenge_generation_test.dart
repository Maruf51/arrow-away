import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arrow_escape/data/repositories/level_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('daily challenge generates a separate board and persists it by date',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repository = LevelRepository(prefs);
    final stopwatch = Stopwatch()..start();

    final generated = await repository.getDailyChallengeLevelAsync(
      dateKey: '2026-10-11',
      seed: 87654321,
    );
    stopwatch.stop();

    expect(generated.levelNumber, 480);
    expect(generated.gridSize, 21);
    expect(generated.arrows, isNotEmpty);
    expect(prefs.getString('daily_challenge_level_2026-10-11'), isNotNull);

    final restoredRepository = LevelRepository(prefs);
    final synchronouslyRestored =
      restoredRepository.getCachedDailyChallengeLevel('2026-10-11');
    expect(synchronouslyRestored, isNotNull);
    expect(synchronouslyRestored!.toJson(), generated.toJson());
    final restored = await restoredRepository.getDailyChallengeLevelAsync(
      dateKey: '2026-10-11',
      seed: 123,
    );
    expect(restored.toJson(), generated.toJson());
    final nextDate = await repository.getDailyChallengeLevelAsync(
      dateKey: '2026-10-12',
      seed: 12345678,
    );
    expect(nextDate.arrows.map((arrow) => arrow.path.toString()).toList(),
        isNot(generated.arrows.map((arrow) => arrow.path.toString()).toList()));
    // Keep timing visible in test output without a flaky wall-clock threshold.
    // ignore: avoid_print
    print('Daily challenge first generation: ${stopwatch.elapsedMilliseconds}ms');
  });
}