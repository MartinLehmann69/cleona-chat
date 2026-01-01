// lib/ui/components/skin_fab.dart
//
// Per-skin FloatingActionButton replacement that matches the browser-preview
// `.mock-fab` CSS styling.
//
// Reference: docs/design/skins-final-browser-preview.html
//
// Mode dispatch via Theme.of(context).character.surfaceRenderMode:
//   photo     → 60×60, 16px radius, white@40% border, bg-image + dark-overlay
//   cssTeal   → 56×56, 4px radius, no image/border/overlay, teal solid bg
//   cssSlate  → 60×60, 4px radius, 2px cyan border, cyan glow shadow, monospace +
//   brutalist → 64×64, 0 radius, 3px black border, yellow bg, offset shadow

import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/character_profile.dart';

/// Per-skin FAB that matches the browser-preview `.mock-fab` per-skin rules.
class SkinFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData? icon;
  final String? heroTag;

  const SkinFab({
    super.key,
    this.onPressed,
    this.icon,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    final character = Theme.of(context).extension<CharacterProfile>() ??
        CharacterProfile.standard;

    switch (character.surfaceRenderMode) {
      case SurfaceRenderMode.cssTeal:
        return _TealFab(
          onPressed: onPressed,
          icon: icon ?? Icons.add,
          heroTag: heroTag,
        );
      case SurfaceRenderMode.cssSlate:
        return _SlateFab(
          onPressed: onPressed,
          icon: icon ?? Icons.add,
          heroTag: heroTag,
        );
      case SurfaceRenderMode.brutalist:
        return _BrutalistFab(
          onPressed: onPressed,
          icon: icon ?? Icons.add,
          heroTag: heroTag,
        );
      case SurfaceRenderMode.photo:
        return _PhotoFab(
          onPressed: onPressed,
          icon: icon ?? Icons.add,
          heroTag: heroTag,
          fabAssetPath: character.fabAssetPath,
        );
    }
  }
}

// ── Teal FAB ────────────────────────────────────────────────────────────────
// CSS spec: bg #00897B, 4px radius, no image/overlay/border, 56×56
// shadow: 0 6px 18px rgba(0,137,123,0.35), 0 2px 4px rgba(0,0,0,0.1)
// white + size 30 weight 300

class _TealFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? heroTag;

  const _TealFab({required this.onPressed, required this.icon, this.heroTag});

  @override
  Widget build(BuildContext context) {
    const teal = Color(0xFF00897B);
    const size = 56.0;
    const radius = BorderRadius.all(Radius.circular(4.0));

    return _FabShell(
      heroTag: heroTag,
      size: size,
      borderRadius: radius,
      shadow: const [
        BoxShadow(
          color: Color(0x5900897B), // rgba(0,137,123,0.35)
          blurRadius: 18,
          offset: Offset(0, 6),
        ),
        BoxShadow(
          color: Color(0x1A000000), // rgba(0,0,0,0.1)
          blurRadius: 4,
          offset: Offset(0, 2),
        ),
      ],
      border: null,
      decoration: const BoxDecoration(
        color: teal,
        borderRadius: radius,
      ),
      onPressed: onPressed,
      child: Icon(
        icon,
        color: Colors.white,
        size: 30,
        weight: 300,
      ),
    );
  }
}

// ── Slate FAB ───────────────────────────────────────────────────────────────
// CSS spec: bg #0f1419, 2px #00E5FF border, 4px radius, 60×60
// shadow: 0 0 20px rgba(0,229,255,0.4), 0 8px 24px rgba(0,0,0,0.5)
// cyan + size 26 weight 900 monospace, cyan glow text-shadow

class _SlateFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? heroTag;

  const _SlateFab({required this.onPressed, required this.icon, this.heroTag});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFF0F1419);
    const cyan = Color(0xFF00E5FF);
    const size = 60.0;
    const radius = BorderRadius.all(Radius.circular(4.0));

    return _FabShell(
      heroTag: heroTag,
      size: size,
      borderRadius: radius,
      shadow: const [
        BoxShadow(
          color: Color(0x6600E5FF), // rgba(0,229,255,0.4)
          blurRadius: 20,
          offset: Offset(0, 0),
        ),
        BoxShadow(
          color: Color(0x80000000), // rgba(0,0,0,0.5)
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
      border: Border.all(color: cyan, width: 2),
      decoration: const BoxDecoration(
        color: bg,
        borderRadius: radius,
      ),
      onPressed: onPressed,
      child: Icon(
        icon,
        color: cyan,
        size: 26,
        weight: 900,
      ),
    );
  }
}

