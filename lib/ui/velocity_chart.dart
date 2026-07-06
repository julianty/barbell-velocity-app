/// Bar velocity over time: a single-series fl_chart line (smoothed velocity,
/// px/s) with the detected concentric phases shaded as vertical ranges.
/// Hover/touch shows a time + velocity tooltip on the nearest point.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analysis/models.dart';
import 'viz_palette.dart';

class VelocityChart extends StatelessWidget {
  final AnalysisResult analysis;

  const VelocityChart({super.key, required this.analysis});

  @override
  Widget build(BuildContext context) {
    final viz = VizPalette.of(context);
    final fps = analysis.fps;
    final velocity = analysis.smoothVelocity;

    final spots = <FlSpot>[
      for (var i = 0; i < velocity.length; i++)
        if (velocity[i].isFinite) FlSpot(i / fps, velocity[i]),
    ];
    if (spots.length < 2) return const SizedBox.shrink();

    final labelStyle = TextStyle(color: viz.muted, fontSize: 11);

    return AspectRatio(
      aspectRatio: 16 / 9,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: viz.surface,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
          child: LineChart(
            LineChartData(
              rangeAnnotations: RangeAnnotations(
                verticalRangeAnnotations: [
                  for (final (start, end) in analysis.phases)
                    VerticalRangeAnnotation(
                      x1: start / fps,
                      x2: end / fps,
                      color: viz.phaseWash,
                    ),
                ],
              ),
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: viz.gridline, strokeWidth: 1),
              ),
              titlesData: FlTitlesData(
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                bottomTitles: AxisTitles(
                  axisNameWidget: Text('time (s)', style: labelStyle),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 24,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(meta.formattedValue, style: labelStyle),
                    ),
                  ),
                ),
                leftTitles: AxisTitles(
                  axisNameWidget: Text('velocity (px/s)', style: labelStyle),
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (value, meta) => SideTitleWidget(
                      meta: meta,
                      child: Text(meta.formattedValue, style: labelStyle),
                    ),
                  ),
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(bottom: BorderSide(color: viz.axis)),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => viz.textPrimary.withValues(alpha: 0.9),
                  getTooltipItems: (touched) => [
                    for (final spot in touched)
                      LineTooltipItem(
                        '${spot.x.toStringAsFixed(2)} s\n'
                        '${spot.y.toStringAsFixed(0)} px/s',
                        TextStyle(color: viz.surface, fontSize: 12),
                      ),
                  ],
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  color: viz.series1,
                  barWidth: 2,
                  dotData: const FlDotData(show: false),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
