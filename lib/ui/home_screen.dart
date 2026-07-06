/// App entry screen and state machine: pick a video -> processing (with
/// progress) -> results, with distinct error states for unreadable videos
/// and lifts where no person was detected.
library;

import 'package:flutter/material.dart';

import '../input/video_picker.dart';
import '../pipeline/video_pipeline.dart';
import 'results_view.dart';

class HomeScreen extends StatefulWidget {
  /// Injectable for tests; defaults to the real platform pipeline/picker.
  final VideoPipeline? pipeline;
  final Future<PickedVideo?> Function() picker;

  const HomeScreen({super.key, this.pipeline, this.picker = pickVideo});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

sealed class _ScreenState {}

class _Idle extends _ScreenState {}

class _Processing extends _ScreenState {
  final String videoName;
  final PipelineProgress? progress;
  _Processing(this.videoName, [this.progress]);
}

class _Failed extends _ScreenState {
  final String message;
  _Failed(this.message);
}

class _Done extends _ScreenState {
  final PipelineOutput output;
  _Done(this.output);
}

class _HomeScreenState extends State<HomeScreen> {
  _ScreenState _state = _Idle();

  Future<void> _pickAndRun() async {
    final video = await widget.picker();
    if (video == null || !mounted) return;

    setState(() => _state = _Processing(video.name));
    final pipeline = widget.pipeline ?? VideoPipeline();
    try {
      final output = await pipeline.run(video, onProgress: (p) {
        if (mounted) setState(() => _state = _Processing(video.name, p));
      });
      if (mounted) setState(() => _state = _Done(output));
    } on UnreadableVideoException catch (e) {
      if (mounted) setState(() => _state = _Failed(e.message));
    } on NoBarbellException catch (e) {
      if (mounted) setState(() => _state = _Failed(e.message));
    } catch (e) {
      if (mounted) setState(() => _state = _Failed('Analysis failed: $e'));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Barbell Velocity'),
        actions: [
          if (_state is _Done || _state is _Failed)
            IconButton(
              tooltip: 'Analyze another video',
              icon: const Icon(Icons.refresh),
              onPressed: () => setState(() => _state = _Idle()),
            ),
        ],
      ),
      body: switch (_state) {
        _Idle() => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Analyze a lift video',
                    style: theme.textTheme.headlineSmall),
                const SizedBox(height: 8),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    'Pick a video of a barbell lift. Pose detection tracks '
                    'the bar via the lifter\'s wrists and reports per-rep '
                    'velocity.',
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _pickAndRun,
                  icon: const Icon(Icons.video_file),
                  label: const Text('Pick a video'),
                ),
              ],
            ),
          ),
        _Processing(:final videoName, :final progress) => Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 240,
                  child: LinearProgressIndicator(value: progress?.fraction),
                ),
                const SizedBox(height: 16),
                Text('Analyzing $videoName…',
                    style: theme.textTheme.titleMedium),
                if (progress != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    '${progress.framesProcessed} frames · '
                    '${progress.framesWithDetection} with a lifter',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
            ),
          ),
        _Failed(:final message) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 48),
                  const SizedBox(height: 12),
                  Text(message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: _pickAndRun,
                    child: const Text('Try another video'),
                  ),
                ],
              ),
            ),
          ),
        _Done(:final output) => ResultsView(output: output),
      },
    );
  }
}
