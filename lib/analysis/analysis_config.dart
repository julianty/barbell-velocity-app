/// All tunable parameters of the analysis pipeline.
///
/// Defaults are the values the Python reference actually runs with
/// (call-site values in `yolo_pose/analysis.py`, which override some
/// function-signature defaults — see REFERENCE_NOTES.md).
class AnalysisConfig {
  /// Half-width of the rolling-median outlier window (frames).
  final int outlierWindow;

  /// Max deviation from local median (px) before a point is replaced.
  final double outlierThreshold;

  /// Savitzky-Golay window length in frames (odd).
  final int sgWindow;

  /// Savitzky-Golay polynomial order.
  final int sgPoly;

  /// PELT penalty.
  final double pen;

  /// Minimum segment length (frames) to be a concentric candidate.
  final int minFrames;

  /// px/s; segments below this avg velocity are excluded from merge runs.
  final double mergeMinVel;

  /// Max boundary extension per side (frames) after candidate selection.
  final int extensionLookahead;

  /// Fraction of estimated full-rep displacement a candidate must cover.
  final double minRepRatio;

  /// PELT minimum segment size (ruptures default).
  final int peltMinSize;

  /// PELT jump: breakpoints considered only at multiples of this (ruptures default).
  final int peltJump;

  /// Minimum rep length (frames) for the peaks-based detector.
  final int peaksMinFrames;

  const AnalysisConfig({
    this.outlierWindow = 3,
    this.outlierThreshold = 50.0,
    this.sgWindow = 9,
    this.sgPoly = 3,
    this.pen = 20.0,
    this.minFrames = 5,
    this.mergeMinVel = 50.0,
    this.extensionLookahead = 30,
    this.minRepRatio = 0.60,
    this.peltMinSize = 2,
    this.peltJump = 5,
    this.peaksMinFrames = 20,
  });
}
