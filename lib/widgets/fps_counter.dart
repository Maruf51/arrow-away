import 'dart:ui' show FrameTiming;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Small translucent chip displaying the current rendering FPS.
///
/// A second line shows where the frame time goes, measured by the engine
/// (works in release builds, no DevTools needed):
///   UI  = time on the UI thread (Dart: build + layout + paint recording, i.e.
///         Flame update/render for every component)
///   GPU = time on the raster thread (turning the recorded frame into pixels)
///   max = slowest frame in the window
/// If UI is the big number the game code is the bottleneck; if GPU is, there
/// is too much drawing / overdraw for the graphics chip.
///
/// Counts frames with a [Ticker] and refreshes the value twice per second.
/// Intended to be placed inside a `Stack` overlay (e.g. bottom-left corner).
/// Wrapped in [IgnorePointer] so it never intercepts touches.
class FpsCounter extends StatefulWidget {
  const FpsCounter({super.key});

  @override
  State<FpsCounter> createState() => _FpsCounterState();
}

class _FpsCounterState extends State<FpsCounter>
    with SingleTickerProviderStateMixin {
  static const Duration _updateInterval = Duration(milliseconds: 500);

  late final Ticker _ticker;
  int _frames = 0;
  int _windowStartUs = 0;
  double _fps = 0;

  // Frame-timing accumulators (fed by the engine's FrameTiming reports).
  double _uiSumMs = 0;
  double _rasterSumMs = 0;
  double _worstMs = 0;
  int _timingFrames = 0;
  double _uiMs = -1;
  double _rasterMs = -1;
  double _maxMs = -1;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) {
    for (final t in timings) {
      _uiSumMs += t.buildDuration.inMicroseconds / 1000.0;
      _rasterSumMs += t.rasterDuration.inMicroseconds / 1000.0;
      final total = t.totalSpan.inMicroseconds / 1000.0;
      if (total > _worstMs) _worstMs = total;
      _timingFrames++;
    }
  }

  void _onTick(Duration elapsed) {
    final nowUs = elapsed.inMicroseconds;
    if (_windowStartUs == 0) {
      _windowStartUs = nowUs;
      return;
    }

    _frames++;
    final deltaUs = nowUs - _windowStartUs;
    if (deltaUs < _updateInterval.inMicroseconds) return;

    _windowStartUs = nowUs;
    final fps = _frames * 1000000 / deltaUs;
    _frames = 0;

    // Skip the first bogus reading after a paused/resumed app, and
    // anything below 1 fps (window too coarse to be meaningful).
    if (fps < 1 || fps > 1000) return;

    final rounded = fps.roundToDouble();
    double? ui, raster, worst;
    if (_timingFrames > 0) {
      ui = _uiSumMs / _timingFrames;
      raster = _rasterSumMs / _timingFrames;
      worst = _worstMs;
    }
    _uiSumMs = 0;
    _rasterSumMs = 0;
    _worstMs = 0;
    _timingFrames = 0;

    final timingChanged = ui != null &&
        (ui.round() != _uiMs.round() ||
            raster!.round() != _rasterMs.round() ||
            worst!.round() != _maxMs.round());
    if (rounded != _fps || timingChanged) {
      setState(() {
        _fps = rounded;
        if (ui != null) {
          _uiMs = ui;
          _rasterMs = raster!;
          _maxMs = worst!;
        }
      });
    }
  }

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final label =
        _fps > 0 ? '${_fps.toStringAsFixed(0)} FPS' : '-- FPS';

    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.65),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFF8BC34A),
                fontSize: 12,
                fontWeight: FontWeight.w700,
                fontFeatures: [FontFeature.tabularFigures()],
              ),
            ),
            if (_uiMs >= 0)
              Text(
                'UI ${_uiMs.toStringAsFixed(1)} · GPU ${_rasterMs.toStringAsFixed(1)} · max ${_maxMs.toStringAsFixed(0)} ms',
                style: const TextStyle(
                  color: Color(0xFFB0BEC5),
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
          ],
        ),
      ),
    );
  }
}