import 'dart:math';
import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/skins.dart';

/// Custom painter for chat background patterns per skin.
/// Patterns are very subtle — low opacity, decorative only.
class SkinBackgroundPainter extends CustomPainter {
  final String skinId;
  final Color patternColor;

  SkinBackgroundPainter({
    required this.skinId,
    required this.patternColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (skinId) {
      case 'ocean':
        _paintWaves(canvas, size);
        break;
      case 'forest':
        _paintLeaves(canvas, size);
        break;
      case 'amethyst':
        _paintCrystalline(canvas, size);
        break;
      case 'crimson':
        _paintDiagonalLines(canvas, size);
        break;
      case 'slate':
        _paintDotGrid(canvas, size);
        break;
      case 'gold':
        _paintOrnaments(canvas, size);
        break;
      case 'sunset':
        _paintHorizontalStripes(canvas, size);
        break;
      // teal and contrast: no pattern
    }
  }

  /// Ocean: wave lines flowing horizontally.
  void _paintWaves(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = patternColor.withValues(alpha: 0.15)
      ..strokeWidth = 1.8
      ..style = PaintingStyle.stroke;

    for (var y = 40.0; y < size.height; y += 60) {
      final path = Path();
      path.moveTo(0, y);
      for (var x = 0.0; x < size.width; x += 80) {
        path.quadraticBezierTo(
          x + 20, y - 12,
          x + 40, y,
        );
        path.quadraticBezierTo(
          x + 60, y + 12,
          x + 80, y,
        );
      }
      canvas.drawPath(path, paint);
    }
  }

  /// Forest: leaf-like shapes scattered.
  void _paintLeaves(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = patternColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rng = Random(42); // deterministic pattern
    for (var i = 0; i < 20; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final leafSize = 12.0 + rng.nextDouble() * 8;
      final angle = rng.nextDouble() * pi;

      canvas.save();
      canvas.translate(cx, cy);
      canvas.rotate(angle);

      final path = Path();
      path.moveTo(0, -leafSize);
      path.quadraticBezierTo(leafSize * 0.6, -leafSize * 0.3, 0, leafSize);
      path.quadraticBezierTo(-leafSize * 0.6, -leafSize * 0.3, 0, -leafSize);
      canvas.drawPath(path, paint);

      // Leaf vein
      canvas.drawLine(Offset(0, -leafSize), Offset(0, leafSize), paint);

      canvas.restore();
    }
  }

  /// Amethyst: geometric crystalline pattern.
  void _paintCrystalline(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = patternColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final rng = Random(7);
    for (var i = 0; i < 15; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final crystalSize = 15.0 + rng.nextDouble() * 20;
      final sides = 5 + rng.nextInt(3); // 5-7 sided

      final path = Path();
      for (var s = 0; s <= sides; s++) {
        final a = (2 * pi / sides) * s - pi / 2;
        final r = crystalSize * (0.7 + 0.3 * ((s % 2 == 0) ? 1.0 : 0.6));
        final px = cx + r * cos(a);
        final py = cy + r * sin(a);
        if (s == 0) {
          path.moveTo(px, py);
        } else {
          path.lineTo(px, py);
        }
      }
      path.close();
      canvas.drawPath(path, paint);

      // Inner lines to center
      for (var s = 0; s < sides; s++) {
        final a = (2 * pi / sides) * s - pi / 2;
        final r = crystalSize * (0.7 + 0.3 * ((s % 2 == 0) ? 1.0 : 0.6));
        canvas.drawLine(
          Offset(cx, cy),
          Offset(cx + r * cos(a), cy + r * sin(a)),
          paint,
        );
      }
    }
  }

  /// Crimson: diagonal lines.
  void _paintDiagonalLines(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = patternColor.withValues(alpha: 0.12)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    const spacing = 30.0;
    final maxDim = size.width + size.height;
    for (var d = -size.height; d < maxDim; d += spacing) {
      canvas.drawLine(
        Offset(d, 0),
        Offset(d + size.height, size.height),
        paint,
      );
    }
  }

  /// Slate: dot grid (technical, developer-style).
  void _paintDotGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = patternColor.withValues(alpha: 0.18)
      ..style = PaintingStyle.fill;

    const spacing = 24.0;
    const radius = 1.5;
    for (var x = spacing; x < size.width; x += spacing) {
      for (var y = spacing; y < size.height; y += spacing) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  /// Gold: curved ornaments.
  void _paintOrnaments(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = patternColor.withValues(alpha: 0.12)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    final rng = Random(13);
    for (var i = 0; i < 12; i++) {
      final cx = rng.nextDouble() * size.width;
      final cy = rng.nextDouble() * size.height;
      final r = 10.0 + rng.nextDouble() * 15;
      final startAngle = rng.nextDouble() * 2 * pi;

      final path = Path();
      // Draw a decorative swirl
      for (var t = 0.0; t < 2 * pi; t += 0.1) {
        final radius = r * (1 + 0.3 * sin(3 * t));
        final x = cx + radius * cos(t + startAngle);
        final y = cy + radius * sin(t + startAngle);
        if (t == 0) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  /// Sunset: horizontal stripes like a horizon.
  void _paintHorizontalStripes(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (var y = 80.0; y < size.height; y += 50) {
      final alpha = 0.08 + 0.06 * sin(y / size.height * pi);
      paint.color = patternColor.withValues(alpha: alpha);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(SkinBackgroundPainter oldDelegate) =>
      skinId != oldDelegate.skinId || patternColor != oldDelegate.patternColor;
}

/// Paints a subtle watermark motif in the bottom-right corner of the chat area.
/// Each skin has its own motif; teal, slate, and contrast have none.
class SkinWatermarkPainter extends CustomPainter {
  final String skinId;
  final Color watermarkColor;

  SkinWatermarkPainter({
    required this.skinId,
    required this.watermarkColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Position: bottom-right with padding
    final cx = size.width - 60;
    final cy = size.height - 60;

    switch (skinId) {
      case 'ocean':
        _paintWave(canvas, cx, cy);
        break;
      case 'sunset':
        _paintSun(canvas, cx, cy);
        break;
      case 'forest':
        _paintLeaf(canvas, cx, cy);
        break;
      case 'amethyst':
        _paintCrystal(canvas, cx, cy);
        break;
      case 'crimson':
        _paintBolt(canvas, cx, cy);
        break;
      case 'gold':
        _paintStar(canvas, cx, cy);
        break;
      // teal, slate, contrast: no watermark
    }
  }

  Paint get _paint => Paint()
    ..color = watermarkColor.withValues(alpha: 0.15)
    ..style = PaintingStyle.stroke
    ..strokeWidth = 2.0
    ..strokeCap = StrokeCap.round;

  /// Ocean: stylized wave
  void _paintWave(Canvas canvas, double cx, double cy) {
    final paint = _paint;
    final path = Path();
    path.moveTo(cx - 30, cy);
    path.quadraticBezierTo(cx - 15, cy - 14, cx, cy);
    path.quadraticBezierTo(cx + 15, cy + 14, cx + 30, cy);
    canvas.drawPath(path, paint);
    // Second wave below
    final path2 = Path();
    path2.moveTo(cx - 25, cy + 10);
    path2.quadraticBezierTo(cx - 10, cy - 2, cx + 5, cy + 10);
    path2.quadraticBezierTo(cx + 18, cy + 20, cx + 25, cy + 10);
    canvas.drawPath(path2, paint);
  }

  /// Sunset: stylized sun / half circle with rays
  void _paintSun(Canvas canvas, double cx, double cy) {
    final paint = _paint;
    // Half circle (horizon)
    final rect = Rect.fromCircle(center: Offset(cx, cy + 8), radius: 18);
    canvas.drawArc(rect, pi, pi, false, paint);
    // Horizon line
    canvas.drawLine(Offset(cx - 28, cy + 8), Offset(cx + 28, cy + 8), paint);
    // Rays above
    for (var i = 0; i < 5; i++) {
      final angle = pi + (pi / 6) * (i - 2);
      final x1 = cx + 22 * cos(angle);
      final y1 = cy + 8 + 22 * sin(angle);
      final x2 = cx + 32 * cos(angle);
      final y2 = cy + 8 + 32 * sin(angle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), paint);
    }
  }

  /// Forest: stylized leaf
  void _paintLeaf(Canvas canvas, double cx, double cy) {
    final paint = _paint;
    final path = Path();
    // Leaf outline
    path.moveTo(cx, cy - 25);
    path.quadraticBezierTo(cx + 18, cy - 10, cx, cy + 25);
    path.quadraticBezierTo(cx - 18, cy - 10, cx, cy - 25);
    canvas.drawPath(path, paint);
    // Center vein
    canvas.drawLine(Offset(cx, cy - 25), Offset(cx, cy + 25), paint);
    // Side veins
    for (final dy in [-10.0, 0.0, 10.0]) {
      final spread = 8.0 - dy.abs() * 0.3;
      canvas.drawLine(Offset(cx, cy + dy), Offset(cx - spread, cy + dy - 5), paint);
      canvas.drawLine(Offset(cx, cy + dy), Offset(cx + spread, cy + dy - 5), paint);
    }
  }

  /// Amethyst: stylized crystal / gem
  void _paintCrystal(Canvas canvas, double cx, double cy) {
    final paint = _paint;
    // Outer hexagonal gem shape
    final path = Path();
    path.moveTo(cx, cy - 25); // top
    path.lineTo(cx + 18, cy - 10);
    path.lineTo(cx + 18, cy + 10);
    path.lineTo(cx, cy + 25); // bottom
    path.lineTo(cx - 18, cy + 10);
    path.lineTo(cx - 18, cy - 10);
    path.close();
    canvas.drawPath(path, paint);
    // Inner facets — lines from top to bottom corners
    canvas.drawLine(Offset(cx, cy - 25), Offset(cx + 18, cy + 10), paint);
    canvas.drawLine(Offset(cx, cy - 25), Offset(cx - 18, cy + 10), paint);
    // Horizontal facet line
    canvas.drawLine(Offset(cx - 18, cy - 10), Offset(cx + 18, cy - 10), paint);
  }

  /// Crimson: stylized lightning bolt
  void _paintBolt(Canvas canvas, double cx, double cy) {
    final paint = _paint;
    final path = Path();
    path.moveTo(cx + 5, cy - 28);
    path.lineTo(cx - 8, cy - 2);
    path.lineTo(cx + 2, cy - 2);
    path.lineTo(cx - 5, cy + 28);
    path.lineTo(cx + 10, cy + 2);
    path.lineTo(cx, cy + 2);
    path.close();
    canvas.drawPath(path, paint);
  }

  /// Gold: stylized 5-pointed star
  void _paintStar(Canvas canvas, double cx, double cy) {
    final paint = _paint;
    final path = Path();
    const points = 5;
    const outerR = 24.0;
    const innerR = 10.0;
    for (var i = 0; i < points * 2; i++) {
      final angle = (pi / points) * i - pi / 2;
      final r = i.isEven ? outerR : innerR;
      final x = cx + r * cos(angle);
      final y = cy + r * sin(angle);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(SkinWatermarkPainter oldDelegate) =>
      skinId != oldDelegate.skinId || watermarkColor != oldDelegate.watermarkColor;
}

/// Themed add-button widget per skin.
/// Each skin paints a unique shape with a "+" inside.
class SkinAddButton extends StatelessWidget {
  final String skinId;
  final Color color;
  final VoidCallback onTap;
  final double size;

  const SkinAddButton({
    super.key,
    required this.skinId,
    required this.color,
    required this.onTap,
    this.size = 28.0,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: CustomPaint(
            size: Size(size, size),
            painter: _SkinAddButtonPainter(skinId: skinId, color: color),
          ),
        ),
      ),
    );
  }
}

class _SkinAddButtonPainter extends CustomPainter {
  final String skinId;
  final Color color;

  _SkinAddButtonPainter({required this.skinId, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 1;

    switch (skinId) {
      case 'ocean':
        _paintShell(canvas, cx, cy, r);
        break;
      case 'sunset':
        _paintSun(canvas, cx, cy, r);
        break;
      case 'forest':
        _paintLeaf(canvas, cx, cy, r);
        break;
      case 'amethyst':
        _paintCrystal(canvas, cx, cy, r);
        break;
      case 'crimson':
        _paintFlame(canvas, cx, cy, r);
        break;
      case 'slate':
        _paintChip(canvas, cx, cy, r);
        break;
      case 'gold':
        _paintBar(canvas, cx, cy, r);
        break;
      case 'contrast':
        _paintBold(canvas, cx, cy, r);
        break;
      default: // teal
        _paintDefault(canvas, cx, cy, r);
        break;
    }

    // Draw "+" on top
    _drawPlus(canvas, cx, cy, r * 0.45);
  }

  Paint get _fill => Paint()
    ..color = color.withValues(alpha: 0.15)
    ..style = PaintingStyle.fill;

  Paint get _stroke => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = 1.5
    ..strokeCap = StrokeCap.round;

  void _drawPlus(Canvas canvas, double cx, double cy, double arm) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - arm, cy), Offset(cx + arm, cy), paint);
    canvas.drawLine(Offset(cx, cy - arm), Offset(cx, cy + arm), paint);
  }

  /// Teal: clean rounded tab
  void _paintDefault(Canvas canvas, double cx, double cy, double r) {
    final rect = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset(cx, cy), width: r * 2, height: r * 1.7),
      Radius.circular(r * 0.5),
    );
    canvas.drawRRect(rect, _fill);
    canvas.drawRRect(rect, _stroke);
  }

  /// Ocean: shell / droplet shape
  void _paintShell(Canvas canvas, double cx, double cy, double r) {
    final path = Path();
    path.moveTo(cx, cy - r); // top
    path.quadraticBezierTo(cx + r * 1.2, cy - r * 0.3, cx + r * 0.8, cy + r * 0.5);
    path.quadraticBezierTo(cx + r * 0.3, cy + r * 1.1, cx, cy + r);
    path.quadraticBezierTo(cx - r * 0.3, cy + r * 1.1, cx - r * 0.8, cy + r * 0.5);
    path.quadraticBezierTo(cx - r * 1.2, cy - r * 0.3, cx, cy - r);
    path.close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
  }

  /// Sunset: sun with small rays
  void _paintSun(Canvas canvas, double cx, double cy, double r) {
    // Inner circle
    canvas.drawCircle(Offset(cx, cy), r * 0.55, _fill);
    canvas.drawCircle(Offset(cx, cy), r * 0.55, _stroke);
    // Rays
    final rayPaint = _stroke..strokeWidth = 1.2;
    for (var i = 0; i < 8; i++) {
      final angle = (pi / 4) * i;
      final x1 = cx + r * 0.7 * cos(angle);
      final y1 = cy + r * 0.7 * sin(angle);
      final x2 = cx + r * 0.95 * cos(angle);
      final y2 = cy + r * 0.95 * sin(angle);
      canvas.drawLine(Offset(x1, y1), Offset(x2, y2), rayPaint);
    }
  }

  /// Forest: leaf shape
  void _paintLeaf(Canvas canvas, double cx, double cy, double r) {
    final path = Path();
    path.moveTo(cx, cy - r);
    path.quadraticBezierTo(cx + r * 1.1, cy - r * 0.2, cx, cy + r);
    path.quadraticBezierTo(cx - r * 1.1, cy - r * 0.2, cx, cy - r);
    path.close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
    // Center vein
    final veinPaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx, cy - r * 0.6), Offset(cx, cy + r * 0.6), veinPaint);
  }

  /// Amethyst: crystal / gem shape (hexagonal)
  void _paintCrystal(Canvas canvas, double cx, double cy, double r) {
    final path = Path();
    // Hexagonal gem with pointed top and bottom
    path.moveTo(cx, cy - r); // top point
    path.lineTo(cx + r * 0.85, cy - r * 0.35);
    path.lineTo(cx + r * 0.85, cy + r * 0.35);
    path.lineTo(cx, cy + r); // bottom point
    path.lineTo(cx - r * 0.85, cy + r * 0.35);
    path.lineTo(cx - r * 0.85, cy - r * 0.35);
    path.close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
    // Facet line
    final facetPaint = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..strokeWidth = 0.8
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(cx - r * 0.85, cy - r * 0.35), Offset(cx + r * 0.85, cy - r * 0.35), facetPaint);
  }

