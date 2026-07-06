/// Platform-selecting InferenceBackend factory (mirrors
/// lib/input/frame_source_factory.dart): web -> onnxruntime-web, iOS ->
/// ultralytics_yolo (CoreML).
library;

import 'inference_backend.dart';

import 'backend_stub.dart'
    if (dart.library.js_interop) 'web_onnx_backend.dart'
    if (dart.library.io) 'ios_yolo_backend.dart';

InferenceBackend createInferenceBackend() => createInferenceBackendImpl();
