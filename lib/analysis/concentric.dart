/// Concentric-phase detection, ported line-for-line from the reference
/// `yolo_pose/detect_concentric.py` (both the ruptures/PELT method and the
/// scipy-peaks method). Reference quirks are preserved deliberately; see
/// REFERENCE_NOTES.md.
library;

import 'dart:math' as math;

import 'find_peaks.dart';
import 'models.dart';
import 'pelt.dart';
import 'signal.dart';

/// Stable descending sort helper (Python's `sorted(reverse=True)` is stable;
/// Dart's List.sort is not): equal keys keep original order.
List<T> _stableSortDesc<T>(List<T> items, int Function(T a, T b) cmpAsc) {
  final indexed = [for (var i = 0; i < items.length; i++) (i, items[i])];
  indexed.sort((a, b) {
    final c = cmpAsc(b.$2, a.$2); // descending
    return c != 0 ? c : a.$1.compareTo(b.$1); // stable
  });
  return [for (final e in indexed) e.$2];
}

double _mean(List<double> xs) =>
    xs.isEmpty ? 0.0 : xs.reduce((a, b) => a + b) / xs.length;

/// `detect_concentric_ruptures`. [smoothedPositions] may contain nulls/NaN
/// (interpolated internally, like `_interpolate`). [smoothVelocity] is the
/// fps-scaled velocity of the smoothed signal (px/s) and is required by the
/// as-run reference path (a per-frame-diff fallback is kept for fidelity).
(List<Phase>, List<Segment>) detectConcentricRuptures(
  List<double?> smoothedPositions, {
  required double pen,
  required int minFrames,
  List<double>? smoothVelocity,
  double mergeMinVel = 50.0,
  int extensionLookahead = 30,
  double minRepRatio = 0.60,
  int peltMinSize = 2,
  int peltJump = 5,
}) {
  final raw = [for (final p in smoothedPositions) p ?? double.nan];
  if (raw.every((v) => v.isNaN)) return (const <Phase>[], const <Segment>[]);
  final arr = interpolateNan(raw);
  final n = arr.length;

  // Stage 1: PELT on the per-frame velocity (first diff, NOT fps-scaled).
  final vel = [for (var i = 1; i < n; i++) arr[i] - arr[i - 1]];
  final breakpoints =
      peltL2(vel, pen: pen, minSize: peltMinSize, jump: peltJump);
  final boundaries = [0, ...breakpoints];

  // Stage 2: per-segment stats. Adjacent segments share the boundary frame
  // (reference off-by-one quirk, kept).
  final segments = <Segment>[];
  for (var i = 0; i < boundaries.length - 1; i++) {
    final segStart = boundaries[i];
    final segEnd = boundaries[i + 1];
    final frames = segEnd - segStart + 1;
    segments.add(Segment(
      start: segStart,
      end: segEnd,
      frames: frames,
      displacement: arr[segEnd] - arr[segStart],
      skippedShort: frames < minFrames,
    ));
  }

  // Stage 3: merge runs of >= 2 consecutive qualifying segments.
  bool qualifies(Segment seg) {
    if (seg.skippedShort) return false;
    double avgVel;
    if (smoothVelocity != null) {
      final s = math.min(seg.start + 1, smoothVelocity.length);
      final e = math.min(seg.end + 1, smoothVelocity.length);
      avgVel = _mean(smoothVelocity.sublist(s, math.max(s, e)));
    } else {
      avgVel = seg.frames > 0 ? seg.displacement / seg.frames : 0.0;
    }
    return seg.displacement > 0 && avgVel >= mergeMinVel;
  }

  final nOriginal = segments.length;
  var i = 0;
  while (i < nOriginal) {
    if (qualifies(segments[i])) {
      var j = i + 1;
      while (j < nOriginal && qualifies(segments[j])) {
        j++;
      }
      if (j - i > 1) {
        final mStart = segments[i].start;
        final mEnd = segments[j - 1].end;
        final mFrames = mEnd - mStart + 1;
        segments.add(Segment(
          start: mStart,
          end: mEnd,
          frames: mFrames,
          displacement: arr[mEnd] - arr[mStart],
          skippedShort: mFrames < minFrames,
          merged: true,
        ));
      }
      i = j;
    } else {
      i++;
    }
  }

  // Stage 4: candidate pool.
  final candidates =
      [for (final s in segments) if (!s.skippedShort && s.displacement > 0) s];

  // Stage 5: expected rep displacement from peak/trough analysis.
  double estimateRepDisplacement(List<double> a) {
    final distance = math.max(1, a.length ~/ 20);
    var mx = a[0], mn = a[0];
    for (final v in a) {
      if (v > mx) mx = v;
      if (v < mn) mn = v;
    }
    final prom = (mx - mn) * 0.15;
    final peaks = findPeaks(a, distance: distance, prominence: prom);
    final troughs =
        findPeaks([for (final v in a) -v], distance: distance, prominence: prom);
    final displacements = <double>[];
    var peakCursor = 0;
    for (final trough in troughs) {
      while (peakCursor < peaks.length && peaks[peakCursor] <= trough) {
        peakCursor++;
      }
      if (peakCursor < peaks.length) {
        displacements.add(a[peaks[peakCursor]] - a[trough]);
      }
    }
    return displacements.isNotEmpty ? median(displacements) : mx - mn;
  }

  final expectedDisp = estimateRepDisplacement(arr);
  final qualified = [
    for (final c in candidates)
      if (c.displacement >= minRepRatio * expectedDisp) c
  ];

  // Stage 6: dedup — prefer merged, then higher displacement; greedy
  // non-overlapping; first max wins ties (stable descending sort).
  final qualifiedSorted = _stableSortDesc<Segment>(qualified, (a, b) {
    final c = (a.merged ? 1 : 0).compareTo(b.merged ? 1 : 0);
    return c != 0 ? c : a.displacement.compareTo(b.displacement);
  });
  var allSelected = <Segment>[];
  for (final cand in qualifiedSorted) {
    final overlaps = allSelected
        .any((sel) => cand.start < sel.end && sel.start < cand.end);
    if (!overlaps) allSelected.add(cand);
  }
  allSelected = _stableSortDesc<Segment>(allSelected, (a, b) => b.start.compareTo(a.start));

  if (allSelected.isEmpty && candidates.isNotEmpty) {
    // Python max() returns the first maximal element.
    var best = candidates.first;
    for (final c in candidates.skip(1)) {
      if (c.displacement > best.displacement) best = c;
    }
    allSelected = [best];
  }

  for (final seg in segments) {
    seg.selected = allSelected.contains(seg); // identity
  }
  var phases = [for (final s in allSelected) (s.start, s.end)];

  // Stage 7: extend boundaries while velocity conditions hold.
  double velAt(int frame) {
    if (smoothVelocity != null) return smoothVelocity[frame];
    return frame > 0 ? arr[frame] - arr[frame - 1] : 0.0;
  }

  Phase extend(int start, int end) {
    var count = 0;
    while (end + 1 < n && count < extensionLookahead) {
      if (velAt(end) > 0 && arr[end + 1] > arr[end]) {
        end++;
        count++;
      } else {
        break;
      }
    }
    count = 0;
    while (start - 1 >= 0 && count < extensionLookahead) {
      if (velAt(start - 1) > 0) {
        start--;
        count++;
      } else {
        break;
      }
    }
    return (math.max(0, start), math.min(n - 1, end));
  }

  phases = [for (final (s, e) in phases) extend(s, e)];
  return (phases, segments);
}

