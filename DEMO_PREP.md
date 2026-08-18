# Demo Prep — Remaining Work (Priority Order)

Findings from a code survey (deployment blockers), a UI/UX design pass, an implemented UI refactor, an independent Opus code review of that refactor plus the rest of the codebase, and three follow-up fixes for the critical issues that review surfaced. Everything through item 9 has now been verified on Julian's iPhone via a real `flutter run` — signing, orientation, backpressure, video-import flow, and general on-device runtime all confirmed working, and item 6's in-progress work is committed. Remaining open items: 5 (phone-layout test coverage) and the non-blocking cleanup list in item 10. See also `RESOLUTION_DOWNSCALING.md` for a separate performance investigation to pick up once a working demo build exists.

## 1. Set an Xcode signing team — DONE, verified on-device
Signing team set in Xcode (Runner target → Signing & Capabilities), `DEVELOPMENT_TEAM = 8C8536FBN8` now committed in `project.pbxproj`. App builds, installs, and runs on Julian's iPhone via `flutter run`.

## 2. Portrait video analyzed sideways — DONE, verified on-device
`FrameExtractor.swift` previously applied `preferredTransform` to clip *metadata* on `open` but never to the actual per-frame pixel buffers in `readFrames`, so portrait clips had vertical motion land on the wrong axis. Fixed with a new `FrameOrientation` struct that decomposes the track's transform into rotation + mirror, applied per-frame via `vImageRotate90_ARGB8888` / `vImageHorizontal|VerticalReflect_ARGB8888` (no per-pixel loops, no CIContext round-trip) ahead of the existing BGRA→RGBA permute. Emitted width/height now match the rotated buffer. Verified: a standalone harness checked all 8 capture orientations pixel-for-pixel against an independent reference, `xcodebuild ... -sdk iphonesimulator` succeeded, and a real on-device run against an actual portrait clip showed correct orientation in the player.

## 3. No backpressure on iOS frame streaming — DONE, verified on-device
`FrameExtractor.swift` was emitting full-res RGBA frames as fast as `AVAssetReader` allowed, and pausing Dart's broadcast-stream subscription doesn't block the platform-side producer — risk of 2GB+ buffered per clip and an OOM kill mid-demo. Fixed with a credit-gated producer: Swift now caps in-flight unacknowledged frames at 3 (`maxInFlight`, `NSCondition`-guarded), and `lib/input/ios_frame_source.dart` was changed to wrap the broadcast stream in a single-subscription `StreamController` that only pulls from an internal queue while unpaused, sending an `ackFrame` method-channel call for each frame handed to the consumer. The `FrameSource` interface and all other implementations (web, stub, test fakes) are untouched — `VideoPipeline`'s `await for` contract is unchanged. Verified: `flutter analyze` clean, `xcodebuild` succeeded, `flutter test` 122/122, and a real on-device run completed a full video-import → frame-extraction pass without crashing or visible stutter.

## 4. Portrait clips can push the player controls off-screen — DONE, implemented this session
`lib/ui/lift_player.dart`'s video preview now wraps the `AspectRatio` widget in `Center(child: ConstrainedBox(constraints: BoxConstraints(maxHeight: screenHeight * 0.45), ...))`, so a portrait clip letterboxes (narrower width, capped height) instead of overflowing past the screen; landscape clips are unaffected since they're already well under the cap. Also fixed a related latent bug: the code previously guarded `height > 0` but not `width > 0` before constructing `AspectRatio` (which asserts both must be positive) — both are now guarded. Verified: `flutter analyze` clean, `flutter test` 122/122.

## 5. New phone-width layout branch has zero test coverage (new — found in code review)
All 122 existing tests run at Flutter's default 800×600 test-surface size, which only exercises the *wide* (≥700pt, tablet/desktop) branch of the new `LayoutBuilder` in `results_view.dart:247`. The actual phone-width layout the demo depends on has never been exercised by an automated test. Add a test that sets `tester.view.physicalSize = Size(390*3, 844*3)` (or similar) before pumping the results view.

## 6. Commit the in-progress iOS build setup — DONE
`ios/Podfile` + `Podfile.lock`, `ios/Runner/yolo26s-pose.mlpackage/` (wired into `project.pbxproj`), the model-name rename in `lib/inference/ios_yolo_backend.dart` (`yolov8s-pose` → `yolo26s-pose`), the Results/Home UI refactor (item 8), and this session's hero/chart layout tweaks (item 12) are all committed.

