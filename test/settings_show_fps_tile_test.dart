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

    final settingsCard = find.byWidgetPredicate((widget) {
      if (widget is! Container || widget.decoration is! BoxDecoration) {
        return false;
      }
      return (widget.decoration! as BoxDecoration).color ==
          const Color(0xFFFFF9EE);
    });
    final cardHeight = tester.getSize(settingsCard.first).height;
    final viewHeight =
        MediaQuery.sizeOf(tester.element(find.byType(SettingsDialog))).height;
    expect(cardHeight, greaterThan(viewHeight * 0.6));
    expect(cardHeight, lessThan(viewHeight * 0.8));
    expect(find.byType(SingleChildScrollView), findsWidgets);

    // Tile is visible in the settings menu.
    expect(find.text('Show Framerate (FPS)'), findsOneWidget);
    expect(find.text('Grid Background Dots'), findsNothing);
    expect(find.text('Start Arrow Animation'), findsNothing);

    // Defaults to off.
    expect(progress.showFps, isFalse);
    expect(progress.timeLimitEnabled, isTrue);

    final timeLimitCard = find.ancestor(
      of: find.text('Time Limit (Later Levels)'),
      matching: find.byType(Row),
    );
    final timeLimitSwitch = find.descendant(
      of: timeLimitCard.first,
      matching: find.byType(Switch),
    );
    await tester.tap(timeLimitSwitch);
    await tester.pump();
    expect(progress.timeLimitEnabled, isFalse);
    expect(prefs.getBool('timeLimitEnabled'), isFalse);

    // The FPS switch: the Switch inside the 'Show Framerate (FPS)' card.
    // (Resolved by card instead of index so neighbouring toggles — e.g. the
    // Music toggle — can't shift the wrong switch into focus.)
    final fpsCard = find.ancestor(
      of: find.text('Show Framerate (FPS)'),
      matching: find.byType(Row),
    );
    final fpsSwitch = find.descendant(
      of: fpsCard.first,
      matching: find.byType(Switch),
    );

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
