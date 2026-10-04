import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

/// Small translucent chip displaying the current rendering FPS.
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

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
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
    if (rounded != _fps) {
      setState(() => _fps = rounded);
    }
  }

  @override
  void dispose() {
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
        child: Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8BC34A),
            fontSize: 12,
            fontWeight: FontWeight.w700,
            fontFeatures: [FontFeature.tabularFigures()],
          ),
        ),
      ),
    );
  }
}