## 7. Verify the video-import flow works end-to-end before the demo — DONE, verified on-device
The app has no camera/Photos capture — it uses `file_picker` (`lib/input/video_picker.dart`), which opens the iOS **Files** app, not the Camera Roll. A clip shot with the Camera app won't be pickable until it's saved into Files/iCloud Drive first. Confirmed on-device: picked a real lift video through the Files picker, ran the full pipeline end to end, no crash, correct orientation, sane velocities.

## 8. Results/Home UI refactor — DONE, implemented and verified on-device
`lib/ui/results_view.dart`, `lib/ui/home_screen.dart`, `lib/ui/lift_player.dart`, `lib/ui/velocity_chart.dart`, and `test/widget_test.dart` were rewritten to fix the desktop-first layout (see prior version of this doc for the original problem list). `flutter analyze` is clean and `flutter test` is 122/122 passing. The phone-width branch has now been exercised live on Julian's iPhone and looks correct, but see item 5 above — it's still untested by the automated suite.

## 9. Confirm on-device runtime behavior — DONE, first real run completed successfully
`flutter run` on Julian's iPhone: app installed, launched, ran a full pick → extract → analyze → results pass without crashing. Known issues from the original survey, updated:
- Items 2 and 3 above are fixed in code and now **confirmed on real hardware** — no crash, no visible stutter, correct orientation.
- `FrameExtractor.swift` — the `reading` flag data race noted by the original survey. Low severity (worst case one extra frame processed after cancel); superseded in practice by the new credit-gated `stopReading()`/`isReading` locking added for item 3, which already guards most of the relevant reads/writes. Not separately re-tested.
- ~~EventChannel error emission via a raw FlutterError object~~ — **correction: this is not an issue.** `FlutterEventSink` special-cases `FlutterError` into a proper error envelope, so this surfaces correctly as a `PlatformException` in Dart. (Originally flagged by the deployment survey; the code review confirmed it's a false alarm.)
- `ios_yolo_backend.dart:37-57` — full-res PNG encode per frame confirmed as real overhead (tens of ms at 1080p on top of inference). Still open — not measured/fixed this session. Fix: pass `targetWidth: 640` to `instantiateCodec()` and rescale returned keypoints.

## 10. Worth fixing later (non-blocking, from code review)
- Chart rebuild churn during playback: `velocity_chart.dart:121-137` reallocates ~7k `FlSpot` objects for all series on every tick (~20×/sec while scrubbing) — likely visible jank on-device. Memoize the spot lists per analysis result and pass only the cursor position down.
- `lift_player.dart:75-87` — decoded frame images accumulate in memory across playback and are only freed on `dispose`; add an LRU eviction window for long clips.
- `results_view.dart:81` — "Duration" is computed as `rawPositions.length / fps` rather than the video's actual duration; can be wrong for unevenly-sampled web input.
- `pubspec.yaml` bundles a 47MB web-only `assets/models/yolov8s-pose.onnx` into the iOS build unnecessarily.
- `lift_player.dart:105` guards `height > 0` but not `width > 0` before constructing `AspectRatio`, which asserts both must be positive.
- `home_screen.dart:46-50` — no guard against a double-tap on the picker button starting two concurrent analysis pipelines.

## 11. Add camera/photo-library usage strings only if you add in-app capture later
`ios/Runner/Info.plist` has no `NSCameraUsageDescription`/photo-library keys, but the app doesn't currently use the camera or Photos picker in code — so this isn't a live blocker today. Only relevant if capture is added later.

## 12. Results screen tweaks from the first on-device run — DONE
Two UI requests after seeing the real results screen on-device: the position/velocity charts now render directly under the video (previously after the rep cards) in the phone-first layout; the hero section now shows both **Best avg velocity** and **Best peak velocity**, each labeled with the rep number it was measured at (e.g. "231 px/s rep #2"). `flutter analyze` clean, `flutter test` 122/122, verified live on Julian's iPhone.

---
*Not investigated: `HANDOFF_REVIEW.md`/`PROGRESS.md`/`REFERENCE_NOTES.md` also document algorithm-correctness notes for the Dart port of the Python analysis pipeline (PELT, Savitzky-Golay) — unrelated to deployment/layout, not covered here.*
