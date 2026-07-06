/// Integration tests for VideoPipeline with fake frame/inference layers,
/// including a fixture-backed run: frames whose wrist midpoints trace a
/// golden fixture's positions must yield that fixture's reps exactly.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/inference/inference_backend.dart';
import 'package:barbell_velocity_app/input/frame_source.dart';
import 'package:barbell_velocity_app/input/video_picker.dart';
import 'package:barbell_velocity_app/pipeline/video_pipeline.dart';

class FakeFrameSource implements FrameSource {
  final int frameCount;
  final double fps;

  /// NaN mimics the web, where fps is unknown until frames are extracted.
  final double reportedFps;
  final bool failOnOpen;
  bool disposed = false;

  FakeFrameSource({
    required this.frameCount,
    required this.fps,
    double? reportedFps,
    this.failOnOpen = false,
  }) : reportedFps = reportedFps ?? fps;

  @override
  Future<VideoInfo> open() async {
    if (failOnOpen) throw StateError('corrupt container');
    return VideoInfo(
        fps: reportedFps, durationS: frameCount / fps, width: 4, height: 4);
  }

  @override
  Stream<VideoFrame> frames() async* {
    for (var i = 0; i < frameCount; i++) {
      yield VideoFrame(
        index: i,
        timestampS: i / fps,
        width: 4,
        height: 4,
        rgba: Uint8List(4 * 4 * 4),
      );
    }
  }

  @override
  Future<void> dispose() async => disposed = true;
}

/// Emits one person per frame whose wrist midpoint has y = -positions[i]
/// (analysis position = -center.y), or no detections where null.
class FakeInferenceBackend implements InferenceBackend {
  final List<double?> positions;
  bool disposed = false;

  FakeInferenceBackend(this.positions);

  @override
  Future<void> load() async {}

  @override
  Future<List<PoseDetection>> infer(VideoFrame frame) async {
    final pos = frame.index < positions.length ? positions[frame.index] : null;
    if (pos == null) return const [];
    final kp = List<Keypoint>.generate(17, (_) => const Keypoint(0, 0, 0.5));
    kp[kLeftWrist] = Keypoint(100, -pos, 0.9);
    kp[kRightWrist] = Keypoint(120, -pos, 0.9);
    return [
      PoseDetection(
          x1: 0, y1: 0, x2: 200, y2: 400, confidence: 0.9, keypoints: kp),
    ];
  }

  @override
  Future<void> dispose() async => disposed = true;
}

const _video = PickedVideo(name: 'lift.mp4', path: '/fake/lift.mp4');

VideoPipeline _pipeline(FakeFrameSource source, FakeInferenceBackend backend) =>
    VideoPipeline(
        frameSourceFactory: (_) => source, backendFactory: () => backend);

