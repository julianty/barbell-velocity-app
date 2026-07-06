import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/analysis/concentric.dart';
import 'package:barbell_velocity_app/analysis/models.dart';
import 'package:barbell_velocity_app/analysis/pipeline.dart';

void main() {
  group('TrackPoint', () {
    test('fromJson with center', () {
      final p = TrackPoint.fromJson({
        'frame': 'frame_000001.jpg',
        'center': [12, 34.5],
      });
      expect(p.frame, 'frame_000001.jpg');
      expect(p.center, [12.0, 34.5]);
    });

    test('fromJson with null center', () {
      final p = TrackPoint.fromJson({'frame': 'f', 'center': null});
      expect(p.center, isNull);
    });
  });

  group('extractPositions / analyzeTrack', () {
    test('position is -y, null preserved', () {
      final points = [
        const TrackPoint(frame: 'a', center: [10, 100]),
        const TrackPoint(frame: 'b'),
        const TrackPoint(frame: 'c', center: [10, 80]),
      ];
      expect(extractPositions(points), [-100.0, null, -80.0]);
    });

    test('analyzeTrack runs the full pipeline', () {
      final points = [
        for (var i = 0; i < 300; i++)
          TrackPoint(frame: 'f$i', center: [10, 500.0 - i])
      ];
      final r = analyzeTrack(BarbellTrack(points: points, fps: 60));
      expect(r.fps, 60);
      expect(r.smoothPositions.length, 300);
      expect(r.hasReps, isTrue);
    });
  });

  group('RepResult', () {
    test('toJson round-trips fields', () {
      const rep = RepResult(
        repIndex: 0,
        startFrame: 10,
        endFrame: 50,
        avgVelPxS: 120.5,
        maxVelPxS: 300.0,
        durationS: 0.667,
        displacementPx: 80.0,
      );
      final j = rep.toJson();
      expect(j['startFrame'], 10);
      expect(j['avgVelPxS'], 120.5);
      expect(j['displacementPx'], 80.0);
    });
  });

  group('detectConcentricRuptures without smoothVelocity', () {
    test('falls back to per-frame displacement rate', () {
      final signal = [
        for (var i = 0; i < 200; i++)
          (i >= 50 && i < 100) ? (i - 50) * 10.0 : (i < 50 ? 0.0 : 500.0)
      ].cast<double?>();
      final (phases, segments) = detectConcentricRuptures(
        signal,
        pen: 20,
        minFrames: 5,
        mergeMinVel: 1.0, // px/frame scale in fallback mode
      );
      expect(segments, isNotEmpty);
      expect(phases, isNotEmpty);
    });
  });
}
