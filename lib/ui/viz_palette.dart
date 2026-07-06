/// Chart color roles (light + dark), from the validated reference dataviz
/// palette: series-1 blue, muted ink for axis labels, hairline gridlines.
/// One series per chart, so no legend — the title names it.
library;

import 'package:flutter/material.dart';

class VizPalette {
  final Color surface;
  final Color textPrimary;
  final Color textSecondary;
  final Color muted;
  final Color gridline;
  final Color axis;
  final Color series1;

  const VizPalette._({
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.muted,
    required this.gridline,
    required this.axis,
    required this.series1,
  });

  static const light = VizPalette._(
    surface: Color(0xFFFCFCFB),
    textPrimary: Color(0xFF0B0B0B),
    textSecondary: Color(0xFF52514E),
    muted: Color(0xFF898781),
    gridline: Color(0xFFE1E0D9),
    axis: Color(0xFFC3C2B7),
    series1: Color(0xFF2A78D6),
  );

  static const dark = VizPalette._(
    surface: Color(0xFF1A1A19),
    textPrimary: Color(0xFFFFFFFF),
    textSecondary: Color(0xFFC3C2B7),
    muted: Color(0xFF898781),
    gridline: Color(0xFF2C2C2A),
    axis: Color(0xFF383835),
    series1: Color(0xFF3987E5),
  );

  static VizPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark ? dark : light;

  /// Wash for shaded concentric-phase ranges: the series hue, recessive.
  Color get phaseWash => series1.withValues(alpha: 0.14);
}
