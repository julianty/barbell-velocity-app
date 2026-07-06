# Handoff: bug-hunt / review session

Written 2026-07-06 for a fresh session whose job is to run review agents over
this repo and find bugs, correctness risks, and cleanup opportunities.
Companion docs: `PROGRESS.md` (full history, decisions, environment findings),
`REFERENCE_NOTES.md` (exact algorithm spec the analysis layer must match).

## What this app is

Flutter app (web + iOS) that estimates barbell velocity from a lift video:
frames → YOLOv8-pose inference (wrists 9+10 averaged = bar proxy) → pure-Dart
analysis (faithful port of `barbell-speed-estimator/yolo_pose/analysis.py`) →
results UI (lift replay + position/velocity charts with synced cursor + rep
table). Everything runs on-device; there is no server component.

State: all features code-complete and web-verified end-to-end in Chrome on a
real deadlift clip. iOS code written but NEVER compiled (no Mac here).
`flutter analyze` clean, `flutter test` 122/122 green, `flutter build web`
clean, ~9 commits on `main`, no remote.

## How to verify anything

```powershell
cd C:\Users\alexa\repos\barbell_velocity_app
flutter analyze
flutter test                 # 122 tests, ~5 s
flutter build web            # also compile-checks JS interop via lib/main.dart
flutter build web -t lib/dev/compile_check.dart   # forces ALL platform code paths
```

Manual web run: `cd build\web; python -m http.server 8080`, open
localhost:8080 (tab must stay VISIBLE or extraction hangs — known Chrome
behavior, documented in PROGRESS.md). A 0.6 MB test clip lives at
`build/web/deadlift_clip.mp4` (untracked; regenerate with ffmpeg from the
reference repo's videos if missing).

## Hard invariants — flag ANY violation

1. **The analysis layer (`lib/analysis/`) must match the Python reference
   bit-for-bit on the golden fixtures.** `test/golden/golden_test.dart` +
   `test/fixtures/*.golden.json` are the contract (segments/phases
   integer-exact; signals rtol 1e-6 / atol 1e-4). Any "simplification" that
   changes fixture output is a bug, even if it looks more correct — including
   the deliberately weird bits:
   - ruptures PELT internals (jump quantization, first-strict-minimum
     tie-break, pruning with per-segment penalty)
   - scipy find_peaks semantics (plateau midpoints, distance-before-prominence,
     height-priority suppression)
   - stable sorts where Python sorts are stable and Dart's `sort` is not
     (`_stableSortDesc` in concentric.dart)
   - sequential in-place outlier removal; SavGol `mode='interp'` edges;
     `v[0]=0` velocity; end-exclusive rep slices `smoothVelocity[start:end)`
   - a perfectly-still nonzero signal yielding one ~0-displacement "rep"
     (float noise + reference's max-displacement fallback) is FAITHFUL, not
     a bug.
2. **Documented deviations are intentional** (in code comments + PROGRESS.md):
   savgolFilter returns input when window > n; empty/all-missing tracks return
   an empty AnalysisResult instead of crashing; velocity uses uniform fps even
   though web frame sampling is uneven (matches reference; the chart cursor
   compensates via `PipelineOutput.chartTimeForPlaybackTime`).

## Where bugs are most likely (review priorities)

1. `lib/input/web_frame_source.dart` — JS interop, event-listener lifecycle,
   the pause/resume backpressure added late (onPause/onResume racing play()
   promises; AbortError swallowing by string match), stream teardown, object
   URL revocation, listeners never removed on dispose.
2. `lib/inference/web_onnx_backend.dart` — hand-rolled `dart:js_interop` for
   ort (extension types, `Uri.base.resolve('vendor/')`); tensor lifetime
   (no explicit release of input/output tensors); session reuse.
3. `lib/pipeline/video_pipeline.dart` — error mapping, dispose in `finally`
   (source/backend dispose can themselves throw and mask errors), progress
   fraction math, memory: PreviewCollector caps (300 frames × ~410 KB ≈ 120 MB
   worst case — check the comment's arithmetic and whether the cap is sane).
4. `lib/ui/lift_player.dart` — Timer.periodic + setState every tick, ui.Image
   lifecycle (decode cache never evicts; dispose during in-flight decode
   guarded by `mounted` only), binary search edge cases.
5. `lib/inference/yolo_decoder.dart` — letterbox rounding vs ultralytics
   (`round(pad-0.1)`), clamp-to-`size-1` asymmetries, NMS on empty input.
6. iOS files (`ios/Runner/FrameExtractor.swift`, `lib/inference/
   ios_yolo_backend.dart`, `lib/input/ios_frame_source.dart`) — NEVER
   compiled; review for API misuse but expect real verification on a Mac.
   Known soft spots: EventChannel error emission as FlutterError object (is
   `emit(FlutterError…)` valid for an event sink?), `reading` flag data race,
   PNG re-encode per frame cost in ios_yolo_backend.
7. Tests themselves — `pumpUntilFound` helper exists because pumpAndSettle
   stalls on timer-driven streams; widget tests must unmount LiftPlayer before
   ending (pending Timer.periodic). New tests must follow both patterns.

## Suggested agent split

- Agent A: analysis layer vs REFERENCE_NOTES.md + fixtures (correctness only).
- Agent B: web platform layer (input/inference/pipeline JS interop, memory,
  lifecycle).
- Agent C: UI + tests (player/charts sync, state machine, test hygiene).
- Agent D (optional): iOS code desk-review.
Run `/code-review` on the whole tree or per-area; verify candidate findings
against the invariants above before reporting — especially anything touching
lib/analysis/, where "obvious fixes" are usually fixture-breaking.

## Environment

Windows 11, Flutter 3.41.9 / Dart 3.11.5, no Xcode. Reference repo (Python,
fixtures regenerable via `tools/dump_golden.py` in its `bb-speed-env`):
`C:\Users\alexa\repos\barbell-speed-estimator`. Deps pinned in pubspec:
file_picker 11.0.2, ultralytics_yolo 0.6.9, web 1.1.1, fl_chart ^1.1.1;
onnxruntime-web 1.27.0 vendored in `web/vendor/`.
