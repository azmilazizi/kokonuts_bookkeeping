import 'package:flutter/material.dart';

import '../widgets/app_logo.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final isShortScreen = mediaQuery.size.height < 700;
    final verticalOffset = isShortScreen ? -32.0 : 0.0;

    return Scaffold(
      body: Center(
        child: Transform.translate(
          offset: Offset(0, verticalOffset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppLogo(size: 120),
              const SizedBox(height: 24),
              const CircularProgressIndicator(),
            ],
          ),
        ),
      ),
    );
  }
}
