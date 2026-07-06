import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/analysis/analysis_config.dart';
import 'package:barbell_velocity_app/analysis/concentric.dart';
import 'package:barbell_velocity_app/analysis/pipeline.dart';

/// Synthetic lift: [reps] reps of a smooth up-hold-down cycle plus idle time,
/// mimicking -y wrist position (up = increasing).
List<double?> syntheticLift({int reps = 3, int rest = 60, int repLen = 90}) {
  final signal = <double?>[];
  for (var i = 0; i < rest; i++) {
    signal.add(0);
  }
  for (var r = 0; r < reps; r++) {
    for (var i = 0; i < repLen; i++) {
      // Half-cosine up over first half, hold briefly, half-cosine down.
      final t = i / (repLen - 1);
      double v;
      if (t < 0.4) {
        v = 300 * (1 - math.cos(math.pi * t / 0.4)) / 2;
      } else if (t < 0.5) {
        v = 300;
      } else {
        v = 300 * (1 + math.cos(math.pi * (t - 0.5) / 0.5)) / 2;
      }
      signal.add(v);
    }
    for (var i = 0; i < rest; i++) {
      signal.add(0);
    }
  }
  return signal;
}

void main() {
  group('degenerate inputs', () {
    test('empty track produces empty result, no crash', () {
      final r = analyzePositions([], 60);
      expect(r.reps, isEmpty);
      expect(r.phases, isEmpty);
      expect(r.segments, isEmpty);
    });

    test('all-missing track produces empty result, no crash', () {
      final r = analyzePositions([null, null, null], 60);
      expect(r.reps, isEmpty);
      expect(r.rawPositions.every((v) => v.isNaN), isTrue);
    });

    test('all-NaN detectConcentricRuptures returns empty', () {
      final (phases, segments) = detectConcentricRuptures(
        [null, null],
        pen: 20,
        minFrames: 5,
      );
      expect(phases, isEmpty);
      expect(segments, isEmpty);
    });

    test('standing around (flat signal) finds no reps', () {
      final flat = List<double?>.filled(300, 100.0);
      final r = analyzePositions(flat, 60);
      expect(r.reps, isEmpty);
    });
  });

  group('synthetic lifts', () {
    test('single rep detected once', () {
      final r = analyzePositions(syntheticLift(reps: 1), 60);
      expect(r.reps.length, 1);
      expect(r.reps.first.avgVelPxS, greaterThan(0));
      expect(r.reps.first.maxVelPxS,
          greaterThanOrEqualTo(r.reps.first.avgVelPxS));
    });

    test('multiple reps detected and ordered', () {
      final r = analyzePositions(syntheticLift(reps: 4), 60);
      expect(r.reps.length, 4);
      for (var i = 1; i < r.reps.length; i++) {
        expect(r.reps[i].startFrame,
            greaterThan(r.reps[i - 1].endFrame - 1));
      }
    });

    test('dropped frames (nulls) are tolerated', () {
      final signal = syntheticLift(reps: 2);
      for (var i = 100; i < 110; i++) {
        signal[i] = null;
      }
      final r = analyzePositions(signal, 60);
      expect(r.reps.length, 2);
    });

    test('noisy signal still yields the right rep count', () {
      final rng = math.Random(7);
      final signal = [
        for (final v in syntheticLift(reps: 3))
          v! + (rng.nextDouble() - 0.5) * 8
      ].cast<double?>();
      final r = analyzePositions(signal, 60);
      expect(r.reps.length, 3);
    });

    test('near-zero movement (jitter only) yields no fast reps', () {
      final rng = math.Random(3);
      final signal = [
        for (var i = 0; i < 400; i++) 100 + (rng.nextDouble() - 0.5) * 2.0
      ].cast<double?>();
      final r = analyzePositions(signal, 60);
      // Tiny displacements: no rep should show meaningful concentric velocity.
      for (final rep in r.reps) {
        expect(rep.displacementPx.abs(), lessThan(10));
      }
    });
  });

  group('parameter behavior', () {
    final signal = syntheticLift(reps: 3);

    test('defaults reproduce the baseline', () {
      final a = analyzePositions(signal, 60);
      final b = analyzePositions(signal, 60, config: const AnalysisConfig());
      expect(a.phases, b.phases);
    });

    test('huge pen collapses segmentation', () {
      final r = analyzePositions(signal, 60,
          config: const AnalysisConfig(pen: 1e9));
      expect(r.segments.length, lessThanOrEqualTo(2));
    });

    test('minRepRatio=0 selects at least as many candidates', () {
      final base = analyzePositions(signal, 60);
      final loose = analyzePositions(signal, 60,
          config: const AnalysisConfig(minRepRatio: 0));
      expect(loose.phases.length, greaterThanOrEqualTo(base.phases.length));
    });

    test('extensionLookahead=0 phases are no longer than defaults', () {
      final base = analyzePositions(signal, 60);
      final tight = analyzePositions(signal, 60,
          config: const AnalysisConfig(extensionLookahead: 0));
      expect(tight.phases.length, base.phases.length);
      for (var i = 0; i < base.phases.length; i++) {
        final (bs, be) = base.phases[i];
        final (ts, te) = tight.phases[i];
        expect(te - ts, lessThanOrEqualTo(be - bs));
      }
    });

    test('mergeMinVel very high disables merging', () {
      final r = analyzePositions(signal, 60,
          config: const AnalysisConfig(mergeMinVel: 1e9));
      expect(r.segments.where((s) => s.merged), isEmpty);
    });
  });

  group('peaks method', () {
    test('detects reps on synthetic signal', () {
      final r = analyzePositions(syntheticLift(reps: 3), 60);
      // The leading rest is a boundary plateau, which scipy-style peak
      // finding cannot mark as a trough — so the first rep has no trough to
      // pair with and the peaks method reports reps - 1 here (reference
      // behavior).
      expect(r.peaksPhases.length, 2);
    });

    test('minFrames gates short pairs', () {
      final phases = detectConcentricPeaks(
        syntheticLift(reps: 2, repLen: 30),
        minFrames: 1000,
      );
      expect(phases, isEmpty);
    });
  });
}
