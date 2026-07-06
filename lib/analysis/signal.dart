/// Signal-processing primitives ported from the reference `utils.py`
/// (remove_outliers, smooth_positions, compute_velocity) plus the NaN
/// interpolation used throughout. Numerics match numpy/scipy behavior.
library;

import 'dart:math' as math;

/// Median with numpy semantics (even-length -> mean of the two middle values).
double median(List<double> values) {
  final sorted = List<double>.of(values)..sort();
  final n = sorted.length;
  if (n == 0) return double.nan;
  return n.isOdd
      ? sorted[n ~/ 2]
      : (sorted[n ~/ 2 - 1] + sorted[n ~/ 2]) / 2.0;
}

/// Fill NaNs by linear interpolation over indices, matching
/// `np.interp(idx[nan], idx[valid], arr[valid])`: values outside the valid
/// range are clamped to the first/last valid value. All-NaN input is
/// returned unchanged.
List<double> interpolateNan(List<double> arr) {
  final n = arr.length;
  final out = List<double>.of(arr);
  final validIdx = <int>[];
  for (var i = 0; i < n; i++) {
    if (!arr[i].isNaN) validIdx.add(i);
  }
  if (validIdx.isEmpty || validIdx.length == n) return out;
  for (var i = 0; i < n; i++) {
    if (!out[i].isNaN) continue;
    if (i <= validIdx.first) {
      out[i] = arr[validIdx.first];
    } else if (i >= validIdx.last) {
      out[i] = arr[validIdx.last];
    } else {
      // Find the surrounding valid indices (binary search).
      var lo = 0, hi = validIdx.length - 1;
      while (hi - lo > 1) {
        final mid = (lo + hi) ~/ 2;
        if (validIdx[mid] < i) {
          lo = mid;
        } else {
          hi = mid;
        }
      }
      final x0 = validIdx[lo], x1 = validIdx[hi];
      final y0 = arr[x0], y1 = arr[x1];
      out[i] = y0 + (y1 - y0) * (i - x0) / (x1 - x0);
    }
  }
  return out;
}

/// Rolling-median outlier removal, ported from `utils.remove_outliers`.
///
/// Sequential in-place semantics like the reference: later windows see
/// already-corrected values. `null`/NaN entries are preserved (NaN
/// comparisons are false). `window` is the half-width.
List<double> removeOutliers(
  List<double?> positions, {
  int window = 3,
  double threshold = 50.0,
}) {
  final n = positions.length;
  final arr = [for (final p in positions) p ?? double.nan];
  for (var i = 0; i < n; i++) {
    final start = math.max(0, i - window);
    final end = math.min(n, i + window + 1);
    final local = <double>[];
    for (var j = start; j < end; j++) {
      if (!arr[j].isNaN) local.add(arr[j]);
    }
    if (local.length < 3) continue;
    final med = median(local);
    if ((arr[i] - med).abs() > threshold) arr[i] = med;
  }
  return arr;
}

/// Savitzky-Golay filter matching `scipy.signal.savgol_filter` with the
/// default `mode='interp'` edge handling (a polynomial of order [poly] is
/// least-squares fit to the first/last [window] values and evaluated at the
/// edge positions).
///
/// Deviation from scipy (documented): scipy raises if `window > n`; here the
/// input is returned unchanged so degenerate tracks fail soft.
List<double> savgolFilter(List<double> y, int window, int poly) {
  final n = y.length;
  if (n == 0) return <double>[];
  if (window > n) return List<double>.of(y);
  final half = window ~/ 2;
  final w = _savgolCoeffs(window, poly);
  final out = List<double>.filled(n, 0.0);
  for (var i = half; i < n - half; i++) {
    var s = 0.0;
    for (var k = 0; k < window; k++) {
      s += w[k] * y[i - half + k];
    }
    out[i] = s;
  }
  // mode='interp' edges.
  final xs = [for (var i = 0; i < window; i++) i.toDouble()];
  final leftCoeffs = polyfit(xs, y.sublist(0, window), poly);
  for (var i = 0; i < half; i++) {
    out[i] = polyval(leftCoeffs, i.toDouble());
  }
  final rightCoeffs = polyfit(xs, y.sublist(n - window), poly);
  for (var i = 0; i < half; i++) {
    out[n - half + i] = polyval(rightCoeffs, (window - half + i).toDouble());
  }
  return out;
}

