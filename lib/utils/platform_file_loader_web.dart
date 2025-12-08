import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

Future<Uint8List?> platformFileToBytes(PlatformFile file) async {
  if (file.bytes != null) return file.bytes;

  if (file.readStream != null) {
    final builder = BytesBuilder();
    await for (final chunk in file.readStream!) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  return null;
}
