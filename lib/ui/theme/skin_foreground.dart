// lib/ui/theme/skin_foreground.dart
//
// The colour of controls that sit ON a skin's own surfaces (S412,
// 05.11.2026). The cards of the contact and conversation rows and the page
// background of the photo and slate skins have colours of their own that the
// ColorScheme does not know: a photo skin builds a LIGHT scheme, so a control
// without a colour of its own takes the scheme's dark grey — and sat dark on
// the dark frosted card (`0x80000000`) or the photo. The three-dot menus of
// every row, the list search and the section headings were practically
// invisible with "Ocean" on Android, Linux and every other platform alike.
//
// Text in those rows already chose its colour per surface mode; controls did
// not. `PopupMenuButton` takes `iconColor ?? popupMenuTheme.iconColor ??
// IconTheme.of(context).color` (flutter/material/popup_menu.dart), so an
// IconTheme around a card's controls reaches them. One place decides the
// colours; test/smoke/smoke_skin_control_contrast.dart measures
// them against the surfaces for every skin, light and dark (WCAG 2.1 SC 1.4.11:
// 3:1 for user-interface components).

import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/character_profile.dart';
import 'package:cleona/ui/theme/theme_access.dart';

/// Colour of a control on a row card of [mode] — the same secondary colour
/// the row's status/timestamp text uses on that card.
Color skinCardControlColor(SurfaceRenderMode mode) {
  switch (mode) {
    case SurfaceRenderMode.photo:
      return kPhotoSecondaryText;
    case SurfaceRenderMode.cssTeal:
      return const Color(0xCC000000);
    case SurfaceRenderMode.cssSlate:
      return const Color(0xCC69F0AE);
    case SurfaceRenderMode.brutalist:
      return const Color(0xFF000000);
  }
}

/// Colour of a control or heading directly on the page background of the
/// skin, or null where the ColorScheme already fits the background (teal and
/// contrast are light). Photo and slate are dark behind the content — the
/// same rule the category tabs follow (home_screen.dart `needsOverlay`).
Color? skinBackgroundForeground(BuildContext context) {
  switch (Theme.of(context).character.surfaceRenderMode) {
    case SurfaceRenderMode.photo:
    case SurfaceRenderMode.cssSlate:
      return Colors.white;
    case SurfaceRenderMode.cssTeal:
    case SurfaceRenderMode.brutalist:
      return null;
  }
}

/// The shadow that keeps white text readable over the bright parts of a
/// photo (the category tabs use the same pair); none for the other modes.
List<Shadow>? skinBackgroundTextShadows(BuildContext context) =>
    Theme.of(context).character.surfaceRenderMode == SurfaceRenderMode.photo
        ? const <Shadow>[
            Shadow(color: Color(0xE6000000), blurRadius: 2, offset: Offset(0, 1)),
            Shadow(color: Color(0x99000000), blurRadius: 6, offset: Offset(0, 2)),
          ]
        : null;

/// [style] for a heading directly on the page background — unchanged where
/// the scheme fits, white with the photo shadow on photo and slate.
TextStyle? skinBackgroundHeading(BuildContext context, TextStyle? style) {
  final fg = skinBackgroundForeground(context);
  if (fg == null) return style;
  return (style ?? const TextStyle())
      .copyWith(color: fg, shadows: skinBackgroundTextShadows(context));
}

/// Wraps the controls of a row card so every icon without a colour of its
/// own — the three-dot menu above all — takes [skinCardControlColor].
class SkinCardControls extends StatelessWidget {
  final Widget child;

  const SkinCardControls({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final mode = Theme.of(context).character.surfaceRenderMode;
    return IconTheme.merge(
      data: IconThemeData(color: skinCardControlColor(mode)),
      child: child,
    );
  }
}
