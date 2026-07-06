/// Pure-Dart YOLOv8-pose pre/post-processing for the web ONNX backend.
///
/// The bundled `yolov8s-pose.onnx` (imgsz 640, no NMS) takes a
/// (1, 3, 640, 640) float tensor (RGB, 0..1, letterboxed) and returns
/// (1, 56, 8400): [cx, cy, w, h, conf, 17 x (x, y, conf)] per anchor, all in
/// 640-space. This module replicates the ultralytics postprocess the Python
/// reference relied on: confidence threshold 0.25, IoU NMS 0.7, letterbox
/// math from ultralytics LetterBox / scale_boxes (114-gray padding, centered,
/// `round(pad - 0.1)` top-left rounding).
library;

import 'dart:math' as math;
import 'dart:typed_data';

import '../input/frame_source.dart';
import 'inference_backend.dart';

const kYoloInputSize = 640;
const kYoloConfThreshold = 0.25;
const kYoloIouThreshold = 0.7;
const kYoloNumKeypoints = 17;

/// How a source frame was fitted into the square model input.
class LetterboxParams {
  final int srcWidth;
  final int srcHeight;
  final int inputSize;

  /// min(inputSize / srcWidth, inputSize / srcHeight); never upscales past
  /// need — matches ultralytics LetterBox(scaleup=true) used at predict time.
  final double scale;

  /// Top-left padding in input pixels (ultralytics rounds `pad - 0.1`).
  final int padLeft;
  final int padTop;

  LetterboxParams({
    required this.srcWidth,
    required this.srcHeight,
    this.inputSize = kYoloInputSize,
  })  : scale = math.min(inputSize / srcWidth, inputSize / srcHeight),
        padLeft = _pad(inputSize, srcWidth, srcHeight, srcWidth),
        padTop = _pad(inputSize, srcWidth, srcHeight, srcHeight);

  static int _pad(int inputSize, int w, int h, int dim) {
    final scale = math.min(inputSize / w, inputSize / h);
    final unpadded = (dim * scale).round();
    return ((inputSize - unpadded) / 2 - 0.1).round();
  }

  int get scaledWidth => (srcWidth * scale).round();
  int get scaledHeight => (srcHeight * scale).round();
}

/// Letterbox-resizes an RGBA frame into a (1, 3, size, size) NCHW float
/// tensor (RGB, 0..1), bilinear, 114-gray padding.
(Float32List, LetterboxParams) preprocessLetterbox(VideoFrame frame,
    {int inputSize = kYoloInputSize}) {
  final params = LetterboxParams(
      srcWidth: frame.width, srcHeight: frame.height, inputSize: inputSize);
  final plane = inputSize * inputSize;
  final tensor = Float32List(3 * plane)..fillRange(0, 3 * plane, 114 / 255.0);

  final sw = params.scaledWidth, sh = params.scaledHeight;
  final rgba = frame.rgba;
  for (var y = 0; y < sh; y++) {
    // Bilinear sample position in source space (pixel-center aligned).
    final srcY = (y + 0.5) / params.scale - 0.5;
    final y0 = srcY.floor().clamp(0, frame.height - 1);
    final y1 = (y0 + 1).clamp(0, frame.height - 1);
    final fy = (srcY - srcY.floorToDouble()).clamp(0.0, 1.0);
    final outRow = (y + params.padTop) * inputSize;
    for (var x = 0; x < sw; x++) {
      final srcX = (x + 0.5) / params.scale - 0.5;
      final x0 = srcX.floor().clamp(0, frame.width - 1);
      final x1 = (x0 + 1).clamp(0, frame.width - 1);
      final fx = (srcX - srcX.floorToDouble()).clamp(0.0, 1.0);

      final i00 = (y0 * frame.width + x0) * 4;
      final i01 = (y0 * frame.width + x1) * 4;
      final i10 = (y1 * frame.width + x0) * 4;
      final i11 = (y1 * frame.width + x1) * 4;
      final out = outRow + x + params.padLeft;
      for (var c = 0; c < 3; c++) {
        final top = rgba[i00 + c] * (1 - fx) + rgba[i01 + c] * fx;
        final bottom = rgba[i10 + c] * (1 - fx) + rgba[i11 + c] * fx;
        tensor[c * plane + out] = (top * (1 - fy) + bottom * fy) / 255.0;
      }
    }
  }
  return (tensor, params);
}

