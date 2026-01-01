// lib/ui/theme/skin_surface.dart
//
// Renders the fullscreen skin surface (Layer 0 of the Scaffold body stack).
// Browser-preview reference: docs/design/skins-final-browser-preview.html
//
// Per skin.surfaceRenderMode:
//  - photo     → SkinBackgroundImage + tuned scrim gradient overlay
//  - cssTeal   → Light teal radial gradients + 24px grid overlay
//  - cssSlate  → Dark gradient + cyan-dot pattern + horizontal scanline
//  - brutalist → Pure white fill

import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/character_profile.dart';
import 'package:cleona/ui/theme/skin_background_image.dart';
import 'package:cleona/ui/theme/theme_access.dart';

class SkinSurface extends StatelessWidget {
  final Widget child;
  const SkinSurface({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final character = Theme.of(context).character;

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: _Layer0(character: character)),
        if (character.surfaceRenderMode == SurfaceRenderMode.photo &&
            character.scrimGradient != null)
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(gradient: character.scrimGradient),
            ),
          ),
        Positioned.fill(child: child),
      ],
    );
  }
}

class _Layer0 extends StatelessWidget {
  final CharacterProfile character;
  const _Layer0({required this.character});

  @override
  Widget build(BuildContext context) {
    switch (character.surfaceRenderMode) {
      case SurfaceRenderMode.photo:
        return SkinBackgroundImage(
          assetPath: character.heroAssetPath,
          fallbackGradient: character.fallbackGradient,
          fit: BoxFit.cover,
        );
      case SurfaceRenderMode.cssTeal:
        return const _TealSurface();
      case SurfaceRenderMode.cssSlate:
        return const _SlateSurface();
      case SurfaceRenderMode.brutalist:
        return const ColoredBox(color: Color(0xFFFFFFFF));
    }
  }
}

/// Teal CSS surface — radial wash + 24px grid (per browser-preview .teal .bg-layer).
class _TealSurface extends StatelessWidget {
  const _TealSurface();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Color(0xFFFAFEFD), Color(0xFFE0F2F1), Color(0xFFF5FDFC)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(-0.4, -0.4),
              radius: 0.6,
              colors: [Color(0x59B2DFDB), Color(0x00B2DFDB)],
              stops: [0.0, 1.0],
            ),
          ),
        ),
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment(0.5, 0.5),
              radius: 0.55,
              colors: [Color(0x4080CBC4), Color(0x0080CBC4)],
              stops: [0.0, 1.0],
            ),
          ),
        ),
        CustomPaint(
          painter: _GridPainter(
            color: const Color(0x0A00897B),
            step: 24.0,
          ),
          size: Size.infinite,
        ),
      ],
    );
  }
}

/// Slate CSS surface — dark bg + cyan-dot pattern + subtle green scanline.
class _SlateSurface extends StatelessWidget {
  const _SlateSurface();

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF0F1419), Color(0xFF151C22), Color(0xFF0C1115)],
              stops: [0.0, 0.5, 1.0],
            ),
          ),
        ),
        CustomPaint(
          painter: _DotPainter(color: const Color(0x4000E5FF), step: 18.0, radius: 1.0),
          size: Size.infinite,
        ),
        CustomPaint(
          painter: _ScanlinePainter(color: const Color(0x0A69F0AE)),
          size: Size.infinite,
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  final Color color;
  final double step;
  _GridPainter({required this.color, required this.step});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.0;
    for (double x = 0; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter old) =>
      old.color != color || old.step != step;
}

class _DotPainter extends CustomPainter {
  final Color color;
  final double step;
  final double radius;
  _DotPainter({required this.color, required this.step, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = step / 2; y < size.height; y += step) {
      for (double x = step / 2; x < size.width; x += step) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DotPainter old) =>
      old.color != color || old.step != step || old.radius != radius;
}

class _ScanlinePainter extends CustomPainter {
  final Color color;
  _ScanlinePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ScanlinePainter old) => old.color != color;
}
