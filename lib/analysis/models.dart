/// Data models for the barbell velocity analysis pipeline.
library;

/// One entry of the barbell track: the wrist-average "barbell" center for a
/// frame, or null when no person/wrists were detected.
class TrackPoint {
  final String frame;

  /// [x, y] in pixels (image coordinates, y down), or null if missing.
  final List<double>? center;

  const TrackPoint({required this.frame, this.center});

  factory TrackPoint.fromJson(Map<String, dynamic> json) {
    final c = json['center'];
    return TrackPoint(
      frame: json['frame'] as String,
      center: c == null
          ? null
          : [(c[0] as num).toDouble(), (c[1] as num).toDouble()],
    );
  }
}

/// The full per-frame barbell track plus the video frame rate.
class BarbellTrack {
  final List<TrackPoint> points;
  final double fps;

  const BarbellTrack({required this.points, required this.fps});
}

/// A PELT-derived segment of the position signal with its selection flags.
/// Mirrors the reference's segment dicts (start/end are frame indices into
/// the position array; adjacent segments share their boundary frame).
class Segment {
  final int start;
  final int end;
  final int frames;
  final double displacement;
  final bool skippedShort;
  final bool merged;
  bool selected;

  Segment({
    required this.start,
    required this.end,
    required this.frames,
    required this.displacement,
    required this.skippedShort,
    this.merged = false,
    this.selected = false,
  });
}

/// A detected concentric phase: [start, end] frame indices (inclusive).
typedef Phase = (int start, int end);

/// Per-rep metrics, matching what the reference computes for its rep table.
/// Velocities are px/s over `smoothVelocity[start:end)` (end-exclusive, as in
/// the reference).
class RepResult {
  final int repIndex;
  final int startFrame;
  final int endFrame;
  final double avgVelPxS;
  final double maxVelPxS;
  final double durationS;
  final double displacementPx;

  const RepResult({
    required this.repIndex,
    required this.startFrame,
    required this.endFrame,
    required this.avgVelPxS,
    required this.maxVelPxS,
    required this.durationS,
    required this.displacementPx,
  });

  Map<String, dynamic> toJson() => {
        'repIndex': repIndex,
        'startFrame': startFrame,
        'endFrame': endFrame,
        'avgVelPxS': avgVelPxS,
        'maxVelPxS': maxVelPxS,
        'durationS': durationS,
        'displacementPx': displacementPx,
      };
}

/// Full analysis output: every intermediate signal plus segments, phases and
/// per-rep results. Positions use NaN for missing frames.
class AnalysisResult {
  final List<double> rawPositions; // -y, NaN where center was null
  final List<double> cleanPositions; // after outlier removal (NaN preserved)
  final List<double> smoothPositions; // NaN-interpolated + Savitzky-Golay
  final List<double> rawVelocity; // px/s from cleanPositions
  final List<double> smoothVelocity; // px/s from smoothPositions
  final List<Segment> segments;
  final List<Phase> phases; // ruptures method (primary)
  final List<Phase> peaksPhases; // peaks method (secondary)
  final List<RepResult> reps; // from `phases`
  final double fps;

  const AnalysisResult({
    required this.rawPositions,
    required this.cleanPositions,
    required this.smoothPositions,
    required this.rawVelocity,
    required this.smoothVelocity,
    required this.segments,
    required this.phases,
    required this.peaksPhases,
    required this.reps,
    required this.fps,
  });

  bool get hasReps => reps.isNotEmpty;
}
