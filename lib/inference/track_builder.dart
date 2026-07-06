/// Barbell-track construction from per-frame pose detections, ported from
/// the reference `yolo_pose/build_barbell_track.py`.
///
/// Person selection per frame: a single detection is taken as-is; with a
/// previous center, the person whose wrist midpoint is closest wins; else
/// the largest bounding box; else the first. The center is the mean of the
/// left/right wrist keypoints. Keypoint confidence is deliberately ignored
/// (reference behavior).
library;

import '../analysis/models.dart';
import 'inference_backend.dart';

int _selectByLargestBbox(List<PoseDetection> detections) {
  var best = 0;
  var bestArea = -double.infinity;
  for (var i = 0; i < detections.length; i++) {
    final area = detections[i].boxArea;
    if (area > bestArea) {
      bestArea = area;
      best = i;
    }
  }
  return best;
}

int _selectByWristProximity(
    List<PoseDetection> detections, List<double> lastCenter) {
  var best = 0;
  var bestDist = double.infinity;
  for (var i = 0; i < detections.length; i++) {
    final kp = detections[i].keypoints;
    if (kp.length <= kRightWrist) continue;
    final wx = (kp[kLeftWrist].x + kp[kRightWrist].x) / 2;
    final wy = (kp[kLeftWrist].y + kp[kRightWrist].y) / 2;
    final dx = wx - lastCenter[0], dy = wy - lastCenter[1];
    final d = dx * dx + dy * dy;
    if (d < bestDist) {
      bestDist = d;
      best = i;
    }
  }
  return best;
}

/// `compute_barbell_center`: wrist midpoint of the selected person, or null.
List<double>? computeBarbellCenter(
  List<PoseDetection> detections, {
  List<double>? lastCenter,
}) {
  if (detections.isEmpty) return null;

  int idx;
  if (detections.length == 1) {
    idx = 0;
  } else if (lastCenter != null) {
    idx = _selectByWristProximity(detections, lastCenter);
  } else {
    idx = _selectByLargestBbox(detections);
  }

  final kp = detections[idx].keypoints;
  if (kp.length <= kRightWrist) return null;
  return [
    (kp[kLeftWrist].x + kp[kRightWrist].x) / 2,
    (kp[kLeftWrist].y + kp[kRightWrist].y) / 2,
  ];
}

/// Stateful frame-by-frame builder: feed detections in order, get the track.
class TrackBuilder {
  final List<TrackPoint> _points = [];
  List<double>? _lastCenter;

  void add(String frameName, List<PoseDetection> detections) {
    final center = computeBarbellCenter(detections, lastCenter: _lastCenter);
    if (center != null) _lastCenter = center;
    _points.add(TrackPoint(frame: frameName, center: center));
  }

  List<TrackPoint> get points => List.unmodifiable(_points);

  BarbellTrack build(double fps) => BarbellTrack(points: points, fps: fps);
}
