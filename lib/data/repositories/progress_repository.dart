import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import '../models/level.dart';
import '../../core/constants.dart';
import '../../core/audio_manager.dart';

class ProgressRepository extends ChangeNotifier {
  final SharedPreferences? _prefs;

  // ── State fields ────────────────────────────────────────────────────────────
  int _lives = AppConstants.maxLives;
  DateTime? _nextHeartAt;
  int _currentLevel = 1;
  int _highestUnlockedLevel = 1;
  int _totalScore = 0;
  int _coins = 30;
  String? _lastDailyCoinClaimDate;
  String? _dailyStreakRewardClaimedDate;
  String? _dailyStreakAdBonusClaimedDate;

  // Streak
  int _streakDays = 0;
  DateTime? _lastPlayedDate;

  // Level results
  final Map<int, LevelResult> _levelResults = {};

  // Settings
  bool _soundEnabled = true;
  bool _musicEnabled = true;
  bool _vibrationEnabled = true;
  bool _timeLimitEnabled = true;
  ThemeMode _themeMode = ThemeMode.system;
  bool _showFps = false;

  // 40x40 warning state
  bool _hasSeen40x40Warning = false;

  // Zoom hint state
  bool _hasSeenZoomHint = false;

  // Demo Mode
  bool _isDemoMode = false;

  // Skins & Hints
  String _equippedSkin = 'classic'; // 'classic', 'rainbow', or 'liquid_neon'
  int _hints = 2;
  String? _dailyChallengeMonth;
  int _dailyChallengeVersion = 0;
  Map<int, int> _dailyChallengeSeeds = {};
  final Map<String, int> _dailyChallengeResults = {};

  // Arrow exit speed: 0=Slow, 1=Normal, 2=Fast
  int _arrowSpeedIndex = 1; // default Normal

  // ── Getters ──────────────────────────────────────────────────────────────────
  bool get isDemoMode => _isDemoMode;
  String get equippedSkin => _equippedSkin;
  int get hints => _hints;
  int get arrowSpeedIndex => _arrowSpeedIndex;
  int get lives => _isDemoMode ? 999 : _effectiveHeartCount;
  int get maxLives => AppConstants.maxLives;
  int get currentLevel => _currentLevel;
  int get highestUnlockedLevel => _isDemoMode ? 500 : _highestUnlockedLevel;
  int get totalScore => _totalScore;
  int get coins => _coins;
  bool get hasUnclaimedDailyCoin {
    final stored =
        _prefs?.getString('lastDailyCoinClaimDate') ?? _lastDailyCoinClaimDate;
    return stored == null || stored != _todayKey();
  }

  bool get hasUnclaimedStreakReward {
    final stored = _prefs?.getString('dailyStreakRewardClaimedDate') ??
        _dailyStreakRewardClaimedDate;
    return stored != _todayKey();
  }

  bool get hasUnclaimedStreakAdBonus {
    final stored = _prefs?.getString('dailyStreakAdBonusClaimedDate') ??
        _dailyStreakAdBonusClaimedDate;
    return stored != _todayKey();
  }

  int get currentStreakDayInCycle {
    final streak = _streakDays < 1 ? 1 : _streakDays;
    return ((streak - 1) % 7) + 1;
  }

  List<int> get currentStreakReward =>
      AppConstants.dailyStreakRewards[currentStreakDayInCycle - 1];
  int get streakDays => _streakDays;
  DateTime? get lastPlayedDate => _lastPlayedDate;
  bool get hasLives => _isDemoMode || lives > 0;
  bool get livesAreFull => _isDemoMode || lives >= AppConstants.maxLives;
  int get _effectiveHeartCount {
    if (_isDemoMode ||
        _nextHeartAt == null ||
        DateTime.now().isBefore(_nextHeartAt!)) {
      return _lives;
    }
    final elapsed = DateTime.now().difference(_nextHeartAt!);
    final restored = 1 +
        elapsed.inSeconds ~/ AppConstants.heartRegenerationInterval.inSeconds;
    return (_lives + restored).clamp(0, AppConstants.maxLives);
  }