  /// Crimson: flame / fire shape
  void _paintFlame(Canvas canvas, double cx, double cy, double r) {
    final path = Path();
    path.moveTo(cx, cy - r); // tip
    path.quadraticBezierTo(cx + r * 0.9, cy - r * 0.2, cx + r * 0.6, cy + r * 0.4);
    path.quadraticBezierTo(cx + r * 0.4, cy + r * 0.9, cx, cy + r * 0.7);
    path.quadraticBezierTo(cx - r * 0.4, cy + r * 0.9, cx - r * 0.6, cy + r * 0.4);
    path.quadraticBezierTo(cx - r * 0.9, cy - r * 0.2, cx, cy - r);
    path.close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
  }

  /// Slate: microchip / bracket shape
  void _paintChip(Canvas canvas, double cx, double cy, double r) {
    // Square with notched corners
    final s = r * 0.85;
    final notch = r * 0.25;
    final path = Path();
    path.moveTo(cx - s + notch, cy - s);
    path.lineTo(cx + s - notch, cy - s);
    path.lineTo(cx + s, cy - s + notch);
    path.lineTo(cx + s, cy + s - notch);
    path.lineTo(cx + s - notch, cy + s);
    path.lineTo(cx - s + notch, cy + s);
    path.lineTo(cx - s, cy + s - notch);
    path.lineTo(cx - s, cy - s + notch);
    path.close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
    // Pin lines on sides
    final pinPaint = _stroke..strokeWidth = 1.0;
    for (final dy in [-r * 0.3, 0.0, r * 0.3]) {
      canvas.drawLine(Offset(cx - s - 3, cy + dy), Offset(cx - s, cy + dy), pinPaint);
      canvas.drawLine(Offset(cx + s, cy + dy), Offset(cx + s + 3, cy + dy), pinPaint);
    }
  }