/// `utils.smooth_positions` as called by the reference: null -> NaN, linear
/// NaN interpolation, then Savitzky-Golay.
List<double> smoothPositions(
  List<double?> positions, {
  int window = 9,
  int poly = 3,
}) {
  final arr = interpolateNan([for (final p in positions) p ?? double.nan]);
  return savgolFilter(arr, window, poly);
}

/// `utils.compute_velocity`: v[0] = 0; v[i] = (p[i] - p[i-1]) * fps.
/// A null neighbor yields 0 (reference `is None` branch); NaN propagates.
List<double> computeVelocity(List<double?> positions, double fps) {
  if (positions.isEmpty) return <double>[];
  final v = <double>[0.0];
  for (var i = 1; i < positions.length; i++) {
    final a = positions[i], b = positions[i - 1];
    v.add(a == null || b == null ? 0.0 : (a - b) * fps);
  }
  return v;
}

/// Convolution weights for the Savitzky-Golay interior: the value at the
/// window center of the least-squares polynomial fit. Solves the normal
/// equations of the Vandermonde system exactly (small, well-conditioned).
List<double> _savgolCoeffs(int window, int poly) {
  final half = window ~/ 2;
  final nCoef = poly + 1;
  // A[r][c] = (r - half)^c
  final a = [
    for (var r = 0; r < window; r++)
      [for (var c = 0; c < nCoef; c++) math.pow((r - half).toDouble(), c) as double]
  ];
  // M = A^T A
  final m = [
    for (var i = 0; i < nCoef; i++)
      [
        for (var j = 0; j < nCoef; j++)
          [for (var r = 0; r < window; r++) a[r][i] * a[r][j]]
              .reduce((x, y) => x + y)
      ]
  ];
  // Solve M z = e0; weights = A z.
  final z = _solve(m, [1.0, for (var i = 1; i < nCoef; i++) 0.0]);
  return [
    for (var r = 0; r < window; r++)
      [for (var c = 0; c < nCoef; c++) a[r][c] * z[c]].reduce((x, y) => x + y)
  ];
}

/// Least-squares polynomial fit, numpy `polyfit` convention: returns
/// coefficients highest degree first.
List<double> polyfit(List<double> x, List<double> y, int degree) {
  final nCoef = degree + 1;
  final n = x.length;
  // Vandermonde, highest degree first: A[r][c] = x[r]^(degree - c)
  final a = [
    for (var r = 0; r < n; r++)
      [
        for (var c = 0; c < nCoef; c++)
          math.pow(x[r], degree - c).toDouble()
      ]
  ];
  final m = [
    for (var i = 0; i < nCoef; i++)
      [
        for (var j = 0; j < nCoef; j++)
          [for (var r = 0; r < n; r++) a[r][i] * a[r][j]]
              .reduce((p, q) => p + q)
      ]
  ];
  final rhs = [
    for (var i = 0; i < nCoef; i++)
      [for (var r = 0; r < n; r++) a[r][i] * y[r]].reduce((p, q) => p + q)
  ];
  return _solve(m, rhs);
}

/// Evaluate polynomial (highest degree first) via Horner's method.
double polyval(List<double> coeffs, double x) {
  var acc = 0.0;
  for (final c in coeffs) {
    acc = acc * x + c;
  }
  return acc;
}

/// Gaussian elimination with partial pivoting for small dense systems.
List<double> _solve(List<List<double>> m, List<double> rhs) {
  final n = rhs.length;
  final aug = [
    for (var i = 0; i < n; i++) [...m[i], rhs[i]]
  ];
  for (var col = 0; col < n; col++) {
    var pivot = col;
    for (var r = col + 1; r < n; r++) {
      if (aug[r][col].abs() > aug[pivot][col].abs()) pivot = r;
    }
    if (pivot != col) {
      final tmp = aug[col];
      aug[col] = aug[pivot];
      aug[pivot] = tmp;
    }
    final pv = aug[col][col];
    for (var r = col + 1; r < n; r++) {
      final f = aug[r][col] / pv;
      for (var c = col; c <= n; c++) {
        aug[r][c] -= f * aug[col][c];
      }
    }
  }
  final x = List<double>.filled(n, 0.0);
  for (var r = n - 1; r >= 0; r--) {
    var s = aug[r][n];
    for (var c = r + 1; c < n; c++) {
      s -= aug[r][c] * x[c];
    }
    x[r] = s / aug[r][r];
  }
  return x;
}
