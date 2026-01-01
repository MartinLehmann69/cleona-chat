// lib/ui/theme/skin_background_image.dart
import 'package:flutter/material.dart';

/// Renders a skin's hero image, falling back to gradient on load failure or
/// when no asset path is configured (CSS-only skins).
class SkinBackgroundImage extends StatelessWidget {
  final String? assetPath;
  final LinearGradient? fallbackGradient;
  final BoxFit fit;
  final Widget? child;

  const SkinBackgroundImage({
    super.key,
    required this.assetPath,
    required this.fallbackGradient,
    this.fit = BoxFit.cover,
    this.child,
  });

  @override
  Widget build(BuildContext context) {
    if (assetPath == null) {
      return _gradientBox(child);
    }
    return Image.asset(
      assetPath!,
      fit: fit,
      errorBuilder: (ctx, err, stack) => _gradientBox(child),
    );
  }

  Widget _gradientBox(Widget? child) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: fallbackGradient,
        color: fallbackGradient == null ? Colors.grey.shade200 : null,
      ),
      child: child,
    );
  }
}
