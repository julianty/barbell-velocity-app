/// Preview-frame capture for the lift player: while frames stream through
/// the pipeline, a time-spaced, downscaled copy of some of them is kept so
/// the results screen can replay the lift in sync with the charts. Raw RGBA
/// is retained (converted to images lazily by the UI); nearest-neighbor
/// downscaling keeps the cost per kept frame trivial.
library;

import 'dart:typed_data';

import '../input/frame_source.dart';

/// A retained, downscaled RGBA frame for playback.
class PreviewFrame {
  final double timestampS;
  final int width;
  final int height;
  final Uint8List rgba;

  const PreviewFrame({
    required this.timestampS,
    required this.width,
    required this.height,
    required this.rgba,
  });
}

/// Collects preview frames at ~[targetFps], downscaled to [maxHeight], and
/// capped at [maxFrames] (memory bound: 240 frames at 426x240 RGBA ~ 98 MB
/// would be too much; the defaults keep it a few tens of MB).
class PreviewCollector {
  final double targetFps;
  final int maxHeight;
  final int maxFrames;

  final List<PreviewFrame> _frames = [];
  double? _lastKeptS;

  PreviewCollector({
    this.targetFps = 10,
    this.maxHeight = 240,
    this.maxFrames = 300,
  });

  void add(VideoFrame frame) {
    if (_frames.length >= maxFrames) return;
    final last = _lastKeptS;
    if (last != null && frame.timestampS - last < 1 / targetFps) return;
    _lastKeptS = frame.timestampS;
    _frames.add(downscaleFrame(frame, maxHeight: maxHeight));
  }

  List<PreviewFrame> get frames => List.unmodifiable(_frames);
}

/// Nearest-neighbor downscale of an RGBA frame to at most [maxHeight] rows
/// (integer output size, aspect preserved). Frames already small enough are
/// copied as-is.
PreviewFrame downscaleFrame(VideoFrame frame, {required int maxHeight}) {
  if (frame.height <= maxHeight) {
    return PreviewFrame(
      timestampS: frame.timestampS,
      width: frame.width,
      height: frame.height,
      rgba: Uint8List.fromList(frame.rgba),
    );
  }
  final scale = maxHeight / frame.height;
  final outW = (frame.width * scale).round().clamp(1, frame.width);
  final outH = maxHeight;
  final out = Uint8List(outW * outH * 4);
  for (var y = 0; y < outH; y++) {
    final srcY = (y / scale).floor().clamp(0, frame.height - 1);
    final srcRow = srcY * frame.width;
    final outRow = y * outW;
    for (var x = 0; x < outW; x++) {
      final srcI = (srcRow + (x / scale).floor().clamp(0, frame.width - 1)) * 4;
      final outI = (outRow + x) * 4;
      out[outI] = frame.rgba[srcI];
      out[outI + 1] = frame.rgba[srcI + 1];
      out[outI + 2] = frame.rgba[srcI + 2];
      out[outI + 3] = frame.rgba[srcI + 3];
    }
  }
  return PreviewFrame(
      timestampS: frame.timestampS, width: outW, height: outH, rgba: out);
}