  Duration? get timeUntilNextHeart {
    if (_isDemoMode || livesAreFull || _nextHeartAt == null) return null;
    final restored = _effectiveHeartCount - _lives;
    final next =
        _nextHeartAt!.add(AppConstants.heartRegenerationInterval * restored);
    final remaining = next.difference(DateTime.now());
    return remaining.isNegative ? Duration.zero : remaining;
  }

  bool get dailyChallengeCompletedToday =>
      _dailyChallengeResults.containsKey(dailyChallengeDateKey(DateTime.now()));
  int get dailyChallengeStreak =>
      _calculateDailyChallengeStreak(DateTime.now());
  int dailyChallengeStreakFor(DateTime date) =>
      _calculateDailyChallengeStreak(date);

  bool get soundEnabled => _soundEnabled;
  bool get musicEnabled => _musicEnabled;
  bool get vibrationEnabled => _vibrationEnabled;
  bool get timeLimitEnabled => _timeLimitEnabled;
  ThemeMode get themeMode => _themeMode;
  bool get showFps => _showFps;
  bool get hasSeen40x40Warning => _hasSeen40x40Warning;
  bool get hasSeenZoomHint => _hasSeenZoomHint;

  int getStarsForLevel(int level) => _levelResults[level]?.stars ?? 0;

  bool isLevelUnlocked(int level) {
    if (_isDemoMode) return true;
    return level <= _highestUnlockedLevel;
  }

  void toggleDemoMode() {
    _isDemoMode = !_isDemoMode;
    notifyListeners();
  }

  bool isLevelCompleted(int level) => _levelResults.containsKey(level);

  ProgressRepository([this._prefs]) {
    _load();
  }

  // ── Load / Save ──────────────────────────────────────────────────────────────

  void _load() {
    if (_prefs == null) return;
    try {
      _lives = (_prefs!.getInt('lives') ?? AppConstants.maxLives)
          .clamp(0, AppConstants.maxLives);
      final nextHeartAt = _prefs!.getString('nextHeartAt');
      _nextHeartAt =
          nextHeartAt == null ? null : DateTime.tryParse(nextHeartAt);
      if (nextHeartAt == null && _prefs!.getInt('lives') == 3) {
        _lives = AppConstants.maxLives;
      } else if (_lives < AppConstants.maxLives && _nextHeartAt == null) {
        _nextHeartAt =
            DateTime.now().add(AppConstants.heartRegenerationInterval);
      }
      _currentLevel = _prefs!.getInt('currentLevel') ?? 1;
      _highestUnlockedLevel = _prefs!.getInt('highestUnlockedLevel') ?? 1;
      _totalScore = _prefs!.getInt('totalScore') ?? 0;
      _coins = _prefs!.getInt('coins') ?? 30;
      _streakDays = _prefs!.getInt('streakDays') ?? 0;

      _soundEnabled = _prefs!.getBool('soundEnabled') ?? true;
      _musicEnabled = _prefs!.getBool('musicEnabled') ?? true;
      _vibrationEnabled = _prefs!.getBool('vibrationEnabled') ?? true;
      _timeLimitEnabled = _prefs!.getBool('timeLimitEnabled') ?? true;
      _hasSeen40x40Warning = _prefs!.getBool('hasSeen40x40Warning') ?? false;
      _hasSeenZoomHint = _prefs!.getBool('hasSeenZoomHint') ?? false;
      _showFps = _prefs!.getBool('showFps') ?? false;
      _equippedSkin = _prefs!.getString('equippedSkin') ?? 'classic';
      _hints = _prefs!.getInt('hints') ?? 2;
      _dailyChallengeMonth = _prefs!.getString('dailyChallengeMonth');
      _dailyChallengeVersion = _prefs!.getInt('dailyChallengeVersion') ?? 0;
      final dailyLevels = _prefs!.getString('dailyChallengeLevels');
      if (dailyLevels != null) {
        _dailyChallengeSeeds = (jsonDecode(dailyLevels) as Map<String, dynamic>)
            .map((key, value) => MapEntry(int.parse(key), value as int));
      }
      final dailyResults = _prefs!.getString('dailyChallengeResults');
      if (dailyResults != null) {
        _dailyChallengeResults.addAll(
          (jsonDecode(dailyResults) as Map<String, dynamic>)
              .map((key, value) => MapEntry(key, value as int)),
        );
      }
      _arrowSpeedIndex = _prefs!.getInt('arrowSpeedIndex') ?? 1;

      final themeStr = _prefs!.getString('themeMode') ?? 'system';
      _themeMode = ThemeMode.values.firstWhere(
        (e) => e.name == themeStr,
        orElse: () => ThemeMode.system,
      );

      // Synchronize to AudioManager
      AudioManager.instance.setSoundEnabled(_soundEnabled);
      AudioManager.instance.setMusicEnabled(_musicEnabled);

      final lastPlayedStr = _prefs!.getString('lastPlayedDate');
      if (lastPlayedStr != null) {
        _lastPlayedDate = DateTime.tryParse(lastPlayedStr);
      }

      final resultsJson = _prefs!.getString('levelResults');
      if (resultsJson != null) {
        final Map<String, dynamic> map = jsonDecode(resultsJson);
        for (final entry in map.entries) {
          final level = int.tryParse(entry.key);
          if (level != null) {
            _levelResults[level] =
                LevelResult.fromJson(entry.value as Map<String, dynamic>);
          }
        }
      }

      // Check streak
      _updateStreak();
    } catch (e) {
      debugPrint('Error loading progress from SharedPreferences: $e');
    }
  }

