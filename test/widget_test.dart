/// Widget tests: home-screen state machine (idle -> processing -> results /
/// error) with an injected fake pipeline, and the results view (rep table +
/// velocity chart, zero-reps empty state).
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/inference/inference_backend.dart';
import 'package:barbell_velocity_app/input/frame_source.dart';
import 'package:barbell_velocity_app/input/video_picker.dart';
import 'package:barbell_velocity_app/pipeline/video_pipeline.dart';
import 'package:barbell_velocity_app/ui/home_screen.dart';
import 'package:barbell_velocity_app/ui/lift_player.dart';
import 'package:barbell_velocity_app/ui/velocity_chart.dart';

class _FakeSource implements FrameSource {
  final List<double?> positions;
  final double fps;
  _FakeSource(this.positions, this.fps);

  @override
  Future<VideoInfo> open() async => VideoInfo(
      fps: fps, durationS: positions.length / fps, width: 4, height: 4);

  @override
  Stream<VideoFrame> frames() async* {
    for (var i = 0; i < positions.length; i++) {
      // A real timer per frame so the processing state is observable in
      // fake-async tests (pure microtasks would finish before the first pump).
      await Future<void>.delayed(const Duration(milliseconds: 1));
      yield VideoFrame(
          index: i,
          timestampS: i / fps,
          width: 4,
          height: 4,
          rgba: Uint8List(64));
    }
  }

  @override
  Future<void> dispose() async {}
}

class _FakeBackend implements InferenceBackend {
  final List<double?> positions;
  _FakeBackend(this.positions);

  @override
  Future<void> load() async {}

  @override
  Future<List<PoseDetection>> infer(VideoFrame frame) async {
    final pos = positions[frame.index];
    if (pos == null) return const [];
    final kp = List<Keypoint>.generate(17, (_) => const Keypoint(0, 0, 0.5));
    kp[kLeftWrist] = Keypoint(100, -pos, 0.9);
    kp[kRightWrist] = Keypoint(120, -pos, 0.9);
    return [
      PoseDetection(
          x1: 0, y1: 0, x2: 200, y2: 400, confidence: 0.9, keypoints: kp)
    ];
  }

  @override
  Future<void> dispose() async {}
}

/// Two clean 1-second concentric pushes at 30 fps, separated by rests.
List<double?> twoRepPositions() {
  final positions = <double?>[];
  void rest(double y, int n) => positions.addAll(List.filled(n, y));
  void push(double from, double to, int n) => positions.addAll(
      [for (var i = 1; i <= n; i++) from + (to - from) * i / n]);
  rest(0, 30);
  push(0, 400, 30);
  rest(400, 15);
  push(400, 0, 30); // eccentric (down)
  rest(0, 30);
  push(0, 400, 30);
  rest(400, 30);
  return positions;
}

VideoPipeline _pipelineFor(List<double?> positions, {double fps = 30}) =>
    VideoPipeline(
      frameSourceFactory: (_) => _FakeSource(positions, fps),
      backendFactory: () => _FakeBackend(positions),
      useIsolate: false, // real isolates never resolve in fake-async tests
    );

Future<PickedVideo?> _picker() async =>
    const PickedVideo(name: 'lift.mp4', path: '/fake/lift.mp4');

/// Pumps fake time forward until [finder] matches. pumpAndSettle is not
/// usable here: it stops when no *frame* is scheduled, but the fake frame
/// stream's next event is a pending timer, so it can stall mid-pipeline.
Future<void> pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 500; i++) {
    if (finder.evaluate().isNotEmpty) return;
    await tester.pump(const Duration(milliseconds: 10));
  }
  fail('pumpUntilFound: $finder never matched');
}

void main() {
  testWidgets('idle state shows the pick button', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: HomeScreen(picker: _picker, pipeline: _pipelineFor(const []))));
    expect(find.text('Pick a video'), findsOneWidget);
    expect(find.text('Analyze a lift video'), findsOneWidget);
  });

  testWidgets('happy path: pick -> processing -> results with table and chart',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
            picker: _picker, pipeline: _pipelineFor(twoRepPositions()))));

    await tester.tap(find.text('Pick a video'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 5));
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.textContaining('Analyzing lift.mp4'), findsOneWidget);

    await pumpUntilFound(tester, find.text('Best avg velocity'));
    expect(find.byType(PositionChart), findsOneWidget);
    expect(find.byType(VelocityChart), findsOneWidget);
    expect(find.byType(LiftPlayer), findsOneWidget);
    // Rep results render as stacked cards (not a DataTable) with per-rep
    // avg/peak velocity text.
    expect(find.textContaining('px/s avg'), findsNWidgets(2));
    expect(find.text('Reps'), findsOneWidget);

    // Unmount to cancel the player's playback timer before the test ends.
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('no lifter detected shows the error state', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
            picker: _picker,
            pipeline: _pipelineFor(List<double?>.filled(30, null)))));

    await tester.tap(find.text('Pick a video'));
    await pumpUntilFound(tester, find.textContaining('No lifter was detected'));
    expect(find.text('Try another video'), findsOneWidget);
  });

  testWidgets('still bar yields the zero-reps empty state', (tester) async {
    // Exactly-flat zero signal: any nonzero constant leaves Savitzky-Golay
    // rounding noise, and the reference's fallback then reports one
    // zero-displacement "rep" (faithful reference behavior).
    await tester.pumpWidget(MaterialApp(
        home: HomeScreen(
            picker: _picker,
            pipeline: _pipelineFor(List<double?>.filled(60, 0.0)))));

    await tester.tap(find.text('Pick a video'));
    await pumpUntilFound(tester, find.text('No reps detected'));
    // Charts and player still shown for debugging; unmount to cancel the
    // player's playback timer before the test ends.
    expect(find.byType(PositionChart), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
