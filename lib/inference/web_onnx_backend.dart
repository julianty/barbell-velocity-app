/// Web InferenceBackend: onnxruntime-web (vendored in web/vendor/, loaded as
/// the global `ort` by a script tag in web/index.html) running the bundled
/// yolov8s-pose.onnx. Pre/post-processing lives in yolo_decoder.dart.
library;

import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:flutter/services.dart' show rootBundle;

import '../input/frame_source.dart';
import 'inference_backend.dart';
import 'yolo_decoder.dart';

InferenceBackend createInferenceBackendImpl() => WebOnnxBackend();

// --- minimal onnxruntime-web interop -------------------------------------

@JS('ort.env.wasm.wasmPaths')
external set _ortWasmPaths(JSString paths);

@JS('ort.InferenceSession.create')
external JSPromise<_OrtSession> _createSession(JSUint8Array model);

@JS('ort.Tensor')
extension type _OrtTensor._(JSObject _) implements JSObject {
  external factory _OrtTensor(
      JSString type, JSFloat32Array data, JSArray<JSNumber> dims);
  external JSFloat32Array get data;
}

extension type _OrtSession._(JSObject _) implements JSObject {
  external JSArray<JSString> get inputNames;
  external JSArray<JSString> get outputNames;
  external JSPromise<JSObject> run(JSObject feeds);
  external JSPromise<JSAny?> release();
}

// --------------------------------------------------------------------------

class WebOnnxBackend implements InferenceBackend {
  static const modelAsset = 'assets/models/yolov8s-pose.onnx';

  _OrtSession? _session;
  String? _inputName;
  String? _outputName;

  @override
  Future<void> load() async {
    _ortWasmPaths = 'vendor/'.toJS;
    final model = await rootBundle.load(modelAsset);
    final bytes = model.buffer.asUint8List(
        model.offsetInBytes, model.lengthInBytes);
    final session = await _createSession(bytes.toJS).toDart;
    _session = session;
    _inputName = session.inputNames.toDart.first.toDart;
    _outputName = session.outputNames.toDart.first.toDart;
  }

  @override
  Future<List<PoseDetection>> infer(VideoFrame frame) async {
    final session = _session;
    if (session == null) {
      throw StateError('load() must complete before infer()');
    }

    final (tensor, params) = preprocessLetterbox(frame);
    final input = _OrtTensor(
      'float32'.toJS,
      tensor.toJS,
      [1.toJS, 3.toJS, kYoloInputSize.toJS, kYoloInputSize.toJS].toJS,
    );
    final feeds = JSObject();
    feeds.setProperty(_inputName!.toJS, input);

    final results = await session.run(feeds).toDart;
    final output = results.getProperty<_OrtTensor>(_outputName!.toJS);
    final Float32List raw = output.data.toDart;
    // (1, 56, 8400) flattened row-major.
    final numAnchors = raw.length ~/ (5 + 3 * kYoloNumKeypoints);
    return postprocessPose(raw, params, numAnchors: numAnchors);
  }

  @override
  Future<void> dispose() async {
    final session = _session;
    _session = null;
    if (session != null) await session.release().toDart;
  }
}
