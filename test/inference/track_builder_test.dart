import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/inference/inference_backend.dart';
import 'package:barbell_velocity_app/inference/track_builder.dart';
import 'package:barbell_velocity_app/input/frame_source.dart';

/// A person with wrists at (lx, ly) / (rx, ry) and the given bbox.
PoseDetection person({
  required double lx,
  required double ly,
  required double rx,
  required double ry,
  double x1 = 0,
  double y1 = 0,
  double x2 = 100,
  double y2 = 100,
  double confidence = 0.9,
}) {
  final kp = List<Keypoint>.generate(17, (_) => const Keypoint(0, 0, 0.5));
  kp[kLeftWrist] = Keypoint(lx, ly, 0.5);
  kp[kRightWrist] = Keypoint(rx, ry, 0.5);
  return PoseDetection(
      x1: x1, y1: y1, x2: x2, y2: y2, confidence: confidence, keypoints: kp);
}

void main() {
  group('computeBarbellCenter', () {
    test('no detections -> null', () {
      expect(computeBarbellCenter([]), isNull);
    });

    test('single detection -> its wrist midpoint', () {
      final c = computeBarbellCenter([
        person(lx: 10, ly: 20, rx: 30, ry: 40),
      ]);
      expect(c, [20.0, 30.0]);
    });

    test('single detection wins even if another would be closer', () {
      // Reference precedence: len == 1 short-circuits before proximity.
      final c = computeBarbellCenter(
        [person(lx: 100, ly: 100, rx: 100, ry: 100)],
        lastCenter: [0, 0],
      );
      expect(c, [100.0, 100.0]);
    });

    test('multiple detections with lastCenter -> nearest wrist midpoint', () {
      final near = person(lx: 9, ly: 9, rx: 11, ry: 11); // midpoint (10, 10)
      final far = person(lx: 90, ly: 90, rx: 110, ry: 110,
          x2: 1000, y2: 1000); // bigger bbox, but proximity wins
      final c = computeBarbellCenter([far, near], lastCenter: [10, 10]);
      expect(c, [10.0, 10.0]);
    });

    test('multiple detections without lastCenter -> largest bbox', () {
      final small = person(lx: 0, ly: 0, rx: 2, ry: 2, x2: 10, y2: 10);
      final big = person(lx: 50, ly: 50, rx: 70, ry: 70, x2: 500, y2: 500);
      final c = computeBarbellCenter([small, big]);
      expect(c, [60.0, 60.0]);
    });

    test('selected person with too few keypoints -> null', () {
      final det = PoseDetection(
          x1: 0,
          y1: 0,
          x2: 10,
          y2: 10,
          confidence: 0.9,
          keypoints: List<Keypoint>.generate(
              kRightWrist, (_) => const Keypoint(0, 0, 0.5)));
      expect(computeBarbellCenter([det]), isNull);
    });

    test('candidates missing wrists are skipped in proximity search', () {
      final noWrists = PoseDetection(
          x1: 0,
          y1: 0,
          x2: 10,
          y2: 10,
          confidence: 0.9,
          keypoints: const []);
      final ok = person(lx: 40, ly: 40, rx: 60, ry: 60); // midpoint (50, 50)
      final c = computeBarbellCenter([noWrists, ok], lastCenter: [0, 0]);
      expect(c, [50.0, 50.0]);
    });
  });

  group('TrackBuilder', () {
    test('threads lastCenter across frames and records misses as null', () {
      final builder = TrackBuilder();
      final a = person(lx: 0, ly: 0, rx: 20, ry: 20); // midpoint (10, 10)
      final b = person(lx: 180, ly: 180, rx: 220, ry: 220,
          x2: 1000, y2: 1000); // midpoint (200, 200), largest bbox

      // Frame 0: no lastCenter, two people -> largest bbox (b).
      builder.add('f0', [a, b]);
      // Frame 1: nothing detected -> null point, lastCenter kept.
      builder.add('f1', []);
      // Frame 2: lastCenter (200, 200) -> proximity picks b again.
      builder.add('f2', [a, b]);

      final track = builder.build(30.0);
      expect(track.fps, 30.0);
      expect(track.points.length, 3);
      expect(track.points[0].center, [200.0, 200.0]);
      expect(track.points[1].center, isNull);
      expect(track.points[2].center, [200.0, 200.0]);
      expect(track.points.map((p) => p.frame), ['f0', 'f1', 'f2']);
    });
  });

  group('estimateFps', () {
    test('fewer than two timestamps -> NaN', () {
      expect(estimateFps([]), isNaN);
      expect(estimateFps([0.5]), isNaN);
    });

    test('uniform timestamps -> exact fps', () {
      final ts = [for (var i = 0; i < 10; i++) i / 30.0];
      expect(estimateFps(ts), closeTo(30.0, 1e-9));
    });

    test('median is robust to a dropped frame', () {
      // 30 fps with one frame missing (a single 2/30 gap).
      final ts = [0.0, 1 / 30, 2 / 30, 4 / 30, 5 / 30, 6 / 30, 7 / 30];
      expect(estimateFps(ts), closeTo(30.0, 1e-9));
    });

    test('duplicate timestamps making median dt zero -> NaN', () {
      expect(estimateFps([1.0, 1.0, 1.0]), isNaN);
    });
  });
}
