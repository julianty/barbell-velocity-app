/// Results screen body: summary line, velocity chart with shaded concentric
/// phases, and the per-rep metrics table. Handles the zero-reps case.
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

    if (!analysis.hasReps) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.search_off, size: 48),
              const SizedBox(height: 12),
              Text('No reps detected', style: theme.textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                'The bar was tracked, but no concentric phase qualified as a '
                'rep. Try a video where the full lift is visible.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    final reps = analysis.reps;
    final bestAvg =
        reps.map((r) => r.avgVelPxS).reduce((a, b) => a > b ? a : b);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          '${reps.length} rep${reps.length == 1 ? '' : 's'} · '
          'best avg ${bestAvg.toStringAsFixed(0)} px/s · '
          '${analysis.fps.toStringAsFixed(1)} fps',
          style: theme.textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        Text('Bar velocity — shaded ranges are concentric phases',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: viz.textSecondary)),
        const SizedBox(height: 8),
        VelocityChart(analysis: analysis),
        const SizedBox(height: 24),
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
                  DataCell(
                      Text((rep.startFrame / analysis.fps).toStringAsFixed(2))),
                  DataCell(Text(rep.durationS.toStringAsFixed(2))),
                  DataCell(Text(rep.avgVelPxS.toStringAsFixed(0))),
                  DataCell(Text(rep.maxVelPxS.toStringAsFixed(0))),
                  DataCell(Text(rep.displacementPx.toStringAsFixed(0))),
                ]),
            ],
          ),
        ),
      ],
    );
  }
}
