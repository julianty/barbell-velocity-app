/// Video file selection, shared by web and iOS.
library;

import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

/// A user-picked video: bytes on web, a file path on iOS.
class PickedVideo {
  final String name;
  final Uint8List? bytes;
  final String? path;

  const PickedVideo({required this.name, this.bytes, this.path});

  String get mimeType {
    final ext = name.contains('.') ? name.split('.').last.toLowerCase() : '';
    return switch (ext) {
      'mp4' || 'm4v' => 'video/mp4',
      'mov' => 'video/quicktime',
      'webm' => 'video/webm',
      'avi' => 'video/x-msvideo',
      'mkv' => 'video/x-matroska',
      _ => 'video/mp4',
    };
  }
}

/// Opens the platform file picker restricted to videos; null if cancelled.
Future<PickedVideo?> pickVideo() async {
  final result = await FilePicker.pickFiles(
    type: FileType.video,
    withData: kIsWeb, // web needs the bytes; iOS works from the path
  );
  final file = result?.files.firstOrNull;
  if (file == null) return null;
  return PickedVideo(name: file.name, bytes: file.bytes, path: file.path);
}
