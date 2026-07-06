/// Results screen body, mirroring the reference pelt_concentric.png layout:
/// summary line, vertical-position chart, vertical-velocity chart (both with
/// shaded concentric phases), and the per-rep metrics table. Content is
/// width-constrained so it sits comfortably in a desktop browser window.
/// The charts are shown even when no rep qualified — like the reference
/// plots, they're the main debugging aid for such videos.
library;

import 'package:flutter/material.dart';

import '../pipeline/video_pipeline.dart';
import 'velocity_chart.dart';
import 'viz_palette.dart';

class ResultsView extends StatelessWidget {
  final PipelineOutput output;

  const ResultsView({super.key, required this.output});

  @override
  Widget build(BuildContext context) {
    final analysis = output.analysis;
    final theme = Theme.of(context);
    final viz = VizPalette.of(context);
    final reps = analysis.reps;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
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
                    'The bar was tracked (charts below), but no concentric '
                    'phase qualified as a rep.',
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: viz.textSecondary),
                  ),
                ],
                const SizedBox(height: 4),
                Text('Shaded ranges are detected concentric phases',
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: viz.textSecondary)),
                const SizedBox(height: 16),
                PositionChart(analysis: analysis),
                const SizedBox(height: 20),
                VelocityChart(analysis: analysis),
                if (analysis.hasReps) ...[
                  const SizedBox(height: 20),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: DataTable(
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
                            DataCell(Text((rep.startFrame / analysis.fps)
                                .toStringAsFixed(2))),
                            DataCell(Text(rep.durationS.toStringAsFixed(2))),
                            DataCell(Text(rep.avgVelPxS.toStringAsFixed(0))),
                            DataCell(Text(rep.maxVelPxS.toStringAsFixed(0))),
                            DataCell(
                                Text(rep.displacementPx.toStringAsFixed(0))),
                          ]),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}
