import AVFoundation
import Accelerate
import Flutter

/// Streams decoded video frames (RGBA) to Dart over platform channels.
///
/// MethodChannel  barbell_velocity/frame_extractor : open(path) -> metadata
/// EventChannel   barbell_velocity/frame_stream    : per-frame maps
///
/// Written on Windows without an iOS toolchain — verify on a Mac.
class FrameExtractor: NSObject, FlutterStreamHandler {
  private var eventSink: FlutterEventSink?
  private var reading = false

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = FrameExtractor()
    let method = FlutterMethodChannel(
      name: "barbell_velocity/frame_extractor",
      binaryMessenger: registrar.messenger())
    let events = FlutterEventChannel(
      name: "barbell_velocity/frame_stream",
      binaryMessenger: registrar.messenger())
    method.setMethodCallHandler(instance.handle)
    events.setStreamHandler(instance)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      guard let args = call.arguments as? [String: Any],
        let path = args["path"] as? String
      else {
        result(FlutterError(code: "bad_args", message: "path required", details: nil))
        return
      }
      let asset = AVURLAsset(url: URL(fileURLWithPath: path))
      guard let track = asset.tracks(withMediaType: .video).first else {
        result(FlutterError(code: "no_video_track", message: "No video track in \(path)", details: nil))
        return
      }
      let size = track.naturalSize.applying(track.preferredTransform)
      result([
        "fps": Double(track.nominalFrameRate),
        "durationS": CMTimeGetSeconds(asset.duration),
        "width": Int(abs(size.width)),
        "height": Int(abs(size.height)),
      ])
    case "close":
      reading = false
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink)
    -> FlutterError?
  {
    guard let args = arguments as? [String: Any], let path = args["path"] as? String else {
      return FlutterError(code: "bad_args", message: "path required", details: nil)
    }
    eventSink = events
    reading = true
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.readFrames(path: path)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    reading = false
    eventSink = nil
    return nil
  }

  private func emit(_ value: Any) {
    DispatchQueue.main.async { [weak self] in
      self?.eventSink?(value)
    }
  }

  private func readFrames(path: String) {
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    guard let track = asset.tracks(withMediaType: .video).first,
      let reader = try? AVAssetReader(asset: asset)
    else {
      emit(FlutterError(code: "reader_init", message: "Cannot open \(path)", details: nil))
      emit(FlutterEndOfEventStream)
      return
    }

    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    reader.startReading()

    var index = 0
    while reading, let sample = output.copyNextSampleBuffer() {
      guard let pixelBuffer = CMSampleBufferGetImageBuffer(sample) else { continue }
      let timestamp = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample))

      CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
      let width = CVPixelBufferGetWidth(pixelBuffer)
      let height = CVPixelBufferGetHeight(pixelBuffer)
      let stride = CVPixelBufferGetBytesPerRow(pixelBuffer)
      guard let base = CVPixelBufferGetBaseAddress(pixelBuffer) else {
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)
        continue
      }

      // BGRA (with stride) -> tightly packed RGBA via vImage channel permute.
      var src = vImage_Buffer(
        data: base, height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: stride)
      var rgba = Data(count: width * height * 4)
      rgba.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
        var dstBuf = vImage_Buffer(
          data: dst.baseAddress, height: vImagePixelCount(height),
          width: vImagePixelCount(width), rowBytes: width * 4)
        let permuteMap: [UInt8] = [2, 1, 0, 3]  // BGRA -> RGBA
        vImagePermuteChannels_ARGB8888(&src, &dstBuf, permuteMap, vImage_Flags(kvImageNoFlags))
      }
      CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

      emit([
        "index": index,
        "timestampS": timestamp,
        "width": width,
        "height": height,
        "rgba": FlutterStandardTypedData(bytes: rgba),
      ])
      index += 1
    }

    if reader.status == .failed {
      emit(FlutterError(
        code: "reader_failed",
        message: reader.error?.localizedDescription ?? "unknown", details: nil))
    }
    emit(FlutterEndOfEventStream)
  }
}
