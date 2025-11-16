// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

Widget createAttachmentPdfPreview(String downloadUrl) {
  return _HtmlPdfPreview(downloadUrl: downloadUrl);
}

class _HtmlPdfPreview extends StatefulWidget {
  const _HtmlPdfPreview({required this.downloadUrl});

  final String downloadUrl;

  @override
  State<_HtmlPdfPreview> createState() => _HtmlPdfPreviewState();
}

class _HtmlPdfPreviewState extends State<_HtmlPdfPreview> {
  late final String _viewType;
  html.IFrameElement? _iframe;

  @override
  void initState() {
    super.initState();
    _viewType = 'attachment-pdf-preview-${DateTime.now().microsecondsSinceEpoch}-${hashCode}';
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      _iframe = html.IFrameElement()
        ..src = widget.downloadUrl
        ..style.border = 'none'
        ..style.width = '100%'
        ..style.height = '100%'
        ..allow = 'fullscreen'
        ..setAttribute('loading', 'lazy');
      return _iframe!;
    });
  }

  @override
  void didUpdateWidget(covariant _HtmlPdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.downloadUrl != oldWidget.downloadUrl) {
      _iframe?.src = widget.downloadUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