  Future<void> _save() async {
    if (_prefs == null) return;
    try {
      await Future.wait([
        _prefs!.setInt('lives', _lives),
        if (_nextHeartAt != null)
          _prefs!.setString('nextHeartAt', _nextHeartAt!.toIso8601String())
        else
          _prefs!.remove('nextHeartAt'),
        _prefs!.setInt('currentLevel', _currentLevel),
        _prefs!.setInt('highestUnlockedLevel', _highestUnlockedLevel),
        _prefs!.setInt('totalScore', _totalScore),
        _prefs!.setInt('coins', _coins),
        _prefs!.setInt('streakDays', _streakDays),
        _prefs!.setString('equippedSkin', _equippedSkin),
        _prefs!.setInt('hints', _hints),
        _prefs!.setInt('arrowSpeedIndex', _arrowSpeedIndex),
        if (_lastPlayedDate != null)
          _prefs!
              .setString('lastPlayedDate', _lastPlayedDate!.toIso8601String()),
      ]);
    } catch (e) {
      debugPrint('Error saving progress: $e');
    }

    // Save level results
    if (_prefs != null) {
      final Map<String, dynamic> resultsMap = {};
      for (final entry in _levelResults.entries) {
        resultsMap[entry.key.toString()] = entry.value.toJson();
      }
      await _prefs?.setString('levelResults', jsonEncode(resultsMap));
    }
  }

  // ── Universal hearts ───────────────────────────────────────────────────────

  Future<void> refreshHearts() async {
    if (_isDemoMode ||
        _lives >= AppConstants.maxLives ||
        _nextHeartAt == null) {
      return;
    }
    final now = DateTime.now();
    if (now.isBefore(_nextHeartAt!)) return;

    final elapsed = now.difference(_nextHeartAt!);
    final restored = 1 +
        elapsed.inSeconds ~/ AppConstants.heartRegenerationInterval.inSeconds;
    _lives = (_lives + restored).clamp(0, AppConstants.maxLives);
    _nextHeartAt = _lives >= AppConstants.maxLives
        ? null
        : _nextHeartAt!.add(AppConstants.heartRegenerationInterval * restored);
    await _save();
    notifyListeners();
  }

