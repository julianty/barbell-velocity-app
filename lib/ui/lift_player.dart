/// Animated replay of the lift from the pipeline's preview frames (~10 fps),
/// with play/pause and a scrub slider. Publishes the current playback time
/// through a [ValueNotifier] so the charts can draw a synced sweeping cursor.
library;

import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../pipeline/preview.dart';
import 'viz_palette.dart';

class LiftPlayer extends StatefulWidget {
  final List<PreviewFrame> frames;

  /// Owned by the parent; this widget writes the playback time into it.
  final ValueNotifier<double> cursorTime;

  const LiftPlayer({super.key, required this.frames, required this.cursorTime});

  @override
  State<LiftPlayer> createState() => _LiftPlayerState();
}

class _LiftPlayerState extends State<LiftPlayer> {
  static const _tick = Duration(milliseconds: 50);

  late final List<ui.Image?> _images;
  final Set<int> _decoding = {};
  Timer? _timer;
  bool _playing = true;

  double get _endS =>
      widget.frames.isEmpty ? 0 : widget.frames.last.timestampS;

  @override
  void initState() {
    super.initState();
    _images = List<ui.Image?>.filled(widget.frames.length, null);
    _timer = Timer.periodic(_tick, _onTick);
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final img in _images) {
      img?.dispose();
    }
    super.dispose();
  }

  void _onTick(Timer _) {
    if (!_playing || widget.frames.isEmpty) return;
    var t = widget.cursorTime.value + _tick.inMilliseconds / 1000.0;
    if (t > _endS) t = 0; // loop
    widget.cursorTime.value = t;
    setState(() {});
  }

  /// Index of the last frame at or before time [t].
  int _frameIndexAt(double t) {
    var lo = 0, hi = widget.frames.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) ~/ 2;
      if (widget.frames[mid].timestampS <= t) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  void _ensureDecoded(int index) {
    if (_images[index] != null || _decoding.contains(index)) return;
    _decoding.add(index);
    final f = widget.frames[index];
    ui.decodeImageFromPixels(f.rgba, f.width, f.height,
        ui.PixelFormat.rgba8888, (img) {
      if (!mounted) {
        img.dispose();
        return;
      }
      setState(() => _images[index] = img);
    });
  }

  @override
  Widget build(BuildContext context) {
    final viz = VizPalette.of(context);
    if (widget.frames.isEmpty) return const SizedBox.shrink();

    final t = widget.cursorTime.value.clamp(0.0, _endS);
    final index = _frameIndexAt(t);
    _ensureDecoded(index);
    if (index + 1 < widget.frames.length) _ensureDecoded(index + 1);
    final image = _images[index];

    // Real aspect ratio of the preview frames: sized by AspectRatio rather
    // than a fixed height, so portrait lift videos aren't letterboxed inside
    // a landscape-shaped box.
    final first = widget.frames.first;
    final aspectRatio = (first.width > 0 && first.height > 0)
        ? first.width / first.height
        : 16 / 9;

    // Cap the rendered height so a portrait (e.g. 9:16) video can't grow
    // tall enough to push the play/scrub controls off-screen.
    final maxPreviewHeight = MediaQuery.of(context).size.height * 0.45;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxPreviewHeight),
            child: AspectRatio(
              aspectRatio: aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: ColoredBox(
                  color: viz.surface,
                  child: image == null
                      ? const Center(
                          child: SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(strokeWidth: 2)))
                      : RawImage(image: image, fit: BoxFit.contain),
                ),
              ),
            ),
          ),
        ),
        Row(
          children: [
            IconButton(
              tooltip: _playing ? 'Pause' : 'Play',
              icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
              onPressed: () => setState(() => _playing = !_playing),
            ),
            Expanded(
              child: Slider(
                value: t,
                max: _endS,
                onChanged: (v) {
                  widget.cursorTime.value = v;
                  setState(() {});
                },
              ),
            ),
            Text(
              '${t.toStringAsFixed(1)} s',
              style: TextStyle(
                  color: viz.textSecondary,
                  fontSize: 12,
                  fontFeatures: const [ui.FontFeature.tabularFigures()]),
            ),
            const SizedBox(width: 8),
          ],
        ),
      ],
    );
  }
}
