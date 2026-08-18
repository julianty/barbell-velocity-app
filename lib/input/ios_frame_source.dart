/// iOS FrameSource: talks to the native AVAssetReader-based extractor in
/// `ios/Runner/FrameExtractor.swift` over platform channels. Frames arrive
/// as RGBA byte maps on an EventChannel.
///
/// NOTE: written on Windows; must be verified on a Mac (see PROGRESS.md).
library;

import 'dart:async';
import 'dart:collection';

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

  static VideoFrame _decode(Object? event) {
    final m = (event! as Map).cast<String, dynamic>();
    return VideoFrame(
      index: (m['index'] as num).toInt(),
      timestampS: (m['timestampS'] as num).toDouble(),
      width: (m['width'] as num).toInt(),
      height: (m['height'] as num).toInt(),
      rgba: m['rgba'] as Uint8List,
    );
  }

  /// Backpressure: the native reader decodes far faster than this pipeline
  /// consumes (PNG encode + CoreML per frame). Pausing a subscription on the
  /// EventChannel's *broadcast* stream does not stop the platform producer —
  /// the engine just queues the undelivered messages, so a 1080p clip can
  /// buffer gigabytes of RGBA and get the app killed for memory pressure.
  ///
  /// So the native side is credit-gated instead (see FrameExtractor.swift):
  /// it only ever has a few unacknowledged frames outstanding, and this
  /// single-subscription wrapper sends `ackFrame` as each frame is handed to
  /// the consumer. When the consumer pauses (which `await for` does while it
  /// awaits the loop body) acks stop, and the reader blocks in turn.
  @override
  Stream<VideoFrame> frames() {
    final controller = StreamController<VideoFrame>();
    final pending = Queue<VideoFrame>();
    StreamSubscription<dynamic>? sub;
    var ended = false;

    void pump() {
      while (pending.isNotEmpty &&
          !controller.isPaused &&
          !controller.isClosed) {
        controller.add(pending.removeFirst());
        unawaited(
          _method
              .invokeMethod<void>('ackFrame')
              // The reader may already be gone (cancel/end); acks are advisory.
              .catchError((Object _) {}),
        );
      }
      if (ended && pending.isEmpty && !controller.isClosed) {
        controller.close();
      }
    }

    controller.onListen = () {
      sub = _events
          .receiveBroadcastStream(<String, dynamic>{'path': path})
          .listen(
            (Object? event) {
              pending.add(_decode(event));
              pump();
            },
            onError: (Object e, StackTrace s) => controller.addError(e, s),
            onDone: () {
              ended = true;
              pump();
            },
          );
    };
    controller.onResume = pump;
    controller.onCancel = () async {
      ended = true;
      pending.clear();
      await sub?.cancel();
    };

    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    await _method.invokeMethod<void>('close');
  }
}
