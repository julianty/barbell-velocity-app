/// Platform-agnostic pose inference seam.
///
/// NOTE: despite the original handoff's wording ("barbell detections"), the
/// reference pipeline tracks the *lifter's pose*: COCO-17 keypoints, with
/// the wrists (indices 9, 10) averaged into the barbell-proxy track. See
/// PROGRESS.md "Decisions".
///
/// Implementations: iOS via the `ultralytics_yolo` plugin (CoreML / ANE),
/// web via ONNX Runtime (yolov8s-pose.onnx in assets/models/, output
/// (1, 56, 8400): [cx, cy, w, h, conf, 17 x (x, y, conf)] per anchor,
/// NMS not baked in).
library;

import '../input/frame_source.dart';

/// COCO keypoint indices used by the track builder.
const kLeftWrist = 9;
const kRightWrist = 10;

class Keypoint {
  final double x;
  final double y;
  final double confidence;

  const Keypoint(this.x, this.y, this.confidence);
}

/// One detected person: bounding box, box confidence, 17 COCO keypoints.
class PoseDetection {
  final double x1, y1, x2, y2;
  final double confidence;
  final List<Keypoint> keypoints;

  const PoseDetection({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    required this.confidence,
    required this.keypoints,
  });

  double get boxArea => (x2 - x1) * (y2 - y1);
}

abstract interface class InferenceBackend {
  Future<void> load();

  /// Run pose estimation on one frame; one entry per detected person.
  Future<List<PoseDetection>> infer(VideoFrame frame);

  Future<void> dispose();
}
