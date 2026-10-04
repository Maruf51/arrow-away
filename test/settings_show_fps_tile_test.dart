import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:arrow_escape/data/repositories/progress_repository.dart';
import 'package:arrow_escape/screens/settings/settings_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('Show FPS tile is present and toggles the setting on/off',
      (tester) async {
    GoogleFonts.config.allowRuntimeFetching = false;

    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final progress = ProgressRepository(prefs);

    // Wide surface: widget tests don't load the app's Nunito font, so the
    // fallback metrics widen labels — the real device fits at phone width.
    await tester.binding.setSurfaceSize(const Size(700, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      ChangeNotifierProvider<ProgressRepository>.value(
        value: progress,
        child: MaterialApp(home: const SettingsScreen()),
      ),
    );
    await tester.pump();

    // Tile is visible in the settings menu.
    expect(find.text('Show FPS'), findsOneWidget);

    // Defaults to off.
    expect(progress.showFps, isFalse);

    // Show FPS is the 4th Switch on screen (Sound, Music, Vibration, FPS).
    final fpsSwitch = find.byType(Switch).last;

    // Toggle ON → state + persistence updated.
    await tester.tap(fpsSwitch);
    await tester.pump();
    expect(progress.showFps, isTrue);
    expect(prefs.getBool('showFps'), isTrue);

    // Toggle OFF → state + persistence updated.
    await tester.tap(fpsSwitch);
    await tester.pump();
    expect(progress.showFps, isFalse);
    expect(prefs.getBool('showFps'), isFalse);
  });
}