/// Decodes the raw (1, 56, numAnchors) output into candidate detections in
/// model-input (640) space, keeping anchors with conf >= [confThreshold].
List<PoseDetection> decodePoseOutput(
  Float32List output, {
  int numAnchors = 8400,
  double confThreshold = kYoloConfThreshold,
}) {
  final detections = <PoseDetection>[];
  for (var a = 0; a < numAnchors; a++) {
    final conf = output[4 * numAnchors + a];
    if (conf < confThreshold) continue;
    final cx = output[a];
    final cy = output[numAnchors + a];
    final w = output[2 * numAnchors + a];
    final h = output[3 * numAnchors + a];
    final keypoints = List<Keypoint>.generate(kYoloNumKeypoints, (k) {
      final base = (5 + 3 * k) * numAnchors + a;
      return Keypoint(output[base], output[base + numAnchors],
          output[base + 2 * numAnchors]);
    });
    detections.add(PoseDetection(
      x1: cx - w / 2,
      y1: cy - h / 2,
      x2: cx + w / 2,
      y2: cy + h / 2,
      confidence: conf,
      keypoints: keypoints,
    ));
  }
  return detections;
}

double _iou(PoseDetection a, PoseDetection b) {
  final ix = math.max(
      0.0, math.min(a.x2, b.x2) - math.max(a.x1, b.x1));
  final iy = math.max(
      0.0, math.min(a.y2, b.y2) - math.max(a.y1, b.y1));
  final inter = ix * iy;
  final union = a.boxArea + b.boxArea - inter;
  return union <= 0 ? 0.0 : inter / union;
}

/// Greedy IoU non-max suppression, highest confidence first (single class).
List<PoseDetection> nms(List<PoseDetection> detections,
    {double iouThreshold = kYoloIouThreshold}) {
  final sorted = List<PoseDetection>.of(detections)
    ..sort((a, b) => b.confidence.compareTo(a.confidence));
  final kept = <PoseDetection>[];
  for (final det in sorted) {
    if (kept.every((k) => _iou(k, det) <= iouThreshold)) kept.add(det);
  }
  return kept;
}

/// Maps detections from model-input space back to source-frame pixels
/// (subtract padding, divide by scale, clip) — ultralytics scale_boxes.
List<PoseDetection> scaleToOriginal(
    List<PoseDetection> detections, LetterboxParams params) {
  double mapX(double x) =>
      ((x - params.padLeft) / params.scale).clamp(0.0, params.srcWidth - 1.0);
  double mapY(double y) =>
      ((y - params.padTop) / params.scale).clamp(0.0, params.srcHeight - 1.0);

  return [
    for (final d in detections)
      PoseDetection(
        x1: mapX(d.x1),
        y1: mapY(d.y1),
        x2: mapX(d.x2),
        y2: mapY(d.y2),
        confidence: d.confidence,
        keypoints: [
          for (final k in d.keypoints) Keypoint(mapX(k.x), mapY(k.y), k.confidence),
        ],
      ),
  ];
}

/// Full postprocess: decode -> NMS -> map back to source-frame pixels.
List<PoseDetection> postprocessPose(
  Float32List output,
  LetterboxParams params, {
  int numAnchors = 8400,
  double confThreshold = kYoloConfThreshold,
  double iouThreshold = kYoloIouThreshold,
}) {
  final candidates = decodePoseOutput(output,
      numAnchors: numAnchors, confThreshold: confThreshold);
  return scaleToOriginal(nms(candidates, iouThreshold: iouThreshold), params);
}
