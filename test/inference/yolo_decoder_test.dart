import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/inference/inference_backend.dart';
import 'package:barbell_velocity_app/inference/yolo_decoder.dart';
import 'package:barbell_velocity_app/input/frame_source.dart';

VideoFrame solidFrame(int width, int height, List<int> rgb) {
  final rgba = Uint8List(width * height * 4);
  for (var i = 0; i < width * height; i++) {
    rgba[i * 4] = rgb[0];
    rgba[i * 4 + 1] = rgb[1];
    rgba[i * 4 + 2] = rgb[2];
    rgba[i * 4 + 3] = 255;
  }
  return VideoFrame(
      index: 0, timestampS: 0, width: width, height: height, rgba: rgba);
}

/// Builds a flat (1, 56, numAnchors) output with the given anchors written
/// as [cx, cy, w, h, conf, kp...]; keypoints default to the box center.
Float32List syntheticOutput(
    int numAnchors, List<(int anchor, List<double> box, double conf)> hits) {
  final out = Float32List(56 * numAnchors);
  for (final (a, box, conf) in hits) {
    out[a] = box[0];
    out[numAnchors + a] = box[1];
    out[2 * numAnchors + a] = box[2];
    out[3 * numAnchors + a] = box[3];
    out[4 * numAnchors + a] = conf;
    for (var k = 0; k < kYoloNumKeypoints; k++) {
      out[(5 + 3 * k) * numAnchors + a] = box[0];
      out[(6 + 3 * k) * numAnchors + a] = box[1];
      out[(7 + 3 * k) * numAnchors + a] = 0.9;
    }
  }
  return out;
}

