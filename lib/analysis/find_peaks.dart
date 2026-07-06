/// Peak finding replicating `scipy.signal.find_peaks` for the subset of
/// features the reference uses: plateau-aware local maxima, then `distance`
/// filtering, then `prominence` filtering — in scipy's evaluation order.
library;

/// Plateau-aware local maxima (scipy `_local_maxima_1d`): a maximum is a
/// sample (or flat run) strictly greater than both neighbors; a flat run
/// reports its midpoint `(left + right) ~/ 2`. First and last samples can
/// never be maxima.
List<int> localMaxima(List<double> x) {
  final maxima = <int>[];
  final iMax = x.length - 1;
  var i = 1;
  while (i < iMax) {
    if (x[i - 1] < x[i]) {
      var iAhead = i + 1;
      while (iAhead < iMax && x[iAhead] == x[i]) {
        iAhead++;
      }
      if (x[iAhead] < x[i]) {
        final leftEdge = i;
        final rightEdge = iAhead - 1;
        maxima.add((leftEdge + rightEdge) ~/ 2);
        i = iAhead;
      }
    }
    i++;
  }
  return maxima;
}

/// scipy `_select_by_peak_distance`: process peaks from highest to lowest,
/// removing any peak strictly closer than [distance] to a kept peak.
List<int> _selectByPeakDistance(List<int> peaks, List<double> heights, int distance) {
  final n = peaks.length;
  final keep = List<bool>.filled(n, true);
  // argsort(heights) ascending, stable (index tiebreak).
  final order = [for (var i = 0; i < n; i++) i]
    ..sort((a, b) {
      final c = heights[a].compareTo(heights[b]);
      return c != 0 ? c : a.compareTo(b);
    });
  for (var i = n - 1; i >= 0; i--) {
    final j = order[i];
    if (!keep[j]) continue;
    var k = j - 1;
    while (k >= 0 && peaks[j] - peaks[k] < distance) {
      keep[k] = false;
      k--;
    }
    k = j + 1;
    while (k < n && peaks[k] - peaks[j] < distance) {
      keep[k] = false;
      k++;
    }
  }
  return [for (var i = 0; i < n; i++) if (keep[i]) peaks[i]];
}

/// scipy `_peak_prominences` with full window (wlen unset): scan outward
/// from each peak until a strictly higher sample; the base on each side is
/// the minimum over the scanned range; prominence = height - max(bases).
double _prominence(List<double> x, int peak) {
  final height = x[peak];
  var leftMin = height;
  for (var i = peak; i >= 0 && x[i] <= height; i--) {
    if (x[i] < leftMin) leftMin = x[i];
  }
  var rightMin = height;
  for (var i = peak; i < x.length && x[i] <= height; i++) {
    if (x[i] < rightMin) rightMin = x[i];
  }
  return height - (leftMin > rightMin ? leftMin : rightMin);
}

/// `scipy.signal.find_peaks(x, distance=..., prominence=...)` for the
/// features used by the reference. Either filter may be omitted.
List<int> findPeaks(List<double> x, {int? distance, double? prominence}) {
  var peaks = localMaxima(x);
  if (distance != null) {
    peaks = _selectByPeakDistance(peaks, [for (final p in peaks) x[p]], distance);
  }
  if (prominence != null) {
    peaks = [for (final p in peaks) if (_prominence(x, p) >= prominence) p];
  }
  return peaks;
}
