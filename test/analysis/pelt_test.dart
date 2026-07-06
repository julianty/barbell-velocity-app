import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/analysis/pelt.dart';

void main() {
  group('peltL2', () {
    test('single-regime signal yields one segment', () {
      final signal = List<double>.filled(50, 1.0);
      expect(peltL2(signal, pen: 10), [50]);
    });

    test('detects an obvious mean shift near the true changepoint', () {
      final signal = [
        ...List<double>.filled(50, 0.0),
        ...List<double>.filled(50, 10.0),
      ];
      final bkps = peltL2(signal, pen: 10);
      expect(bkps.last, 100);
      expect(bkps.length, 2);
      // jump=5 quantizes breakpoints to multiples of 5.
      expect(bkps.first, 50);
    });

    test('respects jump quantization', () {
      final signal = [
        ...List<double>.filled(48, 0.0), // true break at 48, not on grid
        ...List<double>.filled(52, 10.0),
      ];
      final bkps = peltL2(signal, pen: 10);
      for (final b in bkps.sublist(0, bkps.length - 1)) {
        expect(b % 5, 0, reason: 'interior breakpoints on jump grid');
      }
    });

    test('higher penalty gives fewer breakpoints', () {
      final signal = [
        for (var i = 0; i < 120; i++) (i ~/ 20).isEven ? 0.0 : 5.0
      ];
      final low = peltL2(signal, pen: 1);
      final high = peltL2(signal, pen: 1e6);
      expect(high.length, lessThanOrEqualTo(low.length));
      expect(high, [120]);
    });

    test('degenerate inputs', () {
      expect(peltL2([], pen: 10), isEmpty);
      expect(peltL2([1.0], pen: 10), [1]);
    });
  });
}
