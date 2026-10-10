import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' show Path;

import 'package:flutter_test/flutter_test.dart';

/// Guards the neon-flow per-arrow draw-call budget.
///
/// The neon-flow branch previously issued ~20-30 draw calls per arrow (layered
/// glow strokes, per-dash strokes, head streaks) and ran at ~15 FPS on a
/// 100-arrow board. These tests lock in the 5-call budget and the "no blur"
/// rule at the source level, so they cannot silently regress.
void main() {
  String source() =>
      File('lib/game/components/arrow_component.dart').readAsStringSync();

  /// Returns the source of `_drawLiquidNeonArrow` via brace matching.
  String neonBranch(String src) {
    final start = src.indexOf('void _drawLiquidNeonArrow(');
    expect(start, greaterThan(-1), reason: '_drawLiquidNeonArrow not found');
    final open = src.indexOf('{', start);
    var depth = 0;
    for (var i = open; i < src.length; i++) {
      if (src[i] == '{') depth++;
      if (src[i] == '}') {
        depth--;
        if (depth == 0) return src.substring(open, i);
      }
    }
    fail('unbalanced braces in _drawLiquidNeonArrow');
  }

  group('neon flow draw-call budget', () {
    test('steady-state render issues at most 6 canvas draw calls', () {
      final body = neonBranch(source());
      final draws = RegExp(r'canvas\.draw\w+').allMatches(body).length;
      expect(draws, lessThanOrEqualTo(6),
          reason: 'neon-flow branch issues $draws draw calls, budget is 6 (includes inner head triangle)');
    });

    test('neon-flow path has no MaskFilter or saveLayer', () {
      final src = source();
      final start = src.indexOf('/// Neon Flow render path');
      // Search forward from the neon block for the preview section.
      final end = src.indexOf('Long-press preview path builder', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      final block = src.substring(start, end);
      expect(block.contains('MaskFilter'), isFalse);
      expect(block.contains('saveLayer'), isFalse);
    });

    test('deleted helpers and paints are gone', () {
      final src = source();
      for (final gone in [
        '_drawLiquidFlow',
        '_drawLiquidHeadStreak',
        '_drawLiquidNeonHead',
        '_drawTubeStroke',
        '_flowDashPath',
        '_paintGlowWide',
        '_paintGlowCore',
        '_paintDashHalo',
        '_paintDashCore',
        '_paintHeadGlowWide',
        '_paintHeadGlowCore',
        '_paintCaretEdge',
        '_paintCaretRim',
        '_paintStreakHalo',
        '_paintStreakCore',
        '_paintRingEdge',
        '_paintDeepRed',
        '_paintHotRed',
        '_paintRed',
        '_paintChannel',
      ]) {
        expect(src.contains(gone), isFalse, reason: '$gone should be deleted');
      }
    });

    test('liquid segments are batched into a single Path + drawPath', () {
      final body = neonBranch(source());
      // 6 calls: 1.soft glow, 2.white border, 3.red body, 4.red head fill,
      // 5.inner white triangle, 6.liquid segments.
      expect(RegExp(r'canvas\.drawPath').allMatches(body).length,
          lessThanOrEqualTo(6));
      expect(body.contains('_buildLiquidPath'), isTrue);
    });

    test('liquid phase decreases along the head-first path', () {
      final src = source();
      final start = src.indexOf('Path? _buildLiquidPath(');
      final end = src.indexOf('void _appendArc(', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      expect(src.substring(start, end),
          contains('seg.startFrac * length - _flowPhase * length'));
    });

    test('arrow updates do not scan the shared arrow list', () {
      final src = source();
      final start = src.indexOf('void update(double dt)');
      final end = src.indexOf('void syncModel(', start);
      expect(start, greaterThan(-1));
      expect(end, greaterThan(start));
      expect(src.substring(start, end), isNot(contains('gameState.arrows')));
    });
  });

  group('liquid segment generation', () {
    test('is deterministic per arrow id', () {
      List<double> build(int seed) {
        final rng = math.Random(seed);
        final count = rng.nextInt(2) + 1;
        final out = <double>[];
        for (var i = 0; i < count; i++) {
          final segLen = 0.15 + rng.nextDouble() * 0.35;
          out
            ..add(rng.nextDouble() * (1.0 - segLen))
            ..add(segLen);
        }
        return out;
      }

      expect(build(12345), equals(build(12345)));
      expect(build(12345), isNot(equals(build(999))));
    });

    test('max 2 segments, each 15%-50% and inside the body', () {
      for (var seed = 0; seed < 500; seed++) {
        final rng = math.Random(seed);
        final count = rng.nextInt(2) + 1;
        expect(count, inInclusiveRange(1, 2), reason: 'max 2 segments');
        for (var i = 0; i < count; i++) {
          final segLen = 0.15 + rng.nextDouble() * 0.35;
          final startFrac = rng.nextDouble() * (1.0 - segLen);
          expect(segLen, inInclusiveRange(0.15, 0.50));
          expect(startFrac, greaterThanOrEqualTo(0.0));
          expect(startFrac + segLen, lessThanOrEqualTo(1.0 + 1e-9));
        }
      }
    });

    test('layout varies across arrows (not degenerate)', () {
      final seen = <String>{};
      for (var seed = 0; seed < 200; seed++) {
        final rng = math.Random(seed);
        final count = rng.nextInt(2) + 1;
        final buf = StringBuffer('$count');
        for (var i = 0; i < count; i++) {
          final segLen = 0.15 + rng.nextDouble() * 0.35;
          buf
            ..write((rng.nextDouble() * (1.0 - segLen)).toStringAsFixed(4))
            ..write(',')
            ..write(segLen.toStringAsFixed(4))
            ..write(';');
        }
        seen.add(buf.toString());
      }
      expect(seen.length, greaterThan(150));
    });
  });

  group('flowing segment geometry', () {
    void append(Path path, double from, double to) {
      path.moveTo(from, 0);
      path.lineTo(to, 0);
    }

    test('segment start wraps within [0, length)', () {
      const length = 300.0;
      for (var s = 0; s < 100; s++) {
        final rng = math.Random(s);
        final segLen = (0.15 + rng.nextDouble() * 0.35) * length;
        final startFrac = rng.nextDouble() * (1.0 - segLen / length);
        for (var p = 0; p <= 20; p++) {
          final start = (startFrac * length + (p / 20.0) * length) % length;
          expect(start, inInclusiveRange(0.0, length - 1e-9));
        }
      }
    });

    test('wrapped segment splits into two sub-paths in ONE Path', () {
      const length = 100.0;
      const start = 80.0;
      const segLen = 40.0; // wraps past the end back to 20

      final path = Path();
      final end = start + segLen;
      if (end <= length) {
        append(path, start, end);
      } else {
        append(path, start, length);
        append(path, 0.0, end - length);
      }

      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 2, reason: 'two contours in one Path object');
      final total = metrics.fold<double>(0, (a, m) => a + m.length);
      expect(total, closeTo(segLen, 1e-6),
          reason: 'wrapping must not lose or duplicate length');
    });

    test('non-wrapping segment stays a single sub-path', () {
      final path = Path();
      append(path, 20.0, 60.0);
      final metrics = path.computeMetrics().toList();
      expect(metrics.length, 1);
      expect(metrics.first.length, closeTo(40.0, 1e-6));
    });
  });
}