  /// Gold: gold bar / ingot shape (trapezoid)
  void _paintBar(Canvas canvas, double cx, double cy, double r) {
    final path = Path();
    // Trapezoidal gold bar shape — wider at bottom
    path.moveTo(cx - r * 0.5, cy - r * 0.7); // top-left
    path.lineTo(cx + r * 0.5, cy - r * 0.7); // top-right
    path.lineTo(cx + r * 0.85, cy + r * 0.7); // bottom-right
    path.lineTo(cx - r * 0.85, cy + r * 0.7); // bottom-left
    path.close();
    canvas.drawPath(path, _fill);
    canvas.drawPath(path, _stroke);
    // Shine line on top
    final shinePaint = Paint()
      ..color = color.withValues(alpha: 0.3)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    canvas.drawLine(
      Offset(cx - r * 0.35, cy - r * 0.45),
      Offset(cx + r * 0.35, cy - r * 0.45),
      shinePaint,
    );
  }

  /// Contrast: bold square with thick border
  void _paintBold(Canvas canvas, double cx, double cy, double r) {
    final rect = Rect.fromCenter(center: Offset(cx, cy), width: r * 1.7, height: r * 1.7);
    canvas.drawRect(rect, _fill);
    final boldStroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(rect, boldStroke);
  }

