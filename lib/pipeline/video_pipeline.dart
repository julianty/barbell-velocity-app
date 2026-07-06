/// End-to-end orchestration: picked video -> frames -> pose inference ->
/// barbell track -> analysis. Platform pieces are injected so tests can run
/// the whole flow with fakes (see test/pipeline/).
library;

import 'package:flutter/foundation.dart' show compute;

import '../analysis/analysis_config.dart';
import '../analysis/models.dart';
import '../analysis/pipeline.dart';
import '../inference/backend_factory.dart';
import '../inference/inference_backend.dart';
import '../inference/track_builder.dart';
import '../input/frame_source.dart';
import '../input/frame_source_factory.dart';
import '../input/video_picker.dart';
import 'preview.dart';

/// The video could not be opened or produced no usable frames.
class UnreadableVideoException implements Exception {
  final String message;
  UnreadableVideoException(this.message);
  @override
  String toString() => message;
}

/// Frames decoded fine but no person/wrists were ever detected.
class NoBarbellException implements Exception {
  final String message;
  NoBarbellException(this.message);
  @override
  String toString() => message;
}

class PipelineProgress {
  final int framesProcessed;
  final int framesWithDetection;

  /// 0..1 based on frame timestamp vs video duration, or null when the
  /// duration is unknown.
  final double? fraction;

  const PipelineProgress({
    required this.framesProcessed,
    required this.framesWithDetection,
    this.fraction,
  });
}

class PipelineOutput {
  final VideoInfo info;
  final BarbellTrack track;
  final AnalysisResult analysis;

  /// Downscaled ~10 fps frames for the results-screen lift player.
  final List<PreviewFrame> preview;

  const PipelineOutput({
    required this.info,
    required this.track,
    required this.analysis,
    this.preview = const [],
  });
}

AnalysisResult _analyzeEntry((BarbellTrack, AnalysisConfig) args) =>
    analyzeTrack(args.$1, config: args.$2);

class VideoPipeline {
  final FrameSource Function(PickedVideo) frameSourceFactory;
  final InferenceBackend Function() backendFactory;
  final AnalysisConfig config;

  /// Analysis normally runs via [compute] to keep the UI thread free; widget
  /// tests set this to false because real isolates never resolve inside the
  /// fake-async test zone.
  final bool useIsolate;

  VideoPipeline({
    this.frameSourceFactory = createFrameSource,
    this.backendFactory = createInferenceBackend,
    this.config = const AnalysisConfig(),
    this.useIsolate = true,
  });

  Future<PipelineOutput> run(
    PickedVideo video, {
    void Function(PipelineProgress progress)? onProgress,
  }) async {
    final source = frameSourceFactory(video);
    final backend = backendFactory();
    try {
      final VideoInfo info;
      try {
        info = await source.open();
      } catch (e) {
        throw UnreadableVideoException('Could not open "${video.name}": $e');
      }
      await backend.load();

      final builder = TrackBuilder();
      final previewCollector = PreviewCollector();
      final timestamps = <double>[];
      var withDetection = 0;
      try {
        await for (final frame in source.frames()) {
          final detections = await backend.infer(frame);
          builder.add('frame_${frame.index}', detections);
          previewCollector.add(frame);
          timestamps.add(frame.timestampS);
          if (detections.isNotEmpty) withDetection++;
          onProgress?.call(PipelineProgress(
            framesProcessed: timestamps.length,
            framesWithDetection: withDetection,
            fraction: info.durationS > 0
                ? (frame.timestampS / info.durationS).clamp(0.0, 1.0)
                : null,
          ));
        }
      } on UnreadableVideoException {
        rethrow;
      } catch (e) {
        throw UnreadableVideoException('Failed decoding "${video.name}": $e');
      }

      if (timestamps.length < 2) {
        throw UnreadableVideoException(
            'No frames could be decoded from "${video.name}"');
      }

      // Web reports fps = NaN from open(); recover it from the timestamps.
      final fps = info.fps.isFinite && info.fps > 0
          ? info.fps
          : estimateFps(timestamps);
      if (!fps.isFinite || fps <= 0) {
        throw UnreadableVideoException(
            'Could not determine the frame rate of "${video.name}"');
      }

      final track = builder.build(fps);
      if (track.points.every((p) => p.center == null)) {
        throw NoBarbellException(
            'No lifter was detected in "${video.name}" — make sure the '
            'person and their hands are visible.');
      }

      final analysis = useIsolate
          ? await compute(_analyzeEntry, (track, config))
          : analyzeTrack(track, config: config);
      return PipelineOutput(
        info: info,
        track: track,
        analysis: analysis,
        preview: previewCollector.frames,
      );
    } finally {
      await source.dispose();
      await backend.dispose();
    }
  }
}
