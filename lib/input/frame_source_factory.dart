/// Platform-dispatching FrameSource constructor.
library;

import 'frame_source.dart';
import 'video_picker.dart';

import 'frame_source_stub.dart'
    if (dart.library.js_interop) 'web_frame_source.dart'
    if (dart.library.io) 'ios_frame_source.dart';

FrameSource createFrameSource(PickedVideo video) =>
    createFrameSourceImpl(video);
