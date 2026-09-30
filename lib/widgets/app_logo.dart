import 'package:flutter/material.dart';

// The dark variant was identical to the light one and has been removed,
// so both themes use the same logo.
String _resolveAppLogoAsset(BuildContext context) =>
    'assets/images/app_logo_light.png';

/// Displays the application logo, automatically adapting to the active theme.
class AppLogo extends StatelessWidget {
  const AppLogo({
    super.key,
    this.size,
    this.height,
    this.width,
  });

  final double? size;
  final double? height;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final resolvedHeight = height ?? size;
    final resolvedWidth = width ?? size;

    return Image.asset(
      _resolveAppLogoAsset(context),
      height: resolvedHeight,
      width: resolvedWidth,
    );
  }
}