  @override
  bool shouldRepaint(_SkinAddButtonPainter oldDelegate) =>
      skinId != oldDelegate.skinId || color != oldDelegate.color;
}

/// FAB in the shape of the active skin's motif.
/// Uses the skin icon asset (PNG) with a "+" overlay.
/// Falls back to CustomPaint for skins without an asset (e.g. contrast).
class SkinFab extends StatelessWidget {
  final String skinId;
  final Color color;
  final Color onColor;
  final VoidCallback onTap;
  final String tooltip;
  final IconData icon;
  final double size;

  const SkinFab({
    super.key,
    required this.skinId,
    required this.color,
    required this.onColor,
    required this.onTap,
    required this.tooltip,
    this.icon = Icons.add,
    this.size = 64.0,
  });

  /// Skins that have a PNG icon asset.
  static const _assetSkins = {
    'teal', 'ocean', 'sunset', 'forest',
    'amethyst', 'crimson', 'slate', 'gold',
    'contrast',
  };

  @override
  Widget build(BuildContext context) {
    final hasAsset = _assetSkins.contains(skinId);
    // Image-based FABs get a bit more space so details are visible
    final renderSize = hasAsset ? size * 1.1 : size;
    final skin = Skins.byId(skinId);
    final isSquarish = skin.fabBorderRadius > 0 && skin.fabBorderRadius < 16;

    return SizedBox(
      width: renderSize,
      height: renderSize,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          customBorder: isSquarish
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(skin.fabBorderRadius))
              : const CircleBorder(),
          child: Semantics(
            label: tooltip,
            button: true,
            child: Stack(
              alignment: Alignment.center,
              children: [
                if (hasAsset)
                  Opacity(
                    opacity: 0.88,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(isSquarish ? skin.fabBorderRadius : renderSize),
                      child: Image.asset(
                        'assets/icons/skins/$skinId.png',
                        width: renderSize,
                        height: renderSize,
                        filterQuality: FilterQuality.medium,
                      ),
                    ),
                  )
                else
                  CustomPaint(
                    size: Size(renderSize, renderSize),
                    painter: _SkinFabPainter(skinId: skinId, color: color),
                  ),
                // Border for skins with fabBorderWidth > 0
                if (skin.fabBorderWidth > 0)
                  Container(
                    width: renderSize,
                    height: renderSize,
                    decoration: BoxDecoration(
                      borderRadius: isSquarish
                          ? BorderRadius.circular(skin.fabBorderRadius)
                          : null,
                      shape: isSquarish ? BoxShape.rectangle : BoxShape.circle,
                      border: Border.all(
                        color: skin.isContrast ? Colors.white : color,
                        width: skin.fabBorderWidth,
                      ),
                    ),
                  ),
                // "+" badge in bottom-right corner
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: Container(
                    width: renderSize * 0.38,
                    height: renderSize * 0.38,
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: isSquarish
                          ? BorderRadius.circular(skin.fabBorderRadius * 0.5)
                          : null,
                      shape: isSquarish ? BoxShape.rectangle : BoxShape.circle,
                      boxShadow: [
                        BoxShadow(color: Colors.black26, blurRadius: 3, offset: const Offset(0, 1)),
                      ],
                    ),
                    child: Icon(
                      icon,
                      color: onColor,
                      size: renderSize * 0.24,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SkinFabPainter extends CustomPainter {
  final String skinId;
  final Color color;

  _SkinFabPainter({required this.skinId, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final cx = size.width / 2;
    final cy = size.height / 2;
    final r = size.width / 2 - 2;

    final shadow = Paint()
      ..color = color.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final fill = Paint()
      ..color = color.withValues(alpha: 0.88)
      ..style = PaintingStyle.fill;

    final highlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;

    final detail = Paint()
      ..color = Colors.white.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    switch (skinId) {
      case 'ocean':
        _paintOcean(canvas, cx, cy, r, shadow, fill, highlight, detail);
        break;
      case 'sunset':
        _paintSunset(canvas, cx, cy, r, shadow, fill, highlight, detail);
        break;
      case 'forest':
        _paintForest(canvas, cx, cy, r, shadow, fill, highlight, detail);
        break;
      case 'amethyst':
        _paintAmethyst(canvas, cx, cy, r, shadow, fill, highlight, detail);
        break;
      case 'crimson':
        _paintCrimson(canvas, cx, cy, r, shadow, fill, highlight, detail);
        break;
      case 'slate':
        _paintSlate(canvas, cx, cy, r, shadow, fill, highlight, detail);
        break;
      case 'gold':
        _paintGold(canvas, cx, cy, r, shadow, fill, highlight, detail);
        break;
      case 'contrast':
        _paintContrast(canvas, cx, cy, r, shadow, fill);
        break;
      default:
        _paintTeal(canvas, cx, cy, r, shadow, fill);
        break;
    }
  }

  /// Teal: clean circle
  void _paintTeal(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill) {
    final path = Path()..addOval(Rect.fromCircle(center: Offset(cx, cy), radius: r));
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
  }

  /// Ocean: flowing droplet with inner wave lines
  void _paintOcean(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill, Paint highlight, Paint detail) {
    final path = Path();
    path.moveTo(cx, cy - r * 0.95);
    path.cubicTo(cx + r * 0.5, cy - r * 0.95, cx + r * 1.1, cy - r * 0.4, cx + r * 0.9, cy + r * 0.1);
    path.cubicTo(cx + r * 0.7, cy + r * 0.6, cx + r * 0.35, cy + r * 1.0, cx, cy + r * 0.95);
    path.cubicTo(cx - r * 0.35, cy + r * 1.0, cx - r * 0.7, cy + r * 0.6, cx - r * 0.9, cy + r * 0.1);
    path.cubicTo(cx - r * 1.1, cy - r * 0.4, cx - r * 0.5, cy - r * 0.95, cx, cy - r * 0.95);
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
    // Inner wave lines
    for (final dy in [-0.15, 0.15]) {
      final wave = Path();
      wave.moveTo(cx - r * 0.5, cy + r * dy);
      wave.quadraticBezierTo(cx - r * 0.15, cy + r * (dy - 0.12), cx, cy + r * dy);
      wave.quadraticBezierTo(cx + r * 0.15, cy + r * (dy + 0.12), cx + r * 0.5, cy + r * dy);
      canvas.drawPath(wave, detail);
    }
  }

  /// Sunset: rounded sun with smooth rays
  void _paintSunset(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill, Paint highlight, Paint detail) {
    // Outer sun with smooth curved rays
    final path = Path();
    const rays = 10;
    for (var i = 0; i < rays * 2; i++) {
      final angle = (pi / rays) * i - pi / 2;
      final nextAngle = (pi / rays) * (i + 1) - pi / 2;
      final outerR = i.isEven ? r * 1.0 : r * 0.72;
      final nextR = i.isEven ? r * 0.72 : r * 1.0;
      final midAngle = (angle + nextAngle) / 2;
      final midR = (outerR + nextR) / 2;
      if (i == 0) {
        path.moveTo(cx + outerR * cos(angle), cy + outerR * sin(angle));
      }
      path.quadraticBezierTo(
        cx + midR * cos(midAngle), cy + midR * sin(midAngle),
        cx + nextR * cos(nextAngle), cy + nextR * sin(nextAngle),
      );
    }
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
    // Inner glow circle
    canvas.drawCircle(Offset(cx, cy), r * 0.45, highlight);
  }

  /// Forest: tall narrow leaf — clearly not a circle
  void _paintForest(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill, Paint highlight, Paint detail) {
    final path = Path();
    // Narrow pointed leaf — tall and slim
    path.moveTo(cx, cy - r * 1.15); // sharp top tip
    path.cubicTo(cx + r * 0.2, cy - r * 0.8, cx + r * 0.65, cy - r * 0.3, cx + r * 0.6, cy + r * 0.2);
    path.cubicTo(cx + r * 0.5, cy + r * 0.6, cx + r * 0.15, cy + r * 0.95, cx, cy + r * 1.15); // bottom tip
    path.cubicTo(cx - r * 0.15, cy + r * 0.95, cx - r * 0.5, cy + r * 0.6, cx - r * 0.6, cy + r * 0.2);
    path.cubicTo(cx - r * 0.65, cy - r * 0.3, cx - r * 0.2, cy - r * 0.8, cx, cy - r * 1.15);
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
    // Center vein — full length
    canvas.drawLine(Offset(cx, cy - r * 0.9), Offset(cx, cy + r * 0.9), detail);
    // Side veins — angled
    for (final dy in [-0.5, -0.2, 0.1, 0.4]) {
      final w = r * (0.35 - dy.abs() * 0.15);
      canvas.drawLine(Offset(cx, cy + r * dy), Offset(cx + w, cy + r * (dy - 0.18)), detail);
      canvas.drawLine(Offset(cx, cy + r * dy), Offset(cx - w, cy + r * (dy - 0.18)), detail);
    }
  }

  /// Amethyst: faceted crystal with inner facet lines and shimmer
  void _paintAmethyst(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill, Paint highlight, Paint detail) {
    final path = Path();
    path.moveTo(cx, cy - r);
    path.lineTo(cx + r * 0.7, cy - r * 0.55);
    path.lineTo(cx + r * 0.9, cy + r * 0.1);
    path.lineTo(cx + r * 0.55, cy + r * 0.7);
    path.lineTo(cx, cy + r);
    path.lineTo(cx - r * 0.55, cy + r * 0.7);
    path.lineTo(cx - r * 0.9, cy + r * 0.1);
    path.lineTo(cx - r * 0.7, cy - r * 0.55);
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
    // Facet lines from top to side vertices
    canvas.drawLine(Offset(cx, cy - r), Offset(cx + r * 0.9, cy + r * 0.1), detail);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx - r * 0.9, cy + r * 0.1), detail);
    canvas.drawLine(Offset(cx, cy - r), Offset(cx, cy + r), detail);
    // Horizontal facet
    canvas.drawLine(Offset(cx - r * 0.7, cy - r * 0.55), Offset(cx + r * 0.7, cy - r * 0.55), detail);
    // Highlight edge
    final shimmer = Path();
    shimmer.moveTo(cx, cy - r);
    shimmer.lineTo(cx + r * 0.7, cy - r * 0.55);
    shimmer.lineTo(cx + r * 0.9, cy + r * 0.1);
    canvas.drawPath(shimmer, highlight);
  }

  /// Crimson: tall narrow flame — clearly flame-shaped, not circular
  void _paintCrimson(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill, Paint highlight, Paint detail) {
    final path = Path();
    // Tall narrow flame with flickering tip and wide base
    path.moveTo(cx, cy - r * 1.2); // sharp tip
    path.cubicTo(cx + r * 0.1, cy - r * 0.9, cx + r * 0.4, cy - r * 0.5, cx + r * 0.5, cy - r * 0.1);
    // Right flicker outward
    path.cubicTo(cx + r * 0.65, cy + r * 0.15, cx + r * 0.7, cy + r * 0.4, cx + r * 0.5, cy + r * 0.6);
    // Narrow back in then wide base
    path.cubicTo(cx + r * 0.35, cy + r * 0.75, cx + r * 0.2, cy + r * 0.85, cx, cy + r * 0.8);
    // Mirror left side
    path.cubicTo(cx - r * 0.2, cy + r * 0.85, cx - r * 0.35, cy + r * 0.75, cx - r * 0.5, cy + r * 0.6);
    path.cubicTo(cx - r * 0.7, cy + r * 0.4, cx - r * 0.65, cy + r * 0.15, cx - r * 0.5, cy - r * 0.1);
    path.cubicTo(cx - r * 0.4, cy - r * 0.5, cx - r * 0.1, cy - r * 0.9, cx, cy - r * 1.2);
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
    // Inner lighter flame tongue
    final inner = Path();
    inner.moveTo(cx, cy - r * 0.6);
    inner.cubicTo(cx + r * 0.08, cy - r * 0.3, cx + r * 0.2, cy + r * 0.05, cx + r * 0.12, cy + r * 0.3);
    inner.cubicTo(cx + r * 0.05, cy + r * 0.5, cx, cy + r * 0.45, cx, cy + r * 0.45);
    inner.cubicTo(cx, cy + r * 0.45, cx - r * 0.05, cy + r * 0.5, cx - r * 0.12, cy + r * 0.3);
    inner.cubicTo(cx - r * 0.2, cy + r * 0.05, cx - r * 0.08, cy - r * 0.3, cx, cy - r * 0.6);
    inner.close();
    canvas.drawPath(inner, Paint()..color = Colors.white.withValues(alpha: 0.2)..style = PaintingStyle.fill);
  }

  /// Slate: microchip with pins and circuit traces
  void _paintSlate(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill, Paint highlight, Paint detail) {
    final s = r * 0.78;
    final notch = r * 0.18;
    final path = Path();
    path.moveTo(cx - s + notch, cy - s);
    path.lineTo(cx + s - notch, cy - s);
    path.lineTo(cx + s, cy - s + notch);
    path.lineTo(cx + s, cy + s - notch);
    path.lineTo(cx + s - notch, cy + s);
    path.lineTo(cx - s + notch, cy + s);
    path.lineTo(cx - s, cy + s - notch);
    path.lineTo(cx - s, cy - s + notch);
    path.close();
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
    // Pins on all 4 sides
    final pinPaint = Paint()
      ..color = color.withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final d in [-r * 0.3, 0.0, r * 0.3]) {
      canvas.drawLine(Offset(cx - s - 4, cy + d), Offset(cx - s, cy + d), pinPaint);
      canvas.drawLine(Offset(cx + s, cy + d), Offset(cx + s + 4, cy + d), pinPaint);
      canvas.drawLine(Offset(cx + d, cy - s - 4), Offset(cx + d, cy - s), pinPaint);
      canvas.drawLine(Offset(cx + d, cy + s), Offset(cx + d, cy + s + 4), pinPaint);
    }
    // Inner circuit trace
    canvas.drawLine(Offset(cx - s * 0.4, cy - s * 0.4), Offset(cx + s * 0.4, cy + s * 0.4), detail);
    canvas.drawLine(Offset(cx + s * 0.4, cy - s * 0.4), Offset(cx - s * 0.4, cy + s * 0.4), detail);
  }

  /// Gold: 3D gold bar / ingot — wide, flat, clearly trapezoidal
  void _paintGold(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill, Paint highlight, Paint detail) {
    // Front face (wide trapezoid)
    final bottom = Path();
    bottom.moveTo(cx - r * 1.05, cy + r * 0.55);
    bottom.lineTo(cx + r * 1.05, cy + r * 0.55);
    bottom.lineTo(cx + r * 0.7, cy - r * 0.1);
    bottom.lineTo(cx - r * 0.7, cy - r * 0.1);
    bottom.close();
    // Top face (beveled, narrower)
    final top = Path();
    top.moveTo(cx - r * 0.7, cy - r * 0.1);
    top.lineTo(cx + r * 0.7, cy - r * 0.1);
    top.lineTo(cx + r * 0.5, cy - r * 0.6);
    top.lineTo(cx - r * 0.5, cy - r * 0.6);
    top.close();
    // Combined for shadow
    final combined = Path();
    combined.addPath(bottom, Offset.zero);
    combined.addPath(top, Offset.zero);
    canvas.drawPath(combined.shift(const Offset(1, 2)), shadow);
    // Draw bottom face darker
    canvas.drawPath(bottom, fill);
    // Top face slightly lighter
    final topFill = Paint()
      ..color = color.withValues(alpha: 0.95)
      ..style = PaintingStyle.fill;
    canvas.drawPath(top, topFill);
    // Bevel edge line
    canvas.drawLine(Offset(cx - r * 0.55, cy + r * 0.05), Offset(cx + r * 0.55, cy + r * 0.05), highlight);
    // Shine on top
    canvas.drawLine(Offset(cx - r * 0.25, cy - r * 0.35), Offset(cx + r * 0.25, cy - r * 0.35), highlight);
  }

  /// Contrast: bold thick-bordered square
  void _paintContrast(Canvas canvas, double cx, double cy, double r, Paint shadow, Paint fill) {
    final s = r * 0.8;
    final path = Path()..addRect(Rect.fromCenter(center: Offset(cx, cy), width: s * 2, height: s * 2));
    canvas.drawPath(path.shift(const Offset(1, 2)), shadow);
    canvas.drawPath(path, fill);
    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRect(Rect.fromCenter(center: Offset(cx, cy), width: s * 2, height: s * 2), border);
  }

  @override
  bool shouldRepaint(_SkinFabPainter oldDelegate) =>
      skinId != oldDelegate.skinId || color != oldDelegate.color;
}