void main() {
  group('LetterboxParams', () {
    test('landscape video: width fills, height padded and centered', () {
      final p = LetterboxParams(srcWidth: 1920, srcHeight: 1080);
      expect(p.scale, closeTo(640 / 1920, 1e-12));
      expect(p.scaledWidth, 640);
      expect(p.scaledHeight, 360);
      expect(p.padLeft, 0);
      expect(p.padTop, 140); // (640 - 360) / 2
    });

    test('portrait video: height fills, width padded', () {
      final p = LetterboxParams(srcWidth: 1080, srcHeight: 1920);
      expect(p.scaledHeight, 640);
      expect(p.padTop, 0);
      expect(p.padLeft, 140);
    });

    test('square video: no padding, exact fit', () {
      final p = LetterboxParams(srcWidth: 640, srcHeight: 640);
      expect(p.scale, 1.0);
      expect(p.padLeft, 0);
      expect(p.padTop, 0);
    });

    test('ultralytics round(pad - 0.1) rounding on odd pad', () {
      // 640 x 632 scaled -> pad total 8/2 = 4 exactly; use a case with .5:
      // src 640 x 630 -> unpadded 630, pad = 5.0 -> round(4.9) = 5.
      final p = LetterboxParams(srcWidth: 640, srcHeight: 630);
      expect(p.padTop, 5);
      // src 640 x 639 -> pad = 0.5 -> round(0.4) = 0 (floor on the .5 case).
      final q = LetterboxParams(srcWidth: 640, srcHeight: 639);
      expect(q.padTop, 0);
    });
  });

  group('preprocessLetterbox', () {
    test('solid color maps to correct channels; padding is 114-gray', () {
      final frame = solidFrame(64, 32, [255, 128, 0]);
      final (tensor, p) = preprocessLetterbox(frame, inputSize: 64);
      final plane = 64 * 64;
      expect(p.padTop, 16);

      // Center of the image area.
      final mid = (16 + p.padTop) * 64 + 32;
      expect(tensor[mid], closeTo(1.0, 1e-6)); // R
      expect(tensor[plane + mid], closeTo(128 / 255, 1e-6)); // G
      expect(tensor[2 * plane + mid], closeTo(0.0, 1e-6)); // B

      // Padding rows above and below.
      for (final pad in [0, 63 * 64 + 10]) {
        for (var c = 0; c < 3; c++) {
          expect(tensor[c * plane + pad], closeTo(114 / 255, 1e-6));
        }
      }
    });

    test('identity size: pixel values pass through', () {
      final frame = solidFrame(8, 8, [10, 20, 30]);
      final (tensor, p) = preprocessLetterbox(frame, inputSize: 8);
      expect(p.scale, 1.0);
      expect(tensor[0], closeTo(10 / 255, 1e-6));
      expect(tensor[64], closeTo(20 / 255, 1e-6));
      expect(tensor[128], closeTo(30 / 255, 1e-6));
    });
  });

  group('decodePoseOutput', () {
    test('keeps anchors above threshold, decodes cxcywh to xyxy', () {
      final out = syntheticOutput(100, [
        (3, [320.0, 240.0, 100.0, 200.0], 0.9),
        (7, [100.0, 100.0, 50.0, 50.0], 0.1), // below 0.25
      ]);
      final dets = decodePoseOutput(out, numAnchors: 100);
      expect(dets.length, 1);
      final d = dets.single;
      expect(d.x1, closeTo(270, 1e-6));
      expect(d.y1, closeTo(140, 1e-6));
      expect(d.x2, closeTo(370, 1e-6));
      expect(d.y2, closeTo(340, 1e-6));
      expect(d.confidence, closeTo(0.9, 1e-6));
      expect(d.keypoints.length, kYoloNumKeypoints);
      expect(d.keypoints[kLeftWrist].x, closeTo(320, 1e-6));
      expect(d.keypoints[kLeftWrist].confidence, closeTo(0.9, 1e-6));
    });

    test('planar layout: anchor index strides are respected', () {
      // Two anchors both above threshold with distinct values.
      final out = syntheticOutput(10, [
        (0, [10.0, 20.0, 4.0, 4.0], 0.5),
        (9, [30.0, 40.0, 4.0, 4.0], 0.6),
      ]);
      final dets = decodePoseOutput(out, numAnchors: 10);
      expect(dets.length, 2);
      expect(dets[0].x1, closeTo(8, 1e-6));
      expect(dets[1].y1, closeTo(38, 1e-6));
    });
  });

  group('nms', () {
    PoseDetection box(double x1, double y1, double x2, double y2, double conf) =>
        PoseDetection(
            x1: x1, y1: y1, x2: x2, y2: y2, confidence: conf, keypoints: const []);

    test('suppresses heavy overlap, keeps the higher confidence', () {
      final kept = nms([
        box(0, 0, 100, 100, 0.8),
        box(5, 5, 105, 105, 0.9), // IoU ~0.82 with the first
      ]);
      expect(kept.length, 1);
      expect(kept.single.confidence, 0.9);
    });

    test('keeps disjoint and lightly overlapping boxes', () {
      final kept = nms([
        box(0, 0, 100, 100, 0.9),
        box(200, 200, 300, 300, 0.8),
        box(80, 80, 180, 180, 0.7), // IoU ~0.026
      ]);
      expect(kept.length, 3);
    });

    test('iouThreshold=0 keeps only non-touching boxes', () {
      final kept = nms([
        box(0, 0, 100, 100, 0.9),
        box(99, 99, 200, 200, 0.8),
      ], iouThreshold: 0.0);
      expect(kept.length, 1);
    });
  });

  group('scaleToOriginal', () {
    test('inverts the letterbox mapping', () {
      final p = LetterboxParams(srcWidth: 1920, srcHeight: 1080);
      // A point at the center of the 640 input maps to the frame center.
      final det = PoseDetection(
          x1: 320,
          y1: 320,
          x2: 320,
          y2: 320,
          confidence: 1,
          keypoints: const [Keypoint(320, 320, 1)]);
      final mapped = scaleToOriginal([det], p).single;
      expect(mapped.x1, closeTo(960, 1e-6));
      expect(mapped.y1, closeTo((320 - 140) / p.scale, 1e-6)); // 540
      expect(mapped.keypoints.single.y, closeTo(540, 1e-6));
    });

    test('clips to frame bounds', () {
      final p = LetterboxParams(srcWidth: 1920, srcHeight: 1080);
      final det = PoseDetection(
          x1: -50,
          y1: 0, // inside top padding -> negative source y -> clipped to 0
          x2: 700,
          y2: 700,
          confidence: 1,
          keypoints: const []);
      final mapped = scaleToOriginal([det], p).single;
      expect(mapped.x1, 0);
      expect(mapped.y1, 0);
      expect(mapped.x2, 1919);
      expect(mapped.y2, 1079);
    });
  });

  group('postprocessPose', () {
    test('end to end: decode, suppress, map back', () {
      final p = LetterboxParams(srcWidth: 1280, srcHeight: 720);
      final out = syntheticOutput(50, [
        (1, [320.0, 320.0, 100.0, 100.0], 0.9),
        (2, [322.0, 322.0, 100.0, 100.0], 0.6), // duplicate, suppressed
        (5, [100.0, 100.0, 40.0, 40.0], 0.7),
      ]);
      final dets = postprocessPose(out, p, numAnchors: 50);
      expect(dets.length, 2);
      // Sorted by confidence from NMS: 0.9 first.
      expect(dets[0].confidence, closeTo(0.9, 1e-6));
      // Center of input maps to center of frame.
      final cx = (dets[0].x1 + dets[0].x2) / 2;
      expect(cx, closeTo(640, 1e-6));
    });
  });
}
