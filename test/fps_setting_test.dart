import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arrow_escape/data/repositories/progress_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ProgressRepository showFps setting', () {
    test('defaults to off when the key has never been written', () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      expect(progress.showFps, isFalse);
    });

    test('setShowFps(true) notifies, persists, and survives a reload',
        () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);

      var notified = false;
      progress.addListener(() => notified = true);

      await progress.setShowFps(true);

      expect(progress.showFps, isTrue);
      expect(notified, isTrue, reason: 'UI must rebuild to show the overlay');
      expect(prefs.getBool('showFps'), isTrue,
          reason: 'value must be persisted');

      // A fresh repository (e.g. after app restart) reads the saved value.
      final reloaded = ProgressRepository(prefs);
      expect(reloaded.showFps, isTrue);
    });

    test('setShowFps(false) persists and turns the overlay off', () async {
      SharedPreferences.setMockInitialValues({'showFps': true});
      final prefs = await SharedPreferences.getInstance();
      final progress = ProgressRepository(prefs);
      expect(progress.showFps, isTrue);

      await progress.setShowFps(false);

      expect(progress.showFps, isFalse);
      expect(prefs.getBool('showFps'), isFalse);

      final reloaded = ProgressRepository(prefs);
      expect(reloaded.showFps, isFalse);
    });
  });
}
