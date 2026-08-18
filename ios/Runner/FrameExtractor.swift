import AVFoundation
import Accelerate
import Flutter

/// Streams decoded video frames (RGBA) to Dart over platform channels.
///
/// MethodChannel  barbell_velocity/frame_extractor : open(path) -> metadata,
///                                                   ackFrame, close
/// EventChannel   barbell_velocity/frame_stream    : per-frame maps
///
/// Frame production is credit-gated: Dart calls `ackFrame` once it has
/// actually consumed a frame, and the reader blocks once `maxInFlight`
/// frames are unacknowledged. Without this the reader decodes as fast as
/// AVAssetReader allows while the Dart consumer (PNG encode + CoreML) runs
/// far slower; pausing a Dart subscription does not stop the platform side,
/// so the engine buffers the undelivered messages and a short 1080p clip can
/// queue gigabytes of RGBA and get the app jetsammed.
///
/// Written on Windows without an iOS toolchain — verify on a Mac.
class FrameExtractor: NSObject, FlutterStreamHandler {
  /// Frames allowed to be in flight (emitted but not yet acknowledged).
  /// Small enough to bound memory, >1 so decode and inference still overlap.
  private static let maxInFlight = 3

  private var eventSink: FlutterEventSink?

  /// Guards `reading` and `credits`, and wakes the reader thread when either
  /// changes (an ack arrives, or the stream is cancelled).
  private let gate = NSCondition()
  private var reading = false
  private var credits = 0

  /// How a track's `preferredTransform` must be applied to the raw decoded
  /// pixels so the emitted frame is upright.
  ///
  /// The transform is decomposed into an optional mirror plus a multiple of
  /// 90 degrees, which vImage can do in one pass each. A general affine warp
  /// would resample (and blur) the image; real capture transforms are always
  /// one of these eight orientations.
  private struct FrameOrientation {
    enum Mirror { case none, horizontal, vertical }

    /// One of the `kRotate*DegreesClockwise` constants.
    let rotation: UInt8
    let mirror: Mirror
    /// True for 90/270 degrees, where output width/height swap.
    let swapsDimensions: Bool

    init(transform t: CGAffineTransform) {
      // A negative determinant means the transform includes a reflection.
      // Factor it out as M = R * diag(-1, 1): a horizontal flip in *source*
      // space followed by a pure rotation R.
      let mirrored = (t.a * t.d - t.b * t.c) < 0
      let a = mirrored ? -t.a : t.a
      let b = mirrored ? -t.b : t.b

      // preferredTransform is expressed in AVFoundation's top-left-origin
      // display space, so a +90 degree rotation (b = 1, the usual portrait
      // iPhone clip) means the pixels must be turned 90 degrees clockwise.
      var quarterTurns = Int((atan2(b, a) / (.pi / 2)).rounded()) % 4
      if quarterTurns < 0 { quarterTurns += 4 }

      switch quarterTurns {
      case 1: rotation = UInt8(kRotate90DegreesClockwise)
      case 2: rotation = UInt8(kRotate180DegreesClockwise)
      case 3: rotation = UInt8(kRotate270DegreesClockwise)
      default: rotation = UInt8(kRotate0DegreesClockwise)
      }
      swapsDimensions = quarterTurns % 2 == 1

      // The flip happens before the rotation in source space; applying it
      // *after* rotating instead turns its axis by the same angle, so an odd
      // number of quarter turns makes the horizontal flip a vertical one.
      if !mirrored {
        mirror = .none
      } else {
        mirror = swapsDimensions ? .vertical : .horizontal
      }
    }
  }

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
    case "ackFrame":
      // Dart finished with a frame: let the reader produce one more.
      gate.lock()
      credits = min(credits + 1, FrameExtractor.maxInFlight)
      gate.broadcast()
      gate.unlock()
      result(nil)
    case "close":
      stopReading()
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
    gate.lock()
    reading = true
    credits = FrameExtractor.maxInFlight
    gate.broadcast()
    gate.unlock()
    DispatchQueue.global(qos: .userInitiated).async { [weak self] in
      self?.readFrames(path: path)
    }
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    stopReading()
    eventSink = nil
    return nil
  }

  /// Ends the read loop and wakes it if it is waiting for an ack.
  private func stopReading() {
    gate.lock()
    reading = false
    gate.broadcast()
    gate.unlock()
  }

  /// Blocks until a credit is available, then consumes it.
  /// Returns false if reading was cancelled while waiting.
  private func takeCredit() -> Bool {
    gate.lock()
    defer { gate.unlock() }
    while reading && credits <= 0 {
      gate.wait()
    }
    guard reading else { return false }
    credits -= 1
    return true
  }

  private var isReading: Bool {
    gate.lock()
    defer { gate.unlock() }
    return reading
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

    // Recorded orientation: applied to every frame below so Dart always sees
    // an upright image (vertical barbell travel on the vertical axis).
    let orientation = FrameOrientation(transform: track.preferredTransform)

    let output = AVAssetReaderTrackOutput(
      track: track,
      outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
    output.alwaysCopiesSampleData = false
    reader.add(output)
    reader.startReading()

    var index = 0
    while isReading, let sample = output.copyNextSampleBuffer() {
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

      // BGRA (with stride) -> upright, tightly packed RGBA.
      // One vImage rotate (which also drops the stride), an optional in-place
      // reflect for mirrored transforms, then an in-place channel permute.
      let outWidth = orientation.swapsDimensions ? height : width
      let outHeight = orientation.swapsDimensions ? width : height
      var src = vImage_Buffer(
        data: base, height: vImagePixelCount(height), width: vImagePixelCount(width),
        rowBytes: stride)
      var rgba = Data(count: outWidth * outHeight * 4)
      rgba.withUnsafeMutableBytes { (dst: UnsafeMutableRawBufferPointer) in
        let flags = vImage_Flags(kvImageNoFlags)
        var dstBuf = vImage_Buffer(
          data: dst.baseAddress, height: vImagePixelCount(outHeight),
          width: vImagePixelCount(outWidth), rowBytes: outWidth * 4)
        // kRotate0DegreesClockwise is a plain (stride-removing) copy.
        vImageRotate90_ARGB8888(&src, &dstBuf, orientation.rotation, [0, 0, 0, 0], flags)

        // Reflects and permutes below run in place: `alias` deliberately
        // describes the same memory as `dstBuf` (Swift forbids passing one
        // variable as two inout arguments).
        var alias = dstBuf
        switch orientation.mirror {
        case .horizontal:
          vImageHorizontalReflect_ARGB8888(&dstBuf, &alias, flags)
        case .vertical:
          vImageVerticalReflect_ARGB8888(&dstBuf, &alias, flags)
        case .none:
          break
        }
        let permuteMap: [UInt8] = [2, 1, 0, 3]  // BGRA -> RGBA
        vImagePermuteChannels_ARGB8888(&dstBuf, &alias, permuteMap, flags)
      }
      CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

      // Backpressure: block here (the pixel buffer is already unlocked and
      // the frame copied) until Dart has acknowledged an earlier frame.
      // Cancellation wakes this and ends the loop.
      guard takeCredit() else { break }

      emit([
        "index": index,
        "timestampS": timestamp,
        "width": outWidth,
        "height": outHeight,
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
