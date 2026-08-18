# Investigation: Downscaling Video Resolution for Faster Frame Processing / Inference

Status: **not started** — discussion only, to revisit once there's a working, verified demo build (see `DEMO_PREP.md`). Deliberately deferred so it doesn't get tangled up with the demo-blocker fixes already in flight.

## Why this came up

Two things already in `DEMO_PREP.md` point at frame size as a cost driver:
- Item 3 (backpressure fix, done): smaller frames queued means more frames fit in the bounded in-flight buffer before memory pressure becomes a concern — downscaling would compound that fix, not replace it.
- Item 9 / "worth fixing later": the per-frame PNG re-encode in `lib/inference/ios_yolo_backend.dart:37-57` is confirmed real overhead (tens of ms at 1080p) and was already suggested to downscale to `targetWidth: 640` before encoding.

This doc generalizes that from "one known encode step" to "should we downscale earlier/more broadly in the pipeline."

## Upsides

- Cuts CoreML inference time and, more significantly, the PNG-encode cost that's pure image-size-bound.
- Shrinks per-frame payload size — directly reduces peak memory during the in-flight buffering window from item 3, independent of the credit-gating fix.
- Better battery/thermal behavior during a live demo, where inference is the sustained hot loop.
- Many detectors (YOLO pose included) internally resize to a fixed input size (commonly 640×640, letterboxed) regardless of source resolution. If the source is well above that, full-res encode/transfer may be paying cost for zero accuracy benefit, since the model never sees more detail than its native input size anyway.

## Downsides / risks

- **Velocity is a finite difference of wrist-keypoint position** — pixel quantization from downscaling doesn't just add noise, differentiation amplifies it. The shared Python pipeline (`utils.py`) already needs Savitzky-Golay smoothing and median-based outlier removal to handle noise at *current* resolution; more aggressive downscaling would likely need those parameters retuned, not just reused as-is.
- **Calibration coupling (SAM2 / YOLO-seg pipelines)**: `px/mm` calibration is derived from the plate mask on a calibration frame. That calibration is resolution-dependent — downscaling has to be applied consistently to the calibration frame and every subsequent frame, or the m/s output becomes silently wrong. (The YOLO-pose pipeline, and this Flutter app's port of it, output px/s and aren't calibration-coupled, but keep this in mind if downscaling work ever touches the segmentation pipelines.)
- Downscaled frames make the annotated output video harder to visually spot-check — `CLAUDE.md` already calls this out as important for validating tracking quality at low FPS; the same logic applies to low resolution.
- Diminishing/no return if downscaled below what the model already resizes to internally — need to confirm the model's actual native input size before picking a target, or the "savings" may be illusory.

## Recommendation (pending actual investigation)

Start with downscaling to roughly the model's native input size (~640 on the long edge) immediately before the PNG-encode step in the iOS inference path — low-risk, likely no accuracy cost, and consistent with the item-9 suggestion already in `DEMO_PREP.md`. Do not extend this to more aggressive downscaling, or to the Python pipelines' velocity math, without re-validating the smoothing/PELT tuning against the new pixel scale first.

## Open questions to resolve when this is picked up

1. What is `yolo26s-pose.mlpackage`'s actual native input resolution? (Confirms whether pre-encode downscaling to 640 is a free win or whether the model already receives full-res and does its own resize internally, e.g. via CoreML's built-in image-input scaling.)
2. Where exactly should the downscale happen — in Swift before crossing the platform channel (cheapest, avoids transferring full-res data at all) vs. in Dart right before encode? Given item 3's fix, doing it in Swift also shrinks the in-flight buffer's memory footprint, which is the stronger argument.
3. Does downscaling change the keypoint-to-original-frame coordinate mapping in a way that needs explicit rescaling before display (the results UI overlays keypoints on the original-resolution preview frame)?
4. Is there a measurable inference/encode time delta worth chasing, or is PNG encode already the dominant cost regardless of resolution below some threshold? Worth profiling on-device once a build exists, rather than assuming.
