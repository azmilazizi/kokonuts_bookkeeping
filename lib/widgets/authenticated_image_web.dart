// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
import 'dart:ui_web' as ui;

import 'package:flutter/material.dart';

Widget buildPlatformImage(
  String imageUrl, {
  BoxFit? fit,
  Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return _HtmlImagePreview(
    imageUrl: imageUrl,
    fit: fit,
    loadingBuilder: loadingBuilder,
    errorBuilder: errorBuilder,
  );
}

const bool isWebPlatform = true;

class _HtmlImagePreview extends StatefulWidget {
  const _HtmlImagePreview({
    required this.imageUrl,
    this.fit,
    this.loadingBuilder,
    this.errorBuilder,
  });

  final String imageUrl;
  final BoxFit? fit;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;

  @override
  State<_HtmlImagePreview> createState() => _HtmlImagePreviewState();
}

class _HtmlImagePreviewState extends State<_HtmlImagePreview> {
  late final String _viewType;
  html.ImageElement? _image;
  bool _hasLoaded = false;
  Object? _error;

  @override
  void initState() {
    super.initState();
    _viewType =
        'attachment-image-preview-${DateTime.now().microsecondsSinceEpoch}-${hashCode}';

    ui.platformViewRegistry.registerViewFactory(_viewType, (int viewId) {
      _image = html.ImageElement()
        ..src = widget.imageUrl
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = _mapFit(widget.fit)
        ..style.display = 'block';

      _image!.onLoad.listen((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _hasLoaded = true;
          _error = null;
        });
      });

      _image!.onError.listen((_) {
        if (!mounted) {
          return;
        }
        setState(() {
          _error = 'Unable to load image preview.';
        });
      });

      return _image!;
    });
  }

  @override
  void didUpdateWidget(covariant _HtmlImagePreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl) {
      setState(() {
        _hasLoaded = false;
        _error = null;
      });
      _image?.src = widget.imageUrl;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      if (widget.errorBuilder != null) {
        return widget.errorBuilder!(context, _error!, null);
      }
      return const Center(child: Icon(Icons.error));
    }

    final imageView = HtmlElementView(viewType: _viewType);

    if (_hasLoaded || widget.loadingBuilder == null) {
      return imageView;
    }

    return Stack(
      fit: StackFit.expand,
      children: [
        imageView,
        widget.loadingBuilder!(context, const SizedBox(), null),
      ],
    );
  }

  String _mapFit(BoxFit? fit) {
    switch (fit) {
      case BoxFit.cover:
        return 'cover';
      case BoxFit.fill:
        return 'fill';
      case BoxFit.fitHeight:
        return 'contain';
      case BoxFit.fitWidth:
        return 'contain';
      case BoxFit.none:
        return 'none';
      case BoxFit.scaleDown:
        return 'scale-down';
      case BoxFit.contain:
      default:
        return 'contain';
    }
  }
}
