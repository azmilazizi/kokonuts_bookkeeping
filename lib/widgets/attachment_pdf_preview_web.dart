// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:typed_data';
import 'dart:ui_web' as ui;

import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

Widget createAttachmentPdfPreview(
  String downloadUrl, {
  Map<String, String>? headers,
}) {
  return _HtmlPdfPreview(downloadUrl: downloadUrl, headers: headers);
}

Widget createAttachmentPdfPreviewFromBytes(Uint8List bytes) {
  return _HtmlBytesPdfPreview(bytes: bytes);
}

class _HtmlPdfPreview extends StatefulWidget {
  const _HtmlPdfPreview({required this.downloadUrl, this.headers});

  final String downloadUrl;
  final Map<String, String>? headers;

  @override
  State<_HtmlPdfPreview> createState() => _HtmlPdfPreviewState();
}

class _HtmlPdfPreviewState extends State<_HtmlPdfPreview> {
  late final String _viewType;
  late final html.IFrameElement _iframe;
  String? _blobUrl;
  int _loadRequestId = 0;

  @override
  void initState() {
    super.initState();
    _viewType =
        'attachment-pdf-preview-${DateTime.now().microsecondsSinceEpoch}-${hashCode}';

    _iframe = html.IFrameElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'fullscreen'
      ..setAttribute('loading', 'lazy');

    // Register the view factory immediately with a pre-created iframe so that
    // async PDF loading can always update a concrete element.
    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _iframe;
    });

    if (widget.headers != null && widget.headers!.isNotEmpty) {
      _loadPdf();
    } else {
      _iframe.src = widget.downloadUrl;
    }
  }

  @override
  void didUpdateWidget(covariant _HtmlPdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.downloadUrl != oldWidget.downloadUrl ||
        widget.headers != oldWidget.headers) {
      if (widget.headers != null && widget.headers!.isNotEmpty) {
        _revokeBlob();
        _loadPdf();
      } else {
        _revokeBlob();
        _iframe.src = widget.downloadUrl;
      }
    }
  }

  @override
  void dispose() {
    _revokeBlob();
    super.dispose();
  }

  void _revokeBlob() {
    if (_blobUrl != null) {
      html.Url.revokeObjectUrl(_blobUrl!);
      _blobUrl = null;
    }
  }

  Future<void> _loadPdf() async {
    final requestId = ++_loadRequestId;
    try {
      final response = await http.get(
        Uri.parse(widget.downloadUrl),
        headers: widget.headers,
      );

      if (!mounted || requestId != _loadRequestId) {
        return;
      }

      if (response.statusCode == 200) {
        final blob = html.Blob([response.bodyBytes], 'application/pdf');
        final oldBlobUrl = _blobUrl;
        final nextBlobUrl = html.Url.createObjectUrlFromBlob(blob);
        _blobUrl = nextBlobUrl;
        _iframe.src = nextBlobUrl;
        if (oldBlobUrl != null) {
          html.Url.revokeObjectUrl(oldBlobUrl);
        }
      } else {
        // Fallback or error handling
        // For now, if fetch fails, maybe try direct load?
        _iframe.src = widget.downloadUrl;
      }
    } catch (e) {
      // If error (e.g. CORS), fallback to direct URL
      if (!mounted || requestId != _loadRequestId) {
        return;
      }
      _iframe.src = widget.downloadUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}

class _HtmlBytesPdfPreview extends StatefulWidget {
  const _HtmlBytesPdfPreview({required this.bytes});

  final Uint8List bytes;

  @override
  State<_HtmlBytesPdfPreview> createState() => _HtmlBytesPdfPreviewState();
}

class _HtmlBytesPdfPreviewState extends State<_HtmlBytesPdfPreview> {
  late final String _viewType;
  late final html.IFrameElement _iframe;
  String? _blobUrl;

  @override
  void initState() {
    super.initState();
    _viewType =
        'attachment-bytes-pdf-preview-${DateTime.now().microsecondsSinceEpoch}-$hashCode';

    final blob = html.Blob([widget.bytes], 'application/pdf');
    _blobUrl = html.Url.createObjectUrlFromBlob(blob);

    _iframe = html.IFrameElement()
      ..style.border = 'none'
      ..style.width = '100%'
      ..style.height = '100%'
      ..allow = 'fullscreen'
      ..src = _blobUrl!;

    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      return _iframe;
    });
  }

  @override
  void dispose() {
    if (_blobUrl != null) {
      html.Url.revokeObjectUrl(_blobUrl!);
      _blobUrl = null;
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return HtmlElementView(viewType: _viewType);
  }
}
