import 'package:flutter/material.dart';

Widget buildPlatformImage(
  String imageUrl, {
  BoxFit? fit,
  Widget Function(BuildContext, Widget, ImageChunkEvent?)? loadingBuilder,
  Widget Function(BuildContext, Object, StackTrace?)? errorBuilder,
}) {
  return Image.network(
    imageUrl,
    fit: fit,
    loadingBuilder: loadingBuilder,
    errorBuilder: errorBuilder,
  );
}

const bool isWebPlatform = false;
