# Reference pipeline spec (source of truth: barbell-speed-estimator)

Port target. Source files (read 2026-07-05, all committed in that repo):
- `yolo_pose/analysis.py` — orchestration + defaults actually used
- `yolo_pose/detect_concentric.py` — concentric detection
- `utils.py` (repo root) — outlier removal, smoothing, velocity
- `yolo_pose/build_barbell_track.py` — track construction from keypoints (for inference layer)

## Input data model

`barbell_track.json`: `[{ "frame": "<name>", "center": [x, y] | null }, ...]`
- `center` = average of COCO wrist keypoints 9 (L) and 10 (R) of the locked person.
- **No confidence field exists** — missing detection is encoded as `center: null`.
- `meta.json`: `{ "fps": float, "video": str }`. fps drives velocity scaling.
- Position signal = `-center[1]` (y flipped so up = positive). x is ignored.

## Stages, in exact order (analysis.py __main__)

1. **extract_positions**: `pos[i] = -center[i][1]`, or `None` if center null.
2. **remove_outliers(pos, window=3, threshold=50)** — NOTE: call-site values, not
   utils defaults (5/50). Rolling median over `arr[max(0,i-w) : min(n,i+w+1)]`
   excluding NaNs; if <3 valid neighbors, skip; if `|arr[i] - median| > threshold`,
   replace with median. None→NaN survives (NaN comparisons are False). Returns list.
3. **smooth_positions(clean, window=9, poly=3)** — call-site values (utils default
   window=36 is NOT used). Linearly interpolate NaNs first (np.interp, edge-holds),
   then `scipy.signal.savgol_filter(window_length=9, polyorder=3)` with default
   **mode='interp'** (poly fit to first/last window for edges). Must replicate.
4. **compute_velocity(positions, fps)** — `v[0]=0; v[i]=(p[i]-p[i-1])*fps`. If either
   neighbor is None → 0. NaNs propagate (raw path only). Run on BOTH clean (raw_vel)
   and smoothed (smooth_vel). Units: px/s.
5. **detect_concentric(method="ruptures", pen=20, min_frames=5, smooth_velocity=smooth_vel,
   merge_min_vel=50.0, extension_lookahead=30, min_rep_ratio=0.60, return_segments=True)**
   — pen=20 comes from analysis.py main (function default 3.0 is NOT used).

### detect_concentric_ruptures internals (port exactly)

0. `_interpolate`: None→NaN, np.interp fill; all-NaN → return empty.
1. `vel = np.diff(arr)` (px/frame, NOT fps-scaled — distinct from smooth_velocity).
   PELT: `ruptures.Pelt(model="l2").fit(vel).predict(pen=20)`.
   **ruptures defaults: min_size=2, jump=5** — breakpoints only at indices ≡ 0 mod 5
   (except final). l2 cost = sum of squared deviations from segment mean. Must match.
   `boundaries = [0] + breakpoints` (last breakpoint = len(vel)).
2. Segments: for consecutive boundary pairs (v_start, v_end):
   start=v_start, end=v_end (segments SHARE the boundary frame — off-by-one quirk,
   keep it), frames=end-start+1, displacement=arr[end]-arr[start],
   skipped_short = frames < min_frames.
3. Merge runs: `_qualifies(seg)` = not short AND displacement>0 AND avg_vel ≥ merge_min_vel,
   where avg_vel = mean(smooth_velocity[s+1 : e+1]) (list slice; empty→0.0).
   Runs of ≥2 consecutive qualifying segments (scan over ORIGINAL segments only,
   index < n_original) append a synthetic merged candidate {merged: true}.
4. Candidates = all segments with not skipped_short and displacement > 0
   (merged ones included).
5. Expected rep displacement: scipy find_peaks on arr with
   distance=max(1, len//20), prominence=(max-min)*0.15, same for troughs on -arr.
   For each trough, pair with first peak AFTER it (advancing cursor), collect
   arr[peak]-arr[trough]; expected = median, else max-min if no pairs.
   Qualified = candidates with displacement ≥ min_rep_ratio * expected.
6. Dedup: sort qualified by (merged, displacement) DESC; greedy keep non-overlapping
   (overlap = cand.start < sel.end && sel.start < cand.end); sort selected by start.
   Fallback: if none selected but candidates exist → single max-displacement candidate.
7. Extend each phase: forward while end+1 < n && count<30 && smooth_velocity[end] > 0
   && arr[end+1] > arr[end]; backward while start-1 ≥ 0 && count<30 &&
   smooth_velocity[start-1] > 0. Clamp to [0, n-1].

Returns phases [(start,end)] + segments (with selected/skipped_short/merged flags).

### detect_concentric_peaks (also port; not the default path)

find_peaks distance=max(1,len//20), prominence=(max-min)*0.3 on arr and -arr.
Pair trough → first following peak (cursor advances past used peaks); skip if
peak-trough < min_frames (default 20). Returns [(trough, peak)].

### Per-rep metrics (from analysis.py plotting/printing)

For each phase (start, end): avg = mean(smooth_vel[start:end]) (END-EXCLUSIVE),
max = max(smooth_vel[start:end]), duration = (end-start)/fps, rep count = len(phases).
Units px/s. Plus displacement px (ROM proxy) available from arr[end]-arr[start].

## Dart implementations needed from scratch

- Savitzky-Golay filter incl. scipy mode='interp' edge handling (polyfit on end windows).
- PELT changepoint (l2 cost via prefix sums; min_size=2, jump=5 semantics = ruptures).
- find_peaks with scipy's distance (sort-by-height suppression) + prominence semantics.
- Linear interpolation matching np.interp (edge hold).
- Rolling median outlier removal.

## Known reference quirks (keep, do not "fix")

- Adjacent PELT segments share a boundary frame.
- remove_outliers leaves NaN in place; smoothing interpolates them.
- avg-velocity slice in _qualifies is [s+1, e+1] but per-rep avg is [start, end).
- compute_velocity[0] = 0 sentinel.
- Dedup prefers merged candidates over raw displacement.

## Config defaults (single AnalysisConfig object)

| param | default | source |
|---|---|---|
| outlierWindow | 3 | analysis.py call |
| outlierThreshold | 50.0 px | analysis.py call |
| sgWindow | 9 | analysis.py call |
| sgPoly | 3 | analysis.py call |
| pen | 20.0 | analysis.py main |
| minFrames | 5 | analysis.py |
| mergeMinVel | 50.0 px/s | analysis.py |
| extensionLookahead | 30 | analysis.py |
| minRepRatio | 0.60 | analysis.py |
| peltMinSize | 2 | ruptures default |
| peltJump | 5 | ruptures default |
| peaksMinFrames | 20 | detect_concentric.py default |
