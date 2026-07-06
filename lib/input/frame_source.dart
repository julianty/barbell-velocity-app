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
  Future<VideoInfo> open();

  /// Decoded frames in presentation order.
  Stream<VideoFrame> frames();

  Future<void> dispose();
}
