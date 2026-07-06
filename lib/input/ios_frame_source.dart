/// iOS FrameSource: talks to the native AVAssetReader-based extractor in
/// `ios/Runner/FrameExtractor.swift` over platform channels. Frames arrive
/// as RGBA byte maps on an EventChannel.
///
/// NOTE: written on Windows; must be verified on a Mac (see PROGRESS.md).
library;

import 'package:flutter/services.dart';

import 'frame_source.dart';
import 'video_picker.dart';

FrameSource createFrameSourceImpl(PickedVideo video) {
  final path = video.path;
  if (path == null) {
    throw ArgumentError('iOS FrameSource needs a file path');
  }
  return IosFrameSource(path: path);
}

class IosFrameSource implements FrameSource {
  static const _method = MethodChannel('barbell_velocity/frame_extractor');
  static const _events = EventChannel('barbell_velocity/frame_stream');

  final String path;

  IosFrameSource({required this.path});

  @override
  Future<VideoInfo> open() async {
    final info = await _method.invokeMapMethod<String, dynamic>(
        'open', <String, dynamic>{'path': path});
    if (info == null) {
      throw StateError('FrameExtractor.open returned null');
    }
    return VideoInfo(
      fps: (info['fps'] as num).toDouble(),
      durationS: (info['durationS'] as num).toDouble(),
      width: (info['width'] as num).toInt(),
      height: (info['height'] as num).toInt(),
    );
  }

  @override
  Stream<VideoFrame> frames() {
    return _events
        .receiveBroadcastStream(<String, dynamic>{'path': path}).map((event) {
      final m = (event as Map).cast<String, dynamic>();
      return VideoFrame(
        index: (m['index'] as num).toInt(),
        timestampS: (m['timestampS'] as num).toDouble(),
        width: (m['width'] as num).toInt(),
        height: (m['height'] as num).toInt(),
        rgba: m['rgba'] as Uint8List,
      );
    });
  }

  @override
  Future<void> dispose() async {
    await _method.invokeMethod<void>('close');
  }
}
