import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/analysis/find_peaks.dart';

void main() {
  group('localMaxima', () {
    test('simple peaks; endpoints excluded', () {
      expect(localMaxima([0, 1, 0, 2, 0]), [1, 3]);
      expect(localMaxima([5, 0, 0]), isEmpty);
      expect(localMaxima([0, 0, 5]), isEmpty);
    });

    test('plateau reports midpoint (scipy convention)', () {
      expect(localMaxima([0, 3, 3, 3, 0]), [2]);
      expect(localMaxima([0, 3, 3, 0]), [1]); // (1+2)~/2
    });

    test('monotone and flat signals have no maxima', () {
      expect(localMaxima([1, 2, 3, 4]), isEmpty);
      expect(localMaxima([2, 2, 2, 2]), isEmpty);
    });
  });

  group('findPeaks', () {
    test('distance keeps the higher of two close peaks', () {
      // peaks at 2 (h=5) and 4 (h=7), distance 3 -> keep index 4.
      expect(findPeaks([0, 0, 5, 0, 7, 0, 0], distance: 3), [4]);
    });

    test('prominence filters shallow bumps', () {
      final x = <double>[0, 10, 0, 1, 0.5, 1, 0, 10, 0];
      expect(findPeaks(x, prominence: 5), [1, 7]);
    });

    test('distance applied before prominence (scipy order)', () {
      // A tall peak suppresses a near neighbor by distance even when both
      // would pass the prominence filter.
      final x = <double>[0, 6, 0, 8, 0, 0, 0, 6, 0];
      expect(findPeaks(x, distance: 3, prominence: 1), [3, 7]);
    });
  });
}
