/// Fallback for platforms without a FrameSource implementation
/// (selected by the conditional import in frame_source_factory.dart).
library;

import 'frame_source.dart';
import 'video_picker.dart';

FrameSource createFrameSourceImpl(PickedVideo video) =>
    throw UnsupportedError('No FrameSource implementation for this platform');
