/// End-to-end analysis pipeline, mirroring `yolo_pose/analysis.py` __main__:
/// extract positions -> outlier removal -> Savitzky-Golay -> velocities ->
/// concentric detection (ruptures primary, peaks secondary) -> per-rep
/// metrics.
library;

import 'analysis_config.dart';
import 'concentric.dart';
import 'models.dart';
import 'signal.dart';

/// `extract_positions`: position = -center.y (up = positive), null when the
/// frame had no detection.
List<double?> extractPositions(List<TrackPoint> track) =>
    [for (final p in track) p.center == null ? null : -p.center![1]];

/// Analyze a barbell track. Accepts the raw track; see [analyzePositions]
/// for the signal-level entry point used by fixture tests.
AnalysisResult analyzeTrack(
  BarbellTrack track, {
  AnalysisConfig config = const AnalysisConfig(),
}) =>
    analyzePositions(extractPositions(track.points), track.fps, config: config);

/// Signal-level pipeline entry: positions are `-y` px values with null for
/// missing frames.
AnalysisResult analyzePositions(
  List<double?> rawPositions,
  double fps, {
  AnalysisConfig config = const AnalysisConfig(),
}) {
  final raw = [for (final p in rawPositions) p ?? double.nan];

  // Degenerate tracks: the reference crashes on empty/all-missing input;
  // here they produce an empty result so the app can show a clear error.
  if (raw.isEmpty || raw.every((v) => v.isNaN)) {
    return AnalysisResult(
      rawPositions: raw,
      cleanPositions: raw,
      smoothPositions: raw,
      rawVelocity: List<double>.filled(raw.length, 0.0),
      smoothVelocity: List<double>.filled(raw.length, 0.0),
      segments: const [],
      phases: const [],
      peaksPhases: const [],
      reps: const [],
      fps: fps,
    );
  }

  final clean = removeOutliers(rawPositions,
      window: config.outlierWindow, threshold: config.outlierThreshold);
  // The reference smooths the *cleaned* signal (NaNs interpolated inside).
  final smoothOfClean =
      smoothPositions(clean, window: config.sgWindow, poly: config.sgPoly);

  final rawVelocity = computeVelocity(clean, fps);
  final smoothVelocity = computeVelocity(smoothOfClean, fps);

  final (phases, segments) = detectConcentricRuptures(
    smoothOfClean,
    pen: config.pen,
    minFrames: config.minFrames,
    smoothVelocity: smoothVelocity,
    mergeMinVel: config.mergeMinVel,
    extensionLookahead: config.extensionLookahead,
    minRepRatio: config.minRepRatio,
    peltMinSize: config.peltMinSize,
    peltJump: config.peltJump,
  );

  final peaksPhases =
      detectConcentricPeaks(smoothOfClean, minFrames: config.peaksMinFrames);

  final reps = <RepResult>[];
  for (var i = 0; i < phases.length; i++) {
    final (start, end) = phases[i];
    final slice = smoothVelocity.sublist(start, end); // end-exclusive, as ref
    var maxV = slice.first;
    var sum = 0.0;
    for (final v in slice) {
      sum += v;
      if (v > maxV) maxV = v;
    }
    reps.add(RepResult(
      repIndex: i,
      startFrame: start,
      endFrame: end,
      avgVelPxS: sum / slice.length,
      maxVelPxS: maxV,
      durationS: (end - start) / fps,
      displacementPx: smoothOfClean[end] - smoothOfClean[start],
    ));
  }

  return AnalysisResult(
    rawPositions: raw,
    cleanPositions: clean,
    smoothPositions: smoothOfClean,
    rawVelocity: rawVelocity,
    smoothVelocity: smoothVelocity,
    segments: segments,
    phases: phases,
    peaksPhases: peaksPhases,
    reps: reps,
    fps: fps,
  );
}
