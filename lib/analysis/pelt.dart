/// PELT changepoint detection with an L2 (piecewise-constant mean) cost,
/// replicating `ruptures.Pelt(model="l2")` (v1.1.10) including its
/// `min_size=2` / `jump=5` defaults, candidate ordering, first-minimum
/// tie-breaking, and pruning rule — so that results match the Python
/// reference bit-for-bit on the same input.
library;

/// Returns the sorted breakpoint end-indices, including `signal.length`
/// as the final breakpoint (ruptures `predict` convention).
List<int> peltL2(
  List<double> signal, {
  required double pen,
  int minSize = 2,
  int jump = 5,
}) {
  final n = signal.length;
  if (n == 0) return <int>[];
  if (n < minSize) return <int>[n]; // degenerate; reference would raise

  // Prefix sums for O(1) L2 segment cost:
  // cost(s, e) = sum(x^2) - sum(x)^2 / (e - s)
  final s1 = List<double>.filled(n + 1, 0.0);
  final s2 = List<double>.filled(n + 1, 0.0);
  for (var i = 0; i < n; i++) {
    s1[i + 1] = s1[i] + signal[i];
    s2[i + 1] = s2[i] + signal[i] * signal[i];
  }
  double cost(int s, int e) {
    final sum = s1[e] - s1[s];
    return (s2[e] - s2[s]) - sum * sum / (e - s);
  }

  // partitions[t] = optimal partition of signal[0:t]:
  // its breakpoint ends and total cost (segment costs + pen per segment).
  final partitions = <int, ({List<int> ends, double total})>{
    0: (ends: const <int>[], total: 0.0),
  };
  var admissible = <int>[];

  final ind = <int>[
    for (var k = 0; k < n; k += jump)
      if (k >= minSize) k,
    n,
  ];

  for (final bkp in ind) {
    // Python floor division; bkp >= minSize for all entries except possibly
    // a tiny final n, which the n < minSize guard above excludes.
    final newAdm = ((bkp - minSize) ~/ jump) * jump;
    admissible.add(newAdm);

    final candidates = <({int t, List<int> ends, double total})>[];
    for (final t in admissible) {
      final part = partitions[t];
      if (part == null) continue; // mirrors the reference's KeyError skip
      candidates.add((
        t: t,
        ends: part.ends,
        total: part.total + cost(t, bkp) + pen,
      ));
    }
    if (candidates.isEmpty) continue;

    // First strict minimum, like Python's min() over insertion order.
    var best = candidates.first;
    for (final c in candidates.skip(1)) {
      if (c.total < best.total) best = c;
    }
    partitions[bkp] = (ends: [...best.ends, bkp], total: best.total);

    // Prune: keep t whose candidate total is within pen of the new optimum.
    admissible = [
      for (final c in candidates)
        if (c.total <= best.total + pen) c.t,
    ];
  }

  return partitions[n]!.ends;
}
