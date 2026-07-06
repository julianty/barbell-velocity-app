/// Platform-agnostic video frame extraction seam.
///
/// Implementations: web (video element -> canvas) and iOS (native
/// extraction). Both must report the *true* frame rate / per-frame
/// timestamps — velocity math depends on it.
library;

import 'dart:typed_data';

/// A decoded video frame in RGBA order.
class VideoFrame {
  final int index;
  final double timestampS;
  final int width;
  final int height;
  final Uint8List rgba;

  const VideoFrame({
    required this.index,
    required this.timestampS,
    required this.width,
    required this.height,
    required this.rgba,
  });
}

/// Metadata known once the video container is opened.
class VideoInfo {
  final double fps;
  final double durationS;
  final int width;
  final int height;

  const VideoInfo({
    required this.fps,
    required this.durationS,
    required this.width,
    required this.height,
  });
}

abstract interface class FrameSource {
  /// Open the picked video and read its metadata.
  ///
  /// On web, [VideoInfo.fps] is NaN — browsers do not expose the frame rate
  /// up front; compute it from the extracted frames with [estimateFps].
  Future<VideoInfo> open();

  /// Decoded frames in presentation order.
  Stream<VideoFrame> frames();

  Future<void> dispose();
}

/// Frame rate from per-frame timestamps: 1 / median inter-frame interval.
/// The median makes it robust to occasional dropped/duplicated frames.
double estimateFps(List<double> timestampsS) {
  if (timestampsS.length < 2) return double.nan;
  final dts = <double>[
    for (var i = 1; i < timestampsS.length; i++)
      timestampsS[i] - timestampsS[i - 1]
  ]..sort();
  final n = dts.length;
  final medianDt =
      n.isOdd ? dts[n ~/ 2] : (dts[n ~/ 2 - 1] + dts[n ~/ 2]) / 2.0;
  return medianDt > 0 ? 1.0 / medianDt : double.nan;
}
