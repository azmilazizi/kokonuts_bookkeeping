import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'authenticated_image_io.dart'
    if (dart.library.html) 'authenticated_image_web.dart';

class AuthenticatedImage extends StatefulWidget {
  final String imageUrl;
  final Map<String, String>? headers;
  final BoxFit? fit;
  final Widget Function(BuildContext, Object, StackTrace?)? errorBuilder;
  final Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder;

  const AuthenticatedImage({
    super.key,
    required this.imageUrl,
    this.headers,
    this.fit,
    this.errorBuilder,
    this.loadingBuilder,
  });

  @override
  State<AuthenticatedImage> createState() => _AuthenticatedImageState();
}

class _AuthenticatedImageState extends State<AuthenticatedImage> {
  Future<Uint8List>? _imageFuture;

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(AuthenticatedImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.imageUrl != oldWidget.imageUrl ||
        widget.headers != oldWidget.headers) {
      _loadImage();
    }
  }

  void _loadImage() {
    if (_canUsePlatformImage) {
      _imageFuture = null;
      return;
    }
    _imageFuture = _fetchImage();
  }

  Future<Uint8List> _fetchImage() async {
    final response = await http.get(
      Uri.parse(widget.imageUrl),
      headers: widget.headers,
    );

    if (response.statusCode == 200) {
      return response.bodyBytes;
    } else {
      throw Exception('Failed to load image: ${response.statusCode}');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_canUsePlatformImage) {
      return buildPlatformImage(
        _resolvedImageUrlForWeb ?? widget.imageUrl,
        fit: widget.fit,
        loadingBuilder: widget.loadingBuilder,
        errorBuilder: widget.errorBuilder,
      );
    }
    return FutureBuilder<Uint8List>(
      future: _imageFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          if (widget.loadingBuilder != null) {
            return widget.loadingBuilder!(
              context,
              const SizedBox(),
              null, // No progress info available for http.get bodyBytes
            );
          }
          return const Center(child: CircularProgressIndicator());
        } else if (snapshot.hasError) {
          if (widget.errorBuilder != null) {
            return widget.errorBuilder!(context, snapshot.error!, null);
          }
          return const Center(child: Icon(Icons.error));
        } else if (snapshot.hasData) {
          return Image.memory(
            snapshot.data!,
            fit: widget.fit,
            errorBuilder: widget.errorBuilder,
          );
        }
        return const SizedBox();
      },
    );
  }

  bool get _canUsePlatformImage =>
      isWebPlatform ||
      (widget.headers == null || widget.headers!.isEmpty);

  String? get _resolvedImageUrlForWeb {
    if (!isWebPlatform) {
      return null;
    }

    final authKey = _extractAuthKey(widget.headers);
    if (authKey == null || authKey.isEmpty) {
      return null;
    }

    final uri = Uri.tryParse(widget.imageUrl);
    if (uri == null) {
      return null;
    }

    if (uri.queryParameters.containsKey('authkey')) {
      return widget.imageUrl;
    }

    final updatedQuery = Map<String, String>.from(uri.queryParameters);
    updatedQuery['authkey'] = authKey;
    return uri.replace(queryParameters: updatedQuery).toString();
  }

  String? _extractAuthKey(Map<String, String>? headers) {
    if (headers == null || headers.isEmpty) {
      return null;
    }

    final authtoken =
        headers['authtoken'] ?? headers['Authtoken'] ?? headers['authToken'];
    if (authtoken != null && authtoken.trim().isNotEmpty) {
      return authtoken.trim();
    }

    final authorization =
        headers['Authorization'] ?? headers['authorization'] ?? '';
    if (authorization.trim().isEmpty) {
      return null;
    }

    final normalized = authorization
        .replaceFirst(RegExp('^Bearer\\s+', caseSensitive: false), '')
        .trim();
    return normalized.isEmpty ? null : normalized;
  }
}
