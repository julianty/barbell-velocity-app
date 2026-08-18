/// Results screen body, mirroring the reference pelt_concentric.png layout
/// for the analysis charts: vertical-position and vertical-velocity panels
/// (raw + smoothed, shaded concentric phases). The player's playback time
/// drives a sweeping cursor line across both charts.
///
/// Layout is phone-first: below ~700pt width everything stacks in a single
/// scrollable column (hero stat -> video -> stat chips -> rep cards ->
/// charts). At/above ~700pt (tablet/desktop/landscape) the video sits beside
/// the summary in a row, closer to the original desktop-first design.
/// Charts are shown even when no rep qualified — like the reference plots,
/// they're the main debugging aid for such videos.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../analysis/models.dart';
import '../pipeline/preview.dart';
import '../pipeline/video_pipeline.dart';
import 'lift_player.dart';
import 'velocity_chart.dart';
import 'viz_palette.dart';

/// Width at/above which the tablet/desktop side-by-side layout kicks in.
const double _wideBreakpoint = 700;

class ResultsView extends StatefulWidget {
  final PipelineOutput output;

  const ResultsView({super.key, required this.output});

  @override
  State<ResultsView> createState() => _ResultsViewState();
}

class _ResultsViewState extends State<ResultsView> {
  final ValueNotifier<double> _cursorTime = ValueNotifier(0);

  @override
  void dispose() {
    _cursorTime.dispose();
    super.dispose();
  }

  /// The headline number: best per-rep average velocity, prominent and
  /// unmissable rather than buried in a sentence.
  Widget _hero(BuildContext context) {
    final analysis = widget.output.analysis;
    final theme = Theme.of(context);
    final viz = VizPalette.of(context);
    final reps = analysis.reps;

    if (!analysis.hasReps) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('No reps detected', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 4),
          Text(
            'The bar was tracked (charts below), but no concentric phase '
            'qualified as a rep.',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: viz.textSecondary),
          ),
        ],
      );
    }

    final bestAvgRep = reps.reduce((a, b) => a.avgVelPxS > b.avgVelPxS ? a : b);
    final bestPeakRep = reps.reduce((a, b) => a.maxVelPxS > b.maxVelPxS ? a : b);

    Widget stat(String label, double valuePxS, int repIndex) => Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label,
                style: theme.textTheme.labelLarge
                    ?.copyWith(color: viz.textSecondary)),
            const SizedBox(height: 2),
            Text(
              valuePxS.toStringAsFixed(0),
              style: theme.textTheme.headlineMedium?.copyWith(
                color: theme.colorScheme.primary,
                fontWeight: FontWeight.bold,
              ),
            ),
            Text('px/s · rep #${repIndex + 1}',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: viz.textSecondary)),
          ],
        );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
            child: stat('Best avg velocity', bestAvgRep.avgVelPxS,
                bestAvgRep.repIndex)),
        const SizedBox(width: 16),
        Expanded(
            child: stat('Best peak velocity', bestPeakRep.maxVelPxS,
                bestPeakRep.repIndex)),
      ],
    );
  }

  /// Compact chips: rep count, clip duration, effective fps.
  Widget _statChips(BuildContext context) {
    final analysis = widget.output.analysis;
    final theme = Theme.of(context);
    final viz = VizPalette.of(context);
    final reps = analysis.reps;
    final durationS =
        analysis.fps > 0 ? analysis.rawPositions.length / analysis.fps : 0.0;

    Widget chip(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: viz.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: viz.gridline),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(value, style: theme.textTheme.titleMedium),
                Text(label,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: viz.textSecondary)),
              ],
            ),
          ),
        );

    return Row(
      children: [
        chip('Reps', '${reps.length}'),
        const SizedBox(width: 8),
        chip('Duration', '${durationS.toStringAsFixed(1)} s'),
        const SizedBox(width: 8),
        chip('FPS', analysis.fps.toStringAsFixed(1)),
      ],
    );
  }

  Widget _phasesCaption(BuildContext context) {
    final theme = Theme.of(context);
    final viz = VizPalette.of(context);
    return Text('Shaded ranges are detected concentric phases',
        style: theme.textTheme.bodySmall?.copyWith(color: viz.textSecondary));
  }

  /// Rep results as stacked cards (touch-friendly, replaces the old
  /// horizontally-scrolling DataTable).
  Widget _repCards(BuildContext context) {
    final analysis = widget.output.analysis;
    final theme = Theme.of(context);
    final viz = VizPalette.of(context);

    Widget card(RepResult rep) => Container(
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: viz.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: viz.gridline),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 16,
                backgroundColor:
                    theme.colorScheme.primary.withValues(alpha: 0.15),
                child: Text(
                  '${rep.repIndex + 1}',
                  style: TextStyle(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${rep.avgVelPxS.toStringAsFixed(0)} px/s avg · '
                      '${rep.maxVelPxS.toStringAsFixed(0)} px/s peak',
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'start ${(rep.startFrame / analysis.fps).toStringAsFixed(2)} s'
                      ' · ${rep.durationS.toStringAsFixed(2)} s dur'
                      ' · ${rep.displacementPx.toStringAsFixed(0)} px ROM',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: viz.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [for (final rep in analysis.reps) card(rep)],
    );
  }

  Widget _charts(
      BuildContext context, List<PreviewFrame> preview, double chartHeight) {
    final analysis = widget.output.analysis;
    return ValueListenableBuilder<double>(
      valueListenable: _cursorTime,
      builder: (context, t, _) {
        // Playback time -> chart x through the real frame timestamps: web
        // frame sampling is uneven, so index/fps (chart x) drifts from
        // wall-clock time.
        final chartT =
            preview.isEmpty ? null : widget.output.chartTimeForPlaybackTime(t);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PositionChart(
                analysis: analysis, cursorTime: chartT, height: chartHeight),
            const SizedBox(height: 20),
            VelocityChart(
                analysis: analysis, cursorTime: chartT, height: chartHeight),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.output.analysis;
    final preview = widget.output.preview;
    final screenHeight = MediaQuery.of(context).size.height;
    final chartHeight = math.min(280.0, screenHeight * 0.32);

    final videoPlayer = preview.isEmpty
        ? null
        : LiftPlayer(frames: preview, cursorTime: _cursorTime);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;

        if (!isWide) {
          // Phone-first: a single scrollable column, no forced side-by-side
          // row that can overflow narrow screens.
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _hero(context),
              const SizedBox(height: 16),
              if (videoPlayer != null) ...[
                videoPlayer,
                const SizedBox(height: 16),
              ],
              _charts(context, preview, chartHeight),
              const SizedBox(height: 16),
              _statChips(context),
              const SizedBox(height: 16),
              if (analysis.hasReps) _repCards(context),
              const SizedBox(height: 8),
              _phasesCaption(context),
            ],
          );
        }

        // Tablet/desktop: video beside the summary, close to the original
        // side-by-side treatment, but the video column now sizes by its own
        // aspect ratio (via LiftPlayer) instead of assuming a fixed height.
        return Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (videoPlayer != null) ...[
                      SizedBox(width: 360, child: videoPlayer),
                      const SizedBox(width: 20),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _hero(context),
                          const SizedBox(height: 16),
                          _statChips(context),
                          const SizedBox(height: 16),
                          if (analysis.hasReps) _repCards(context),
                          const SizedBox(height: 8),
                          _phasesCaption(context),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _charts(context, preview, chartHeight),
              ],
            ),
          ),
        );
      },
    );
  }
}