/// `detect_concentric_peaks`: trough -> first following peak pairing, one
/// rep per pair, skipping pairs shorter than [minFrames].
List<Phase> detectConcentricPeaks(
  List<double?> smoothedPositions, {
  int minFrames = 20,
}) {
  final raw = [for (final p in smoothedPositions) p ?? double.nan];
  if (raw.every((v) => v.isNaN)) return const <Phase>[];
  final arr = interpolateNan(raw);

  final distance = math.max(1, arr.length ~/ 20);
  var mx = arr[0], mn = arr[0];
  for (final v in arr) {
    if (v > mx) mx = v;
    if (v < mn) mn = v;
  }
  final prom = (mx - mn) * 0.3;

  final peaks = findPeaks(arr, distance: distance, prominence: prom);
  final troughs =
      findPeaks([for (final v in arr) -v], distance: distance, prominence: prom);

  final phases = <Phase>[];
  var peakCursor = 0;
  for (final trough in troughs) {
    while (peakCursor < peaks.length && peaks[peakCursor] <= trough) {
      peakCursor++;
    }
    if (peakCursor >= peaks.length) break;
    final peak = peaks[peakCursor];
    peakCursor++; // this method consumes the peak (unlike stage 5 above)
    if (peak - trough < minFrames) continue;
    phases.add((trough, peak));
  }
  return phases;
}