void main() {
  test('fixture-backed end to end: reps match the Python reference',
      () async {
    final file = Directory('test/fixtures')
        .listSync()
        .whereType<File>()
        .firstWhere((f) => f.path.endsWith('.golden.json'));
    final data = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    final fps = (data['source']['fps'] as num).toDouble();
    final positions = [
      for (final v in data['input_positions'] as List)
        v == null ? null : (v as num).toDouble()
    ];

    final source = FakeFrameSource(
        frameCount: positions.length, fps: fps, reportedFps: fps);
    final backend = FakeInferenceBackend(positions);
    final output = await _pipeline(source, backend).run(_video);

    final expectedReps = data['reps'] as List;
    expect(output.analysis.reps.length, expectedReps.length);
    for (var i = 0; i < expectedReps.length; i++) {
      final e = expectedReps[i] as Map<String, dynamic>;
      final r = output.analysis.reps[i];
      expect(r.startFrame, e['start_frame'], reason: 'rep $i start');
      expect(r.endFrame, e['end_frame'], reason: 'rep $i end');
      expect(r.avgVelPxS, closeTo((e['avg_vel_px_s'] as num).toDouble(), 1e-3),
          reason: 'rep $i avg');
    }
    expect(source.disposed, isTrue);
    expect(backend.disposed, isTrue);
  });

  test('web-style NaN fps is recovered from frame timestamps', () async {
    final positions =
        List<double?>.generate(60, (i) => 100.0 * (1 - (i - 30).abs() / 30));
    final source = FakeFrameSource(
        frameCount: 60, fps: 30, reportedFps: double.nan);
    final output = await _pipeline(source, FakeInferenceBackend(positions))
        .run(_video);
    expect(output.track.fps, closeTo(30.0, 1e-9));
  });

  test('reports progress with an increasing fraction', () async {
    final positions = List<double?>.filled(20, 0.0);
    final source = FakeFrameSource(frameCount: 20, fps: 10);
    final fractions = <double>[];
    await _pipeline(source, FakeInferenceBackend(positions)).run(_video,
        onProgress: (p) {
      if (p.fraction != null) fractions.add(p.fraction!);
    });
    expect(fractions.length, 20);
    expect(fractions.last, greaterThan(fractions.first));
  });

  test('unreadable video: open() failure surfaces as UnreadableVideo',
      () async {
    final source = FakeFrameSource(frameCount: 0, fps: 30, failOnOpen: true);
    expect(
      _pipeline(source, FakeInferenceBackend(const [])).run(_video),
      throwsA(isA<UnreadableVideoException>()),
    );
  });

  test('unreadable video: no decodable frames', () async {
    final source = FakeFrameSource(frameCount: 1, fps: 30);
    expect(
      _pipeline(source, FakeInferenceBackend(const [null])).run(_video),
      throwsA(isA<UnreadableVideoException>()),
    );
  });

  test('no barbell: frames decode but nobody is ever detected', () async {
    final source = FakeFrameSource(frameCount: 30, fps: 30);
    expect(
      _pipeline(source, FakeInferenceBackend(List.filled(30, null)))
          .run(_video),
      throwsA(isA<NoBarbellException>()),
    );
  });

  test('chartTimeForPlaybackTime maps through uneven frame timestamps',
      () async {
    final positions =
        List<double?>.generate(40, (i) => 100.0 * (1 - (i - 20).abs() / 20));
    final source = FakeFrameSource(frameCount: 40, fps: 20);
    final output = await _pipeline(source, FakeInferenceBackend(positions))
        .run(_video);

    // Uniform fake timestamps: mapping is identity onto index/fps grid.
    expect(output.frameTimestampsS.length, 40);
    expect(output.chartTimeForPlaybackTime(0), 0);
    expect(output.chartTimeForPlaybackTime(1.0),
        closeTo(20 / output.analysis.fps, 1e-9));
    // Before the first frame and beyond the last clamp to the ends.
    expect(output.chartTimeForPlaybackTime(-1), 0);
    expect(output.chartTimeForPlaybackTime(999),
        closeTo(39 / output.analysis.fps, 1e-9));

    // Uneven timestamps (as rVFC produces): playback time must resolve to
    // the sampled-frame index, not to t itself.
    final uneven = PipelineOutput(
      info: output.info,
      track: output.track,
      analysis: output.analysis,
      frameTimestampsS: [0.0, 0.1, 0.4, 0.8], // wildly uneven sampling
    );
    // t=0.5 falls after sample 2 (ts 0.4) -> chart x = 2 / fps.
    expect(uneven.chartTimeForPlaybackTime(0.5),
        closeTo(2 / output.analysis.fps, 1e-9));
  });

  test('still lift video yields output with zero reps (not an error)',
      () async {
    // Flat zero: a nonzero constant leaves Savitzky-Golay rounding noise and
    // the reference's fallback then emits one ~0-displacement "rep".
    final source = FakeFrameSource(frameCount: 40, fps: 30);
    final output = await _pipeline(
            source, FakeInferenceBackend(List<double?>.filled(40, 0.0)))
        .run(_video);
    expect(output.analysis.hasReps, isFalse);
  });
}
