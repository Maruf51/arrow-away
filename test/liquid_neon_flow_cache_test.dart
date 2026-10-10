import 'dart:math' as math;
import 'dart:ui' show Path;

import 'package:flutter_test/flutter_test.dart';

/// Verification that the vertex-only arc-length cache used by
/// `_buildLiquidPath` preserves the same geometry as `PathMetric`.
///
/// The helper below is a copy of the component's cache logic so both
/// algorithms can be compared over randomised polylines.
void main() {
  // Mirrors ArrowComponent._rebuildFlowCache / _flowIndexFor / _flowPointAt.
  List<Offset> vertices = [];
  List<double> dists = [];
  double total = 0.0;

  void rebuild(List<Offset> pts) {
    final v = <Offset>[];
    final d = <double>[];
    if (pts.isEmpty) {
      vertices = v;
      dists = d;
      total = 0;
      return;
    }
    v.add(pts.first);
    d.add(0.0);
    var acc = 0.0;
    for (int i = 1; i < pts.length; i++) {
      final segmentLength = (pts[i] - pts[i - 1]).distance;
      if (segmentLength <= 0.0) continue;
      acc += segmentLength;
      v.add(pts[i]);
      d.add(acc);
    }
    vertices = v;
    dists = d;
    total = acc;
  }

  int indexFor(double d) {
    if (dists.isEmpty) return 0;
    if (d <= 0.0) return 0;
    if (d >= total) return dists.length - 1;
    var lo = 0, hi = dists.length - 1;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (dists[mid] < d) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  Offset pointAt(double d) {
    if (vertices.isEmpty) return Offset.zero;
    final i = indexFor(d);
    if (i <= 0) return vertices.first;
    if (i >= vertices.length) return vertices.last;
    final d0 = dists[i - 1];
    final d1 = dists[i];
    final t = d1 > d0 ? (d - d0) / (d1 - d0) : 0.0;
    return Offset.lerp(vertices[i - 1], vertices[i], t)!;
  }

  test('cached vertices match PathMetric arc-length parameterisation', () {
    final rng = math.Random(1234);

    for (int trial = 0; trial < 200; trial++) {
      final cellSize = 24.0 + rng.nextDouble() * 40.0;
      final n = 2 + rng.nextInt(8);

      // Random polyline through a grid-like lattice (axis-aligned steps).
      var r = rng.nextInt(6);
      var c = rng.nextInt(6);
      final pts = <Offset>[];
      for (int i = 0; i < n; i++) {
        pts.add(Offset((c + 0.5) * cellSize, (r + 0.5) * cellSize));
        if (rng.nextBool()) {
          r = (r + rng.nextInt(3) - 1).clamp(0, 7);
        } else {
          c = (c + rng.nextInt(3) - 1).clamp(0, 7);
        }
      }
      if (pts.last == pts.first && pts.length > 1) continue;

      // Reference: PathMetric over the same polyline.
      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      final metric = path.computeMetrics().first;
      final refLength = metric.length;

      rebuild(pts);

      // Cached total length must match the path metric length
      // (PathMetric accumulates in float32, so allow a small epsilon).
      expect(total, closeTo(refLength, 1e-3),
          reason: 'length mismatch on trial $trial');

      // Every cached vertex must lie on the reference path, and the cached
      // pointAt() must match PathMetric.getTangentForOffset().
      expect(vertices.length, lessThanOrEqualTo(pts.length));
      for (int k = 0; k < vertices.length; k++) {
        final tangent = metric.getTangentForOffset(dists[k]);
        if (tangent == null) continue;
        expect((vertices[k] - tangent.position).distance, lessThan(1e-4),
            reason: 'sample $k off-path on trial $trial');
      }

      for (int s = 0; s <= 20; s++) {
        final d = refLength * s / 20.0;
        final tangent = metric.getTangentForOffset(d);
        if (tangent == null) continue;
        expect((pointAt(d) - tangent.position).distance, lessThan(1e-4),
            reason: 'pointAt($d) mismatch on trial $trial');
      }
    }
  });

  test('dash windows match extractPath endpoints', () {
    final rng = math.Random(99);
    final cellSize = 40.0;

    for (int trial = 0; trial < 200; trial++) {
      final pts = <Offset>[];
      var r = rng.nextInt(5);
      var c = rng.nextInt(5);
      for (int i = 0; i < 3 + rng.nextInt(7); i++) {
        pts.add(Offset((c + 0.5) * cellSize, (r + 0.5) * cellSize));
        if (rng.nextBool()) {
          r = (r + rng.nextInt(3) - 1).clamp(0, 7);
        } else {
          c = (c + rng.nextInt(3) - 1).clamp(0, 7);
        }
      }

      final path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length; i++) {
        path.lineTo(pts[i].dx, pts[i].dy);
      }
      final metrics = path.computeMetrics().toList();
      if (metrics.isEmpty) continue; // degenerate path
      final metric = metrics.first;
      final length = metric.length;

      // Skip degenerate (zero-length) paths.
      if (length < 1e-3) continue;

      rebuild(pts);
      if (total < 1e-6) continue;

      // Sweep dash windows across the whole path.
      for (int s = 0; s < 25; s++) {
        final from = length * s / 25.0;
        final to = (from + length * 0.15).clamp(0.0, length).toDouble();
        if (to <= from) continue;

        final refStart = metric.getTangentForOffset(from)!.position;
        final refEnd = metric.getTangentForOffset(to)!.position;

        expect((pointAt(from) - refStart).distance, lessThan(1e-4),
            reason: 'dash start mismatch trial $trial s=$s');
        expect((pointAt(to) - refEnd).distance, lessThan(1e-4),
            reason: 'dash end mismatch trial $trial s=$s');
      }
    }
  });
}