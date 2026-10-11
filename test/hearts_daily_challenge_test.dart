import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arrow_escape/core/constants.dart';
import 'package:arrow_escape/data/models/level.dart';
import 'package:arrow_escape/data/repositories/progress_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('fresh progress starts with 30 coins, 2 hints, and 5 hearts', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = ProgressRepository(prefs);

    expect(progress.coins, 30);
    expect(progress.hints, 2);
    expect(progress.lives, 5);
    expect(progress.maxLives, 5);
  });

  test('daily coin can be claimed once per date and resets after yesterday',
      () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = ProgressRepository(prefs);

    expect(progress.hasUnclaimedDailyCoin, isTrue);
    expect(progress.claimDailyCoin(), AppConstants.dailyFreeCoins);
    expect(progress.coins, 30 + AppConstants.dailyFreeCoins);
    expect(progress.hasUnclaimedDailyCoin, isFalse);
    expect(progress.claimDailyCoin(), 0);

    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    final yesterdayKey =
        '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
    await prefs.setString('lastDailyCoinClaimDate', yesterdayKey);
    expect(progress.hasUnclaimedDailyCoin, isTrue);
  });

  group('Daily login streak rewards', () {
    test('streak reward is claimable once and uses separate date state', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(progress.hasUnclaimedStreakReward, isTrue);
      expect(progress.claimStreakReward(), [15, 0, 0]);
      expect(progress.hasUnclaimedStreakReward, isFalse);
      expect(progress.coins, 45);
      expect(progress.claimStreakReward(), [0, 0, 0]);
      expect(progress.hasUnclaimedDailyCoin, isTrue);
    });

    test('reward table and displayed cycle day wrap after day seven', () async {
      const expectedRewards = [
        [15, 0, 0],
        [20, 0, 0],
        [25, 1, 0],
        [30, 0, 0],
        [35, 1, 0],
        [40, 0, 0],
        [60, 2, 2],
      ];

      for (var streakDay = 1; streakDay <= 8; streakDay++) {
        SharedPreferences.setMockInitialValues({'streakDays': streakDay});
        final prefs = await SharedPreferences.getInstance();
        final progress = ProgressRepository(prefs);
        final expectedDay = streakDay == 8 ? 1 : streakDay;
        expect(progress.currentStreakDayInCycle, expectedDay);
        expect(progress.currentStreakReward, expectedRewards[expectedDay - 1]);
      }
    });

    test('yesterday claim date makes the streak reward available again', () async {
      final yesterday = DateTime.now().subtract(const Duration(days: 1));
      final yesterdayKey =
          '${yesterday.year}-${yesterday.month.toString().padLeft(2, '0')}-${yesterday.day.toString().padLeft(2, '0')}';
      SharedPreferences.setMockInitialValues({
        'dailyStreakRewardClaimedDate': yesterdayKey,
      });
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(progress.hasUnclaimedStreakReward, isTrue);
    });

    test('day-seven reward adds coins, hints, and capped hearts', () async {
      SharedPreferences.setMockInitialValues({
        'streakDays': 7,
        'coins': 0,
        'hints': 0,
        'lives': 1,
      });
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(progress.claimStreakReward(), [60, 2, 2]);
      expect(progress.coins, 60);
      expect(progress.hints, 2);
      expect(progress.lives, 3);
    });

    test('streak ad bonus can be claimed once and is independent', () async {
      SharedPreferences.setMockInitialValues({'coins': 0, 'hints': 0});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(progress.hasUnclaimedStreakAdBonus, isTrue);
      expect(progress.claimStreakAdBonus(), [15, 1]);
      expect(progress.hasUnclaimedStreakAdBonus, isFalse);
      expect(progress.coins, 15);
      expect(progress.hints, 1);
      expect(progress.claimStreakAdBonus(), [0, 0]);
    });
  });

  group('Universal hearts', () {
    test('has five hearts and starts regeneration after consuming one', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(progress.maxLives, 5);
      expect(progress.lives, 5);
      expect(await progress.consumeHeart(), isTrue);
      expect(progress.lives, 4);
      expect(progress.timeUntilNextHeart, isNotNull);
      expect(prefs.getString('nextHeartAt'), isNotNull);
    });

    test('accrues a heart after ten minutes and caps at five', () async {
      final regenAt = DateTime.now().subtract(const Duration(seconds: 1));
      SharedPreferences.setMockInitialValues({
        'lives': 3,
        'nextHeartAt': regenAt.toIso8601String(),
      });
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(progress.lives, 4);
      await progress.refreshHearts();
      expect(progress.lives, 4);
    });

    test('heart purchase deducts coins and respects the cap', () async {
      SharedPreferences.setMockInitialValues({'lives': 0, 'coins': 330});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(
        await progress.purchaseHearts(
          amount: 1,
          cost: AppConstants.heartCostSingle,
        ),
        isTrue,
      );
      expect(progress.lives, 1);
      expect(progress.coins, 250);
      expect(
        await progress.purchaseHearts(
          amount: AppConstants.maxLives,
          cost: AppConstants.heartCostFullRefill,
        ),
        isTrue,
      );
      expect(progress.lives, 5);
      expect(progress.coins, 0);
    });

    test('zero hearts cannot start an attempt until refilled', () async {
      SharedPreferences.setMockInitialValues({'lives': 0, 'coins': 0});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(progress.hasLives, isFalse);
      expect(await progress.consumeHeart(), isFalse);
    });
  });

  group('Level-clear coin rewards', () {
    test('uses the specified clear, star, and replay rewards', () {
      expect(
        ProgressRepository.computeLevelCoinReward(
          levelNumber: 4,
          stars: 3,
          isFirstClear: true,
        ),
        8,
      );
      expect(
        ProgressRepository.computeLevelCoinReward(
          levelNumber: 4,
          stars: 1,
          isFirstClear: true,
        ),
        5,
      );
      expect(
        ProgressRepository.computeLevelCoinReward(
          levelNumber: 5,
          stars: 3,
          isFirstClear: true,
        ),
        23,
      );
      expect(
        ProgressRepository.computeLevelCoinReward(
          levelNumber: 5,
          stars: 2,
          isFirstClear: true,
        ),
        20,
      );
      expect(
        ProgressRepository.computeLevelCoinReward(
          levelNumber: 5,
          stars: 3,
          isFirstClear: false,
        ),
        1,
      );
    });

    test('level result storage updates total score without awarding coins',
        () async {
      SharedPreferences.setMockInitialValues({'coins': 30});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      await progress.recordLevelComplete(LevelResult(
        levelNumber: 4,
        stars: 3,
        score: 250,
        movesUsed: 8,
        livesLost: 0,
        completed: true,
        completedAt: DateTime(2026, 10, 11),
      ));

      expect(progress.totalScore, 250);
      expect(progress.coins, 30);
      expect(progress.isLevelCompleted(4), isTrue);
    });
  });

  group('Hint pricing', () {
    test('single hint and three-hint pack use the new prices', () async {
      expect(AppConstants.hintCostSingle, 100);
      expect(AppConstants.hintCostPack3, 250);

      SharedPreferences.setMockInitialValues({'coins': 350, 'hints': 0});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(await progress.purchaseHints(), isTrue);
      expect(progress.hints, 1);
      expect(progress.coins, 250);
      expect(
        await progress.purchaseHints(
          amount: 3,
          cost: AppConstants.hintCostPack3,
        ),
        isTrue,
      );
      expect(progress.hints, 4);
      expect(progress.coins, 0);
    });
  });

  group('Daily challenges', () {
    test('monthly assignments persist and daily streak counts consecutively', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);
      final month = DateTime(2026, 10, 1);
      final assignments = await progress.ensureDailyChallengesForMonth(month);
      expect(assignments, hasLength(31));
      expect(assignments.values.toSet(), hasLength(31));

      final reloaded = ProgressRepository(prefs);
      final restored = await reloaded.ensureDailyChallengesForMonth(month);
      expect(restored, assignments);

      await reloaded.recordDailyChallengeComplete('2026-10-09', 2);
      await reloaded.recordDailyChallengeComplete('2026-10-10', 3);
      expect(reloaded.dailyChallengeStreakFor(DateTime(2026, 10, 10)), 2);
      expect(AppConstants.maxGameplayLives, 3);
    });
  });
}