/// Compile-check entrypoint: `flutter build web -t lib/dev/compile_check.dart`
/// forces dart2js to compile the platform-conditional layers (web frame
/// source + ONNX backend) before the real UI wires them in. Not shipped.
library;

import '../inference/backend_factory.dart';
import '../input/frame_source_factory.dart';
import '../input/video_picker.dart';

Future<void> main() async {
  final picked = await pickVideo();
  if (picked == null) return;
  final source = createFrameSource(picked);
  final backend = createInferenceBackend();
  await backend.load();
  final info = await source.open();
  // ignore: avoid_print
  print('video: ${info.width}x${info.height} @ ${info.fps}');
  await for (final frame in source.frames()) {
    final detections = await backend.infer(frame);
    // ignore: avoid_print
    print('frame ${frame.index}: ${detections.length} people');
  }
  await source.dispose();
  await backend.dispose();
}
