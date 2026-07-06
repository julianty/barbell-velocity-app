/// Web FrameSource: plays the picked video in a hidden `<video>` element and
/// captures every presented frame via `requestVideoFrameCallback` into a
/// canvas, yielding RGBA bytes plus the frame's `mediaTime` timestamp.
///
/// Browsers do not expose the container frame rate, so [open] reports
/// fps = NaN; compute it afterwards with [estimateFps] over the frame
/// timestamps. Extraction runs at playback speed (a future optimization is
/// WebCodecs for faster-than-realtime decode).
library;

import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'frame_source.dart';
import 'video_picker.dart';

FrameSource createFrameSourceImpl(PickedVideo video) {
  final bytes = video.bytes;
  if (bytes == null) {
    throw ArgumentError('Web FrameSource needs the picked file bytes');
  }
  return WebFrameSource(bytes: bytes, mimeType: video.mimeType);
}

/// WICG `requestVideoFrameCallback` metadata (the callback's second
/// argument; package:web types the method but not this object's fields).
extension type _VideoFrameCallbackMetadata._(JSObject _) implements JSObject {
  external double get mediaTime;
}

class WebFrameSource implements FrameSource {
  final Uint8List bytes;
  final String mimeType;

  web.HTMLVideoElement? _video;
  web.HTMLCanvasElement? _canvas;
  web.CanvasRenderingContext2D? _ctx;
  String? _objectUrl;

  WebFrameSource({required this.bytes, required this.mimeType});

  Future<void> _once(web.EventTarget target, String type,
      {String? errorType}) {
    final completer = Completer<void>();
    late final JSFunction onEvent;
    late final JSFunction onError;
    void cleanup() {
      target.removeEventListener(type, onEvent);
      if (errorType != null) target.removeEventListener(errorType, onError);
    }

    onEvent = ((web.Event _) {
      cleanup();
      if (!completer.isCompleted) completer.complete();
    }).toJS;
    onError = ((web.Event _) {
      cleanup();
      if (!completer.isCompleted) {
        completer.completeError(StateError('Video element fired $errorType'));
      }
    }).toJS;
    target.addEventListener(type, onEvent);
    if (errorType != null) target.addEventListener(errorType, onError);
    return completer.future;
  }

  @override
  Future<VideoInfo> open() async {
    final blob = web.Blob(
      [bytes.toJS].toJS,
      web.BlobPropertyBag(type: mimeType),
    );
    _objectUrl = web.URL.createObjectURL(blob);

    final video = web.HTMLVideoElement()
      ..muted = true
      ..preload = 'auto'
      ..src = _objectUrl!;
    video.setAttribute('playsinline', 'true');
    _video = video;

    await _once(video, 'loadedmetadata', errorType: 'error');

    final canvas = web.HTMLCanvasElement()
      ..width = video.videoWidth
      ..height = video.videoHeight;
    _canvas = canvas;
    _ctx = canvas.getContext('2d', {'willReadFrequently': true}.jsify())
        as web.CanvasRenderingContext2D;

    return VideoInfo(
      fps: double.nan, // unknown until frames are extracted; see estimateFps
      durationS: video.duration,
      width: video.videoWidth,
      height: video.videoHeight,
    );
  }

  @override
  Stream<VideoFrame> frames() {
    final video = _video;
    final ctx = _ctx;
    final canvas = _canvas;
    if (video == null || ctx == null || canvas == null) {
      throw StateError('open() must complete before frames()');
    }

    final controller = StreamController<VideoFrame>();
    var index = 0;
    var done = false;

    void finish() {
      if (!done) {
        done = true;
        controller.close();
      }
    }

    late final JSFunction onFrame;
    onFrame = ((JSAny now, _VideoFrameCallbackMetadata metadata) {
      if (done) return;
      ctx.drawImage(video, 0, 0);
      final data =
          ctx.getImageData(0, 0, canvas.width, canvas.height).data.toDart;
      controller.add(VideoFrame(
        index: index++,
        timestampS: metadata.mediaTime,
        width: canvas.width,
        height: canvas.height,
        rgba: Uint8List.view(
            data.buffer, data.offsetInBytes, data.lengthInBytes),
      ));
      video.requestVideoFrameCallback(onFrame);
    }).toJS;

    video.addEventListener(
        'ended',
        ((web.Event _) {
          finish();
        }).toJS);
    video.addEventListener(
        'error',
        ((web.Event _) {
          if (!done) {
            done = true;
            controller.addError(StateError('Video decode error'));
            controller.close();
          }
        }).toJS);

    controller.onListen = () {
      video.currentTime = 0;
      video.requestVideoFrameCallback(onFrame);
      video.play().toDart.catchError((Object e) {
        if (!done) {
          done = true;
          controller.addError(e);
          controller.close();
        }
        return null;
      });
    };
    controller.onCancel = () {
      done = true;
      video.pause();
    };

    return controller.stream;
  }

  @override
  Future<void> dispose() async {
    _video?.pause();
    _video?.removeAttribute('src');
    _video = null;
    _canvas = null;
    _ctx = null;
    final url = _objectUrl;
    if (url != null) {
      web.URL.revokeObjectURL(url);
      _objectUrl = null;
    }
  }
}
