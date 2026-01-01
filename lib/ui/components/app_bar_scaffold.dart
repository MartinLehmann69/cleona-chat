// lib/ui/components/app_bar_scaffold.dart
//
// Fullscreen SkinSurface scaffold (browser-preview aligned).
// Body structure:
//   Scaffold
//     body: SkinSurface (fullscreen photo/cssTeal/cssSlate/brutalist + scrim)
//       content overlay: SafeArea → Column [ _HeaderRow, Expanded(body) ]
//     floatingActionButton: floatingActionButton
//
// Reference: docs/design/skins-final-browser-preview.html

import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/character_profile.dart';
import 'package:cleona/ui/theme/luminance.dart';
import 'package:cleona/ui/theme/skin_surface.dart';
import 'package:cleona/ui/theme/theme_access.dart';

class AppBarScaffold extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;
  final Widget body;
  final Widget? floatingActionButton;

  /// When true, the body is rendered on top of an OPAQUE theme.surface layer
  /// (so skin-independent body UI with many theme-colored subwidgets — e.g.
  /// Settings, Calendar, EventEditor — stays readable). The Scaffold header
  /// area still shows the skin surface behind the _HeaderRow.
  /// Leave false for home_screen/chat_screen where the photo should shine
  /// through behind cards/message-bubbles (browser-preview intent).
  final bool opaqueBody;

  const AppBarScaffold({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
    required this.body,
    this.floatingActionButton,
    this.opaqueBody = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: Colors.transparent,
      extendBodyBehindAppBar: true,
      body: SkinSurface(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              _HeaderRow(
                title: title,
                subtitle: subtitle,
                leading: leading,
                actions: actions,
              ),
              Expanded(
                child: SafeArea(
                  top: false,
                  child: opaqueBody
                      ? ColoredBox(color: theme.colorScheme.surface, child: body)
                      : body,
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: floatingActionButton,
    );
  }
}

/// The top header row sits over the SkinSurface. Typography adapts per
/// surfaceRenderMode:
///  - photo: light text with drop-shadow for legibility over photo+scrim
///  - cssTeal: dark teal text, no shadow
///  - cssSlate: cyan/green terminal tones, monospace-friendly
///  - brutalist: title wrapped in yellow badge (UPPERCASE), black text
class _HeaderRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget? leading;
  final List<Widget>? actions;

  const _HeaderRow({
    required this.title,
    this.subtitle,
    this.leading,
    this.actions,
  });

  Color _resolveForeground(CharacterProfile character) {
    switch (character.appBarForegroundMode) {
      case AppBarForegroundMode.auto:
        if (character.surfaceRenderMode == SurfaceRenderMode.photo) {
          return Colors.white;
        }
        if (character.surfaceRenderMode == SurfaceRenderMode.cssSlate) {
          return const Color(0xFF00E5FF);
        }
        if (character.surfaceRenderMode == SurfaceRenderMode.brutalist) {
          return Colors.black;
        }
        return autoForeground(character.accentColor);
      case AppBarForegroundMode.forceLight:
        return Colors.white;
      case AppBarForegroundMode.forceDark:
        return Colors.black;
    }
  }

  /// Multi-layer shadow set for text over photo backgrounds.
  /// Layer 1: tight dark halo for legibility even on bright photo regions.
  /// Layer 2: wider blur for overall separation from complex textures.
  static const _photoShadow = <Shadow>[
    Shadow(color: Color(0xE6000000), blurRadius: 2, offset: Offset(0, 1)),
    Shadow(color: Color(0x99000000), blurRadius: 8, offset: Offset(0, 2)),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final character = theme.character;
    final tokens = theme.tokens;
    final fg = _resolveForeground(character);
    final isPhoto = character.surfaceRenderMode == SurfaceRenderMode.photo;
    final isBrutalist = character.surfaceRenderMode == SurfaceRenderMode.brutalist;

    final titleStyle = (isBrutalist
            ? tokens.typography.title
            : tokens.typography.title)
        .copyWith(
      color: fg,
      fontWeight: character.titleWeightBaseline,
      shadows: isPhoto ? _photoShadow : null,
    );

    final subtitleStyle = tokens.typography.caption.copyWith(
      color: fg.withValues(alpha: 0.9),
      shadows: isPhoto ? _photoShadow : null,
    );

    Widget titleWidget;
    if (isBrutalist) {
      titleWidget = Container(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.sm,
          vertical: tokens.spacing.xs,
        ),
        decoration: const BoxDecoration(color: Color(0xFFFFEB3B)),
        child: Text(
          title.toUpperCase(),
          style: titleStyle.copyWith(fontWeight: FontWeight.w900),
        ),
      );
    } else {
      titleWidget = Text(title, style: titleStyle);
    }

    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      child: Row(
        children: [
          if (leading != null)
            IconTheme(data: IconThemeData(color: fg), child: leading!),
          if (leading != null) SizedBox(width: tokens.spacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                titleWidget,
                if (subtitle != null) ...[
                  SizedBox(height: tokens.spacing.xs),
                  Text(
                    isBrutalist ? subtitle!.toUpperCase() : subtitle!,
                    style: subtitleStyle,
                  ),
                ],
              ],
            ),
          ),
          if (actions != null)
            IconTheme(data: IconThemeData(color: fg), child: Row(children: actions!)),
        ],
      ),
    );
  }
}
