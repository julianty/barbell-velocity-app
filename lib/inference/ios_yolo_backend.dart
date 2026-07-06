/// iOS InferenceBackend: the `ultralytics_yolo` plugin running the CoreML
/// pose model (yolov8s-pose.mlpackage, exported on a Mac — see PROGRESS.md)
/// on the Neural Engine. The plugin's single-image API takes *encoded* image
/// bytes, so each raw RGBA frame is PNG-encoded via dart:ui (Skia, native)
/// before prediction. Keypoints come back in source-image pixel space as
/// x, y plus per-keypoint confidences — the same shape our track builder
/// expects.
///
/// NOTE: written on Windows; must be verified on a Mac (see PROGRESS.md).
library;

import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:ultralytics_yolo/ultralytics_yolo.dart' as uy;

import '../input/frame_source.dart';
import 'inference_backend.dart';

InferenceBackend createInferenceBackendImpl() => IosYoloBackend();

class IosYoloBackend implements InferenceBackend {
  /// Model name resolved by the plugin from the app bundle
  /// (yolov8s-pose.mlpackage dragged into ios/Runner in Xcode).
  static const modelName = 'yolov8s-pose';

  uy.YOLO? _yolo;

  @override
  Future<void> load() async {
    final yolo = uy.YOLO(modelPath: modelName, task: uy.YOLOTask.pose);
    await yolo.loadModel();
    _yolo = yolo;
  }

  Future<Uint8List> _encodePng(VideoFrame frame) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(frame.rgba);
    final descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: frame.width,
      height: frame.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final codec = await descriptor.instantiateCodec();
    final image = (await codec.getNextFrame()).image;
    try {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('PNG encode failed');
      return png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
    } finally {
      image.dispose();
      codec.dispose();
      descriptor.dispose();
      buffer.dispose();
    }
  }

  @override
  Future<List<PoseDetection>> infer(VideoFrame frame) async {
    final yolo = _yolo;
    if (yolo == null) {
      throw StateError('load() must complete before infer()');
    }

    final png = await _encodePng(frame);
    final results = await yolo.predict(png);
    final detections = (results['detections'] as List?) ?? const [];

    return [
      for (final d in detections)
        _toPoseDetection(
            uy.YOLOResult.fromMap(Map<String, dynamic>.from(d as Map))),
    ];
  }

  PoseDetection _toPoseDetection(uy.YOLOResult r) {
    final kps = r.keypoints ?? const [];
    final confs = r.keypointConfidences ?? const [];
    return PoseDetection(
      x1: r.boundingBox.left,
      y1: r.boundingBox.top,
      x2: r.boundingBox.right,
      y2: r.boundingBox.bottom,
      confidence: r.confidence,
      keypoints: [
        for (var i = 0; i < kps.length; i++)
          Keypoint(kps[i].x, kps[i].y, i < confs.length ? confs[i] : 0.0),
      ],
    );
  }

  @override
  Future<void> dispose() async {
    final yolo = _yolo;
    _yolo = null;
    await yolo?.dispose();
  }
}