  Future<bool> consumeHeart() async {
    await refreshHearts();
    if (_isDemoMode) return true;
    if (_lives <= 0) return false;
    final wasFull = _lives >= AppConstants.maxLives;
    _lives--;
    if (wasFull || _nextHeartAt == null) {
      _nextHeartAt = DateTime.now().add(AppConstants.heartRegenerationInterval);
    }
    await _save();
    notifyListeners();
    return true;
  }

  /// Called by GameState when player makes a wrong move.
  /// NOTE: Lives are NOT decremented from here — GameState manages lives
  /// during gameplay. This method is for external persistence (e.g. continue).
  Future<void> restoreLives({int amount = AppConstants.maxLives}) async {
    await refreshHearts();
    final wasFull = _lives >= AppConstants.maxLives;
    _lives = (_lives + amount).clamp(0, AppConstants.maxLives);
    if (_lives >= AppConstants.maxLives) {
      _nextHeartAt = null;
    } else if (wasFull || _nextHeartAt == null) {
      _nextHeartAt = DateTime.now().add(AppConstants.heartRegenerationInterval);
    }
    await _save();
    notifyListeners();
  }

  /// Restore the universal heart pool to full.
  Future<void> resetLivesToFull() async {
    _lives = AppConstants.maxLives;
    _nextHeartAt = null;
    await _save();
    notifyListeners();
  }

  Future<bool> purchaseHearts({required int amount, required int cost}) async {
    await refreshHearts();
    if (amount <= 0 || cost < 0 || _coins < cost || livesAreFull) return false;
    final wasFull = livesAreFull;
    _coins -= cost;
    _lives = (lives + amount).clamp(0, AppConstants.maxLives);
    if (_lives >= AppConstants.maxLives) {
      _nextHeartAt = null;
    } else if (wasFull || _nextHeartAt == null) {
      _nextHeartAt = DateTime.now().add(AppConstants.heartRegenerationInterval);
    }
    await _save();
    notifyListeners();
    return true;
  }

  Future<Map<int, int>> ensureDailyChallengesForMonth([DateTime? date]) async {
    final now = date ?? DateTime.now();
    final monthKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    if (_dailyChallengeMonth != monthKey ||
        _dailyChallengeVersion != 2 ||
        _dailyChallengeSeeds.isEmpty) {
      final dayCount = DateTime(now.year, now.month + 1, 0).day;
      final random = Random(now.year * 100 + now.month);
      final usedSeeds = <int>{};
      _dailyChallengeMonth = monthKey;
      _dailyChallengeVersion = 2;
      _dailyChallengeSeeds = {};
      for (var day = 1; day <= dayCount; day++) {
        var seed = random.nextInt(0x7fffffff);
        while (!usedSeeds.add(seed)) {
          seed = random.nextInt(0x7fffffff);
        }
        _dailyChallengeSeeds[day] = seed;
      }
      await _prefs?.setString('dailyChallengeMonth', monthKey);
      await _prefs?.setInt('dailyChallengeVersion', 2);
      await _prefs?.setString(
        'dailyChallengeLevels',
        jsonEncode(
            _dailyChallengeSeeds.map((key, value) => MapEntry('$key', value))),
      );
      notifyListeners();
    }
    return Map.unmodifiable(_dailyChallengeSeeds);
  }

  int? dailyChallengeSeedForDay(int day) => _dailyChallengeSeeds[day];

  bool isDailyChallengeCompleted(String dateKey) =>
      _dailyChallengeResults.containsKey(dateKey);

  Future<bool> recordDailyChallengeComplete(String dateKey, int stars) async {
    final isFirstCompletion = !_dailyChallengeResults.containsKey(dateKey);
    final previous = _dailyChallengeResults[dateKey] ?? 0;
    if (stars > previous) _dailyChallengeResults[dateKey] = stars;
    await _prefs?.setString(
        'dailyChallengeResults', jsonEncode(_dailyChallengeResults));
    notifyListeners();
    return isFirstCompletion;
  }

