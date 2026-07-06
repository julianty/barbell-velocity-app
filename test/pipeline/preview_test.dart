import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:barbell_velocity_app/input/frame_source.dart';
import 'package:barbell_velocity_app/pipeline/preview.dart';

VideoFrame frame(int width, int height, double t, {int fill = 7}) =>
    VideoFrame(
      index: (t * 30).round(),
      timestampS: t,
      width: width,
      height: height,
      rgba: Uint8List(width * height * 4)..fillRange(0, width * height * 4, fill),
    );

void main() {
  group('downscaleFrame', () {
    test('small frames are kept at native size (copied)', () {
      final f = frame(320, 180, 0);
      final p = downscaleFrame(f, maxHeight: 240);
      expect((p.width, p.height), (320, 180));
      expect(p.rgba, f.rgba);
      expect(identical(p.rgba, f.rgba), isFalse);
    });

    test('large frames scale to maxHeight with aspect preserved', () {
      final p = downscaleFrame(frame(1280, 720, 1.5), maxHeight: 240);
      expect(p.height, 240);
      expect(p.width, 427); // 1280 * 240/720, rounded
      expect(p.timestampS, 1.5);
      expect(p.rgba.length, 427 * 240 * 4);
    });

    test('nearest-neighbor samples real pixels', () {
      // 2x2 image with distinct corner colors, downscaled to 1 row.
      final rgba = Uint8List.fromList([
        255, 0, 0, 255, /**/ 0, 255, 0, 255, // top row
        0, 0, 255, 255, /**/ 255, 255, 0, 255, // bottom row
      ]);
      final f = VideoFrame(
          index: 0, timestampS: 0, width: 2, height: 2, rgba: rgba);
      final p = downscaleFrame(f, maxHeight: 1);
      expect(p.height, 1);
      expect(p.width, 1);
      expect(p.rgba, [255, 0, 0, 255]); // top-left corner sampled
    });
  });

  group('PreviewCollector', () {
    test('keeps frames spaced at the target rate', () {
      final c = PreviewCollector(targetFps: 10, maxHeight: 240);
      for (var i = 0; i < 30; i++) {
        c.add(frame(4, 4, i / 30.0)); // 1 s of 30 fps video
      }
      // ~1/10 s spacing over 30 fps input (float rounding can drop one).
      expect(c.frames.length, inInclusiveRange(9, 10));
      for (var i = 1; i < c.frames.length; i++) {
        expect(c.frames[i].timestampS - c.frames[i - 1].timestampS,
            greaterThanOrEqualTo(0.1 - 1e-9));
      }
    });

    test('caps at maxFrames', () {
      final c = PreviewCollector(targetFps: 10, maxFrames: 5);
      for (var i = 0; i < 100; i++) {
        c.add(frame(4, 4, i / 10.0));
      }
      expect(c.frames.length, 5);
    });
  });
}