// ── Brutalist FAB ────────────────────────────────────────────────────────────
// CSS spec: bg #FFEB3B, 3px #000 border, 0 radius, 64×64
// shadow: 5px 5px 0 #000 (offset solid, no blur)
// black + size 36 weight 900, no text-shadow

class _BrutalistFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? heroTag;

  const _BrutalistFab({required this.onPressed, required this.icon, this.heroTag});

  @override
  Widget build(BuildContext context) {
    const yellow = Color(0xFFFFEB3B);
    const black = Color(0xFF000000);
    const size = 64.0;
    const radius = BorderRadius.zero;

    return _FabShell(
      heroTag: heroTag,
      size: size,
      borderRadius: radius,
      shadow: const [
        BoxShadow(
          color: black,
          offset: Offset(5, 5),
          blurRadius: 0, // solid offset shadow, no blur
        ),
      ],
      border: Border.all(color: black, width: 3),
      decoration: const BoxDecoration(
        color: yellow,
        borderRadius: radius,
      ),
      onPressed: onPressed,
      child: Icon(
        icon,
        color: black,
        size: 36,
        weight: 900,
      ),
    );
  }
}

// ── Photo FAB ────────────────────────────────────────────────────────────────
// CSS spec: bg = fabAssetPath, 16px radius, 2px white@40% border, 60×60
// overlay rgba(0,0,0,0.25), + size 36 weight 300 white with text-shadow

class _PhotoFab extends StatelessWidget {
  final VoidCallback? onPressed;
  final IconData icon;
  final String? heroTag;
  final String? fabAssetPath;

  const _PhotoFab({
    required this.onPressed,
    required this.icon,
    this.heroTag,
    this.fabAssetPath,
  });

  @override
  Widget build(BuildContext context) {
    const size = 60.0;
    const radius = BorderRadius.all(Radius.circular(16.0));

    return _FabShell(
      heroTag: heroTag,
      size: size,
      borderRadius: radius,
      shadow: const [
        BoxShadow(
          color: Color(0x80000000), // rgba(0,0,0,0.5)
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
      border: Border.all(color: const Color(0x66FFFFFF), width: 2), // rgba(255,255,255,0.4)
      decoration: BoxDecoration(
        borderRadius: radius,
        color: const Color(0xFF1565C0), // fallback if no image
        image: fabAssetPath != null
            ? DecorationImage(
                image: AssetImage(fabAssetPath!),
                fit: BoxFit.cover,
              )
            : null,
      ),
      onPressed: onPressed,
      // Stack: dark overlay + plus icon on top
      child: Stack(
        fit: StackFit.expand,
        children: [
          // Dark overlay (::before pseudo-element equivalent)
          const ColoredBox(color: Color(0x40000000)), // rgba(0,0,0,0.25)
          // Plus icon centered on top
          Center(
            child: Icon(
              icon,
              color: Colors.white,
              size: 36,
              weight: 300,
              shadows: const [
                Shadow(
                  color: Color(0xCC000000), // rgba(0,0,0,0.8)
                  blurRadius: 12,
                  offset: Offset(0, 2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Shell widget ─────────────────────────────────────────────────────────────
// Handles the tap ripple + sizing + outer decoration + border + shadow.
// The `decoration` goes on the inner Container (with clipping).
// The shadow + border go outside (on the outer DecoratedBox) so InkWell
// ripple clips correctly within the rounded bounds.

class _FabShell extends StatelessWidget {
  final VoidCallback? onPressed;
  final double size;
  final BorderRadius borderRadius;
  final List<BoxShadow> shadow;
  final Border? border;
  final BoxDecoration decoration;
  final Widget child;
  final String? heroTag;

  const _FabShell({
    required this.onPressed,
    required this.size,
    required this.borderRadius,
    required this.shadow,
    required this.border,
    required this.decoration,
    required this.child,
    this.heroTag,
  });

  @override
  Widget build(BuildContext context) {
    // Outer wrapper: shadow + border radius (for shadow to show outside clip)
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: shadow,
      ),
      child: Material(
        color: Colors.transparent,
        borderRadius: borderRadius,
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          borderRadius: borderRadius,
          child: Container(
            width: size,
            height: size,
            decoration: decoration.copyWith(border: border),
            child: child,
          ),
        ),
      ),
    );
  }
}
