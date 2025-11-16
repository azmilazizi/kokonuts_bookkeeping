import 'package:flutter/widgets.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

Widget createAttachmentPdfPreview(String downloadUrl) {
  return SfPdfViewer.network(downloadUrl);
}
