import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/analysis/signal.dart';

void main() {
  group('median', () {
    test('odd and even lengths (numpy semantics)', () {
      expect(median([3, 1, 2]), 2);
      expect(median([4, 1, 3, 2]), 2.5);
      expect(median([5]), 5);
      expect(median([]).isNaN, isTrue);
    });
  });

  group('interpolateNan', () {
    test('interior gap is linear', () {
      expect(interpolateNan([0, double.nan, 2]), [0, 1, 2]);
      expect(interpolateNan([0, double.nan, double.nan, 3]), [0, 1, 2, 3]);
    });

    test('edges clamp to nearest valid (np.interp)', () {
      expect(interpolateNan([double.nan, 5, 7, double.nan]), [5, 5, 7, 7]);
    });

    test('all-NaN unchanged, no-NaN unchanged', () {
      expect(interpolateNan([double.nan, double.nan]).every((v) => v.isNaN),
          isTrue);
      expect(interpolateNan([1, 2, 3]), [1, 2, 3]);
    });
  });

  group('removeOutliers', () {
    test('replaces spikes beyond threshold with local median', () {
      final flat = List<double?>.filled(9, 100.0);
      flat[4] = 300.0; // spike > threshold 50
      final out = removeOutliers(flat, window: 3, threshold: 50);
      expect(out[4], 100.0);
    });

    test('keeps values within threshold', () {
      final data = [100.0, 110.0, 120.0, 130.0, 140.0].cast<double?>();
      final out = removeOutliers(data, window: 3, threshold: 50);
      expect(out, [100.0, 110.0, 120.0, 130.0, 140.0]);
    });

    test('preserves nulls as NaN and skips tiny neighborhoods', () {
      final out = removeOutliers([null, 1.0, null], window: 3, threshold: 50);
      expect(out[0].isNaN, isTrue);
      expect(out[1], 1.0);
      expect(out[2].isNaN, isTrue);
    });

    test('sequential semantics: corrected values feed later windows', () {
      // Two adjacent spikes: the first correction changes the second's window.
      final data =
          [0.0, 0.0, 0.0, 200.0, 200.0, 0.0, 0.0, 0.0].cast<double?>();
      final out = removeOutliers(data, window: 2, threshold: 50);
      expect(out[3], 0.0);
      expect(out[4], lessThan(200.0));
    });
  });

  group('savgolFilter', () {
    test('reproduces a cubic exactly (interior and interp edges)', () {
      double f(double x) => 2 + 3 * x - 0.5 * x * x + 0.01 * x * x * x;
      final y = [for (var i = 0; i < 30; i++) f(i.toDouble())];
      final out = savgolFilter(y, 9, 3);
      for (var i = 0; i < y.length; i++) {
        expect(out[i], closeTo(y[i], 1e-8), reason: 'i=$i');
      }
    });

    test('smooths noise toward the underlying signal', () {
      final rng = math.Random(42);
      final y = [
        for (var i = 0; i < 200; i++)
          math.sin(i / 20) * 100 + (rng.nextDouble() - 0.5) * 10
      ];
      final out = savgolFilter(y, 9, 3);
      double sq(List<double> a) {
        var s = 0.0;
        for (var i = 0; i < a.length; i++) {
          final d = a[i] - math.sin(i / 20) * 100;
          s += d * d;
        }
        return s;
      }

      expect(sq(out), lessThan(sq(y)));
    });

    test('window larger than signal returns input (documented deviation)', () {
      expect(savgolFilter([1, 2, 3], 9, 3), [1, 2, 3]);
      expect(savgolFilter([], 9, 3), isEmpty);
    });
  });

  group('computeVelocity', () {
    test('first element zero, finite difference scaled by fps', () {
      expect(computeVelocity([0.0, 1.0, 3.0], 30), [0.0, 30.0, 60.0]);
    });

    test('null neighbors produce zero velocity', () {
      final v = computeVelocity([0.0, null, 2.0], 30);
      expect(v, [0.0, 0.0, 0.0]);
    });

    test('NaN propagates (reference behavior on cleaned signal)', () {
      final v = computeVelocity([0.0, double.nan, 2.0], 30);
      expect(v[0], 0.0);
      expect(v[1].isNaN, isTrue);
      expect(v[2].isNaN, isTrue);
    });

    test('empty input', () {
      expect(computeVelocity([], 30), isEmpty);
    });
  });
}
