import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:kokonuts_bookkeeping/utils/platform_file_loader_io.dart';

void main() {
  test('platformFileToBytes prefers path over readStream', () async {
    final tempDir = await Directory.systemTemp.createTemp('po-attach-test');
    final tempFile = File('${tempDir.path}/attachment.txt');
    const expected = 'attachment-content';
    await tempFile.writeAsString(expected);

    final file = PlatformFile(
      name: 'attachment.txt',
      size: expected.length,
      path: tempFile.path,
      readStream: Stream<List<int>>.error(
        StateError('readStream should not be consumed when path is available'),
      ),
    );

    final bytes = await platformFileToBytes(file);

    expect(bytes, isNotNull);
    expect(String.fromCharCodes(bytes!), expected);

    await tempDir.delete(recursive: true);
  });
}
