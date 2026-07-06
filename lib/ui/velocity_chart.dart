/// Analysis charts, mirroring the reference pipeline's pelt_concentric.png:
/// a vertical-position panel and a vertical-velocity panel, each showing the
/// raw signal (thin, muted) under the Savitzky-Golay smoothed signal
/// (series blue), with detected concentric phases shaded as vertical ranges.
/// Hover/touch shows a time + per-series tooltip on the nearest point.
library;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../analysis/models.dart';
import 'viz_palette.dart';

class PositionChart extends StatelessWidget {
  final AnalysisResult analysis;

  /// Playback time of the lift player; draws a sweeping cursor line.
  final double? cursorTime;

  const PositionChart({super.key, required this.analysis, this.cursorTime});

  @override
  Widget build(BuildContext context) {
    final viz = VizPalette.of(context);
    return _SignalChart(
      title: 'Vertical position (px, up = positive)',
      unit: 'px',
      fps: analysis.fps,
      phases: analysis.phases,
      cursorTime: cursorTime,
      series: [
        _Series('Raw', analysis.rawPositions, viz.muted, 1),
        _Series('SG-smoothed', analysis.smoothPositions, viz.series1, 2),
      ],
    );
  }
}

class VelocityChart extends StatelessWidget {
  final AnalysisResult analysis;

  /// Playback time of the lift player; draws a sweeping cursor line.
  final double? cursorTime;

  const VelocityChart({super.key, required this.analysis, this.cursorTime});

  @override
  Widget build(BuildContext context) {
    final viz = VizPalette.of(context);
    return _SignalChart(
      title: 'Vertical velocity (px/s)',
      unit: 'px/s',
      fps: analysis.fps,
      phases: analysis.phases,
      cursorTime: cursorTime,
      series: [
        _Series('Raw', analysis.rawVelocity, viz.muted, 1),
        _Series('SG-smoothed', analysis.smoothVelocity, viz.series1, 2),
      ],
    );
  }
}

class _Series {
  final String label;
  final List<double> values;
  final Color color;
  final double width;

  const _Series(this.label, this.values, this.color, this.width);
}

class _SignalChart extends StatelessWidget {
  final String title;
  final String unit;
  final double fps;
  final List<Phase> phases;
  final double? cursorTime;

  /// Painted in order; put the primary (smoothed) series last so it draws
  /// on top of the raw signal.
  final List<_Series> series;

  static const double _height = 280;

  const _SignalChart({
    required this.title,
    required this.unit,
    required this.fps,
    required this.phases,
    required this.series,
    this.cursorTime,
  });

  @override
  Widget build(BuildContext context) {
    final viz = VizPalette.of(context);
    final labelStyle = TextStyle(color: viz.muted, fontSize: 11);
    final legendStyle = TextStyle(color: viz.textSecondary, fontSize: 12);

    final bars = <LineChartBarData>[];
    final barLabels = <String>[]; // parallel to bars, for tooltips
    for (final s in series) {
      final spots = <FlSpot>[
        for (var i = 0; i < s.values.length; i++)
          if (s.values[i].isFinite) FlSpot(i / fps, s.values[i]),
      ];
      if (spots.length >= 2) {
        bars.add(LineChartBarData(
          spots: spots,
          color: s.color,
          barWidth: s.width,
          dotData: const FlDotData(show: false),
        ));
        barLabels.add(s.label);
      }
    }
    if (bars.isEmpty) return const SizedBox.shrink();

    // Only draw the cursor inside the plotted x-range (fl_chart asserts on
    // out-of-range extra lines).
    final maxX = bars
        .map((b) => b.spots.last.x)
        .reduce((a, b) => a > b ? a : b);
    final cursor = cursorTime;
    final cursorX =
        cursor != null && cursor >= 0 && cursor <= maxX ? cursor : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(title,
                  style: TextStyle(color: viz.textSecondary, fontSize: 12)),
            ),
            for (final s in series) ...[
              Container(
                width: 14,
                height: s.width + 1,
                margin: const EdgeInsets.only(left: 12, right: 4),
                color: s.color,
              ),
              Text(s.label, style: legendStyle),
            ],
          ],
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: _height,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: viz.surface,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 16, 16, 8),
              child: LineChart(
                LineChartData(
                  extraLinesData: ExtraLinesData(
                    verticalLines: [
                      if (cursorX != null)
                        VerticalLine(
                          x: cursorX,
                          color: viz.textSecondary,
                          strokeWidth: 1,
                        ),
                    ],
                  ),
                  rangeAnnotations: RangeAnnotations(
                    verticalRangeAnnotations: [
                      for (final (start, end) in phases)
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
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
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
                      axisNameWidget: Text(unit, style: labelStyle),
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 56,
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
                      getTooltipColor: (_) =>
                          viz.textPrimary.withValues(alpha: 0.9),
                      getTooltipItems: (touched) => [
                        for (final (i, spot) in touched.indexed)
                          LineTooltipItem(
                            '${i == 0 ? '${spot.x.toStringAsFixed(2)} s\n' : ''}'
                            '${barLabels[spot.barIndex]}: '
                            '${spot.y.toStringAsFixed(unit == 'px' ? 1 : 0)} $unit',
                            TextStyle(color: viz.surface, fontSize: 12),
                          ),
                      ],
                    ),
                  ),
                  lineBarsData: bars,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