  int? dailyChallengeStars(String dateKey) => _dailyChallengeResults[dateKey];

  int _calculateDailyChallengeStreak(DateTime date) {
    final today = DateTime(date.year, date.month, date.day);
    var cursor = today;
    if (!_dailyChallengeResults.containsKey(dailyChallengeDateKey(cursor))) {
      cursor = cursor.subtract(const Duration(days: 1));
    }
    var streak = 0;
    while (cursor.month == date.month &&
        _dailyChallengeResults.containsKey(dailyChallengeDateKey(cursor))) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  static String dailyChallengeDateKey(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  // ── Streak ───────────────────────────────────────────────────────────────────

  void _updateStreak() {
    if (_lastPlayedDate == null) return;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final lastPlayed = DateTime(
      _lastPlayedDate!.year,
      _lastPlayedDate!.month,
      _lastPlayedDate!.day,
    );
    final diff = today.difference(lastPlayed).inDays;
    if (diff > 1) {
      // Streak broken
      _streakDays = 0;
      _save();
    }
  }

  Future<void> recordDailyPlay() async {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    if (_lastPlayedDate != null) {
      final lastPlayed = DateTime(
        _lastPlayedDate!.year,
        _lastPlayedDate!.month,
        _lastPlayedDate!.day,
      );
      final diff = today.difference(lastPlayed).inDays;
      if (diff == 0) return; // Already recorded today
      if (diff == 1) {
        _streakDays++; // Consecutive day
      } else {
        _streakDays = 1; // Restart streak
      }
    } else {
      _streakDays = 1;
    }

    _lastPlayedDate = now;
    await _save();
    notifyListeners();
  }

  Future<void> protectStreak() async {
    // Called after watching a rewarded ad on streak break
    _lastPlayedDate = DateTime.now();
    await _save();
    notifyListeners();
  }

  // ── Level Progress ────────────────────────────────────────────────────────────

  Future<void> recordLevelComplete(LevelResult result) async {
    final existing = _levelResults[result.levelNumber];
    if (existing == null || result.stars > existing.stars) {
      _levelResults[result.levelNumber] = result;
    }
    _totalScore += result.score;
    _currentLevel = max(_currentLevel, result.levelNumber + 1);
    if (_currentLevel > _highestUnlockedLevel) {
      _highestUnlockedLevel = _currentLevel;
    }
    await _save();
    notifyListeners();
  }

  Future<void> setCurrentLevel(int level) async {
    _currentLevel = level;
    await _save();
    notifyListeners();
  }

  Future<void> addCoins(int amount) async {
    _coins += amount;
    await _save();
    notifyListeners();
  }

  int claimDailyCoin() {
    if (!hasUnclaimedDailyCoin) return 0;
    final today = _todayKey();
    _lastDailyCoinClaimDate = today;
    if (_prefs != null) {
      unawaited(_prefs!.setString('lastDailyCoinClaimDate', today));
    }
    addCoins(AppConstants.dailyFreeCoins);
    _notify();
    return AppConstants.dailyFreeCoins;
  }

  List<int> claimStreakReward() {
    if (!hasUnclaimedStreakReward) return [0, 0, 0];
    final today = _todayKey();
    _dailyStreakRewardClaimedDate = today;
    if (_prefs != null) {
      unawaited(_prefs!.setString('dailyStreakRewardClaimedDate', today));
    }
    final reward = List<int>.from(currentStreakReward);
    if (reward[0] > 0) unawaited(addCoins(reward[0]));
    if (reward[1] > 0) unawaited(addHints(reward[1]));
    _addHearts(reward[2]);
    notifyListeners();
    return reward;
  }

  List<int> claimStreakAdBonus() {
    if (!hasUnclaimedStreakAdBonus) return [0, 0];
    final today = _todayKey();
    _dailyStreakAdBonusClaimedDate = today;
    if (_prefs != null) {
      unawaited(_prefs!.setString('dailyStreakAdBonusClaimedDate', today));
    }
    unawaited(addCoins(AppConstants.dailyStreakAdBonusCoins));
    unawaited(addHints(AppConstants.dailyStreakAdBonusHints));
    notifyListeners();
    return [
      AppConstants.dailyStreakAdBonusCoins,
      AppConstants.dailyStreakAdBonusHints,
    ];
  }

  void _addHearts(int count) {
    if (count <= 0) return;
    final newLives = (_lives + count).clamp(0, AppConstants.maxLives);
    if (newLives != _lives) {
      _lives = newLives;
      if (_lives >= AppConstants.maxLives) {
        _nextHeartAt = null;
      } else if (_nextHeartAt == null) {
        _nextHeartAt =
            DateTime.now().add(AppConstants.heartRegenerationInterval);
      }
      unawaited(_save());
    }
  }

  static String _todayKey() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  void _notify() {
    notifyListeners();
  }

  Future<void> setEquippedSkin(String skin) async {
    _equippedSkin = skin;
    await _save();
    notifyListeners();
  }

  Future<void> addHints(int amount) async {
    _hints += amount;
    await _save();
    notifyListeners();
  }

  Future<bool> purchaseHints({
    int amount = 1,
    int cost = AppConstants.hintCostSingle,
  }) async {
    if (amount <= 0 || cost < 0 || _coins < cost) return false;
    _coins -= cost;
    _hints += amount;
    await _save();
    notifyListeners();
    return true;
  }

  bool useHint() {
    if (_hints > 0) {
      _hints--;
      _save();
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Settings Setters ─────────────────────────────────────────────────────────

  Future<void> setSoundEnabled(bool value) async {
    _soundEnabled = value;
    AudioManager.instance.setSoundEnabled(value);
    await _prefs?.setBool('soundEnabled', value);
    notifyListeners();
  }

  Future<void> setMusicEnabled(bool value) async {
    _musicEnabled = value;
    AudioManager.instance.setMusicEnabled(value);
    await _prefs?.setBool('musicEnabled', value);
    notifyListeners();
  }

  Future<void> setVibrationEnabled(bool value) async {
    _vibrationEnabled = value;
    await _prefs?.setBool('vibrationEnabled', value);
    notifyListeners();
  }

  Future<void> setTimeLimitEnabled(bool value) async {
    _timeLimitEnabled = value;
    await _prefs?.setBool('timeLimitEnabled', value);
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode value) async {
    _themeMode = value;
    await _prefs?.setString('themeMode', value.name);
    notifyListeners();
  }

  Future<void> setShowFps(bool value) async {
    _showFps = value;
    await _prefs?.setBool('showFps', value);
    notifyListeners();
  }

  Future<void> setHasSeen40x40Warning(bool value) async {
    _hasSeen40x40Warning = value;
    await _prefs?.setBool('hasSeen40x40Warning', value);
    notifyListeners();
  }

  Future<void> setHasSeenZoomHint(bool value) async {
    _hasSeenZoomHint = value;
    await _prefs?.setBool('hasSeenZoomHint', value);
    notifyListeners();
  }

  Future<void> setArrowSpeedIndex(int value) async {
    _arrowSpeedIndex = value.clamp(0, 2);
    await _prefs?.setInt('arrowSpeedIndex', _arrowSpeedIndex);
    notifyListeners();
  }

  // ── Star rating calculator ────────────────────────────────────────────────────
  static int calculateStars(int livesLost, int totalArrows, int movesUsed) {
    if (livesLost == 0) return 3;
    if (livesLost == 1) return 2;
    return 1;
  }

  static int computeLevelCoinReward({
    required int levelNumber,
    required int stars,
    required bool isFirstClear,
  }) {
    if (!isFirstClear) return 1;
    final isBoss = levelNumber % 5 == 0;
    final base = isBoss ? 20 : 5;
    final starBonus = stars == 3 ? 3 : 0;
    return base + starBonus;
  }
}
