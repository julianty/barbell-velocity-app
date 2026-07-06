/// Results screen body, mirroring the reference pelt_concentric.png layout:
/// lift replay + summary/table up top, then the vertical-position and
/// vertical-velocity charts (raw + smoothed, shaded concentric phases). The
/// player's playback time drives a sweeping cursor line across both charts.
/// Content is width-constrained so it sits comfortably in a desktop window.
/// Charts are shown even when no rep qualified — like the reference plots,
/// they're the main debugging aid for such videos.
library;

import 'package:flutter/material.dart';

import '../pipeline/video_pipeline.dart';
import 'lift_player.dart';
import 'velocity_chart.dart';
import 'viz_palette.dart';

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

  Widget _summary(BuildContext context) {
    final analysis = widget.output.analysis;
    final theme = Theme.of(context);
    final viz = VizPalette.of(context);
    final reps = analysis.reps;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (analysis.hasReps)
          Text(
            '${reps.length} rep${reps.length == 1 ? '' : 's'} · '
            'best avg ${reps.map((r) => r.avgVelPxS).reduce((a, b) => a > b ? a : b).toStringAsFixed(0)} px/s · '
            '${analysis.fps.toStringAsFixed(1)} fps',
            style: theme.textTheme.titleMedium,
          )
        else ...[
          Text('No reps detected', style: theme.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'The bar was tracked (charts below), but no concentric phase '
            'qualified as a rep.',
            style:
                theme.textTheme.bodyMedium?.copyWith(color: viz.textSecondary),
          ),
        ],
        const SizedBox(height: 4),
        Text('Shaded ranges are detected concentric phases',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: viz.textSecondary)),
        if (analysis.hasReps) ...[
          const SizedBox(height: 12),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: DataTable(
              headingRowHeight: 36,
              dataRowMinHeight: 32,
              dataRowMaxHeight: 36,
              columns: const [
                DataColumn(label: Text('Rep')),
                DataColumn(label: Text('Start (s)'), numeric: true),
                DataColumn(label: Text('Duration (s)'), numeric: true),
                DataColumn(label: Text('Avg (px/s)'), numeric: true),
                DataColumn(label: Text('Peak (px/s)'), numeric: true),
                DataColumn(label: Text('ROM (px)'), numeric: true),
              ],
              rows: [
                for (final rep in reps)
                  DataRow(cells: [
                    DataCell(Text('${rep.repIndex + 1}')),
                    DataCell(Text(
                        (rep.startFrame / analysis.fps).toStringAsFixed(2))),
                    DataCell(Text(rep.durationS.toStringAsFixed(2))),
                    DataCell(Text(rep.avgVelPxS.toStringAsFixed(0))),
                    DataCell(Text(rep.maxVelPxS.toStringAsFixed(0))),
                    DataCell(Text(rep.displacementPx.toStringAsFixed(0))),
                  ]),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final analysis = widget.output.analysis;
    final preview = widget.output.preview;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (preview.isNotEmpty)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: (240 * preview.first.width /
                                preview.first.height)
                            .clamp(160.0, 480.0),
                        child: LiftPlayer(
                            frames: preview, cursorTime: _cursorTime),
                      ),
                      const SizedBox(width: 20),
                      Expanded(child: _summary(context)),
                    ],
                  )
                else
                  _summary(context),
                const SizedBox(height: 16),
                ValueListenableBuilder<double>(
                  valueListenable: _cursorTime,
                  builder: (context, t, _) => Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      PositionChart(
                          analysis: analysis,
                          cursorTime: preview.isEmpty ? null : t),
                      const SizedBox(height: 20),
                      VelocityChart(
                          analysis: analysis,
                          cursorTime: preview.isEmpty ? null : t),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
