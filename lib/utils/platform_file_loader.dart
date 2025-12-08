import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'platform_file_loader_io.dart'
    if (dart.library.html) 'platform_file_loader_web.dart';

Future<Uint8List?> loadPlatformFileBytes(PlatformFile file) {
  return platformFileToBytes(file);
}
