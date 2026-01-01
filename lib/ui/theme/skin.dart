import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/character_profile.dart';
import 'package:cleona/ui/theme/design_tokens.dart';

/// Defines a visual skin for an identity.
/// Each skin controls the entire app color palette via Material 3 seed color,
/// plus font style, message bubble shape, border style, and shadow elevation.
class Skin {
  final String id;
  final String name;
  final Color seedColor;
  final String? fontFamily;
  final FontWeight titleWeight;
  final double borderRadius; // for message bubbles
  final double borderWidth;
  final double shadowElevation;

  // Accessibility extras (Phase 4 — used by Contrast skin)
  final double fontSizeScale; // 1.0 = normal, 1.15 = 15% larger
  final double dividerThickness; // default 0.5, contrast uses 2.0
  final double minTouchTarget; // minimum touch target in dp (default 48, contrast 56)
  final bool forceBorders; // force visible borders on all interactive elements

  // FAB customization per skin
  final double fabBorderRadius; // 0 = circle (default), >0 = rounded rect
  final double fabElevation;
  final double fabBorderWidth;

  // Themed icons per skin
  final IconData addContactIcon;
  final IconData addGroupIcon;
  final IconData addChannelIcon;
  final IconData addIdentityIcon;

  // NEW — design-system-foundation
  final AppBarIntensity appBarIntensity;
  final AppBarForegroundMode appBarForegroundMode;
  final double radiusMultiplier;
  final String? heroAssetPath;
  final LinearGradient? fallbackGradient;

  // Browser-preview alignment
  final SurfaceRenderMode surfaceRenderMode;
  final LinearGradient? scrimGradient;
  final Color peerDotColor;
  final String? avatarAssetPath;
  final String? fabAssetPath;

  const Skin({
    required this.id,
    required this.name,
    required this.seedColor,
    this.fontFamily,
    this.titleWeight = FontWeight.w600,
    this.borderRadius = 12.0,
    this.borderWidth = 0.0,
    this.shadowElevation = 0.0,
    this.fontSizeScale = 1.0,
    this.dividerThickness = 0.5,
    this.minTouchTarget = 48.0,
    this.forceBorders = false,
    this.fabBorderRadius = 0.0,
    this.fabElevation = 6.0,
    this.fabBorderWidth = 0.0,
    this.addContactIcon = Icons.person_add,
    this.addGroupIcon = Icons.group_add,
    this.addChannelIcon = Icons.campaign,
    this.addIdentityIcon = Icons.add,
    // NEW:
    this.appBarIntensity = AppBarIntensity.solid,
    this.appBarForegroundMode = AppBarForegroundMode.auto,
    this.radiusMultiplier = 1.0,
    this.heroAssetPath,
    this.fallbackGradient,
    this.surfaceRenderMode = SurfaceRenderMode.photo,
    this.scrimGradient,
    this.peerDotColor = const Color(0xFF4ADE80),
    this.avatarAssetPath,
    this.fabAssetPath,
  });

  bool get isContrast => id == 'contrast';

  /// Returns the effective skin accent color for the given brightness.
  /// For Contrast skin: always black — the brutalist surface is pinned white
  /// in both light and dark mode (see SurfaceRenderMode.brutalist), so the
  /// accent must be black regardless of the platform brightness preference.
  /// For all other skins: seedColor unchanged.
  Color effectiveColor(Brightness brightness) {
    if (!isContrast) return seedColor;
    return const Color(0xFF000000);
  }

  ThemeData toLightTheme() {
    final base = ThemeData(
      colorScheme: isContrast
          ? const ColorScheme.light(
              primary: Color(0xFF000000),
              onPrimary: Color(0xFFFFFFFF),
              surface: Color(0xFFFFFFFF),
              onSurface: Color(0xFF000000),
              outline: Color(0xFF000000),
            )
          : ColorScheme.fromSeed(
              seedColor: seedColor,
              brightness: Brightness.light,
            ),
      useMaterial3: true,
      fontFamily: fontFamily,
    );
    return _applyAccessibility(base).copyWith(
      extensions: [
        DesignTokens.standard,
        CharacterProfile(
          appBarIntensity: appBarIntensity,
          titleWeightBaseline: titleWeight,
          radiusMultiplier: radiusMultiplier,
          appBarForegroundMode: appBarForegroundMode,
          accentColor: seedColor,
          heroAssetPath: heroAssetPath,
          fallbackGradient: fallbackGradient,
          surfaceRenderMode: surfaceRenderMode,
          scrimGradient: scrimGradient,
          peerDotColor: peerDotColor,
          avatarAssetPath: avatarAssetPath,
          fabAssetPath: fabAssetPath,
        ),
      ],
    );
  }

  /// True when the skin's surface render mode renders a light background
  /// that is pinned regardless of the platform brightness preference. In
  /// that case toDarkTheme() must still hand out a LIGHT ColorScheme —
  /// otherwise widgets that resolve `null → theme.onSurface` get white
  /// foreground tokens and render white-on-white on the pinned-light
  /// surface (TabBar labels, menus, add-identity icon, etc).
  bool get _surfacePinnedLight =>
      surfaceRenderMode == SurfaceRenderMode.cssTeal ||
      surfaceRenderMode == SurfaceRenderMode.brutalist;

  ThemeData toDarkTheme() {
    final ColorScheme scheme;
    if (isContrast) {
      scheme = const ColorScheme.light(
        primary: Color(0xFF000000),
        onPrimary: Color(0xFFFFFFFF),
        surface: Color(0xFFFFFFFF),
        onSurface: Color(0xFF000000),
        outline: Color(0xFF000000),
      );
    } else if (_surfacePinnedLight) {
      scheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.light,
      );
    } else {
      scheme = ColorScheme.fromSeed(
        seedColor: seedColor,
        brightness: Brightness.dark,
      );
    }
    final base = ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      fontFamily: fontFamily,
    );
    return _applyAccessibility(base).copyWith(
      extensions: [
        DesignTokens.standard,
        CharacterProfile(
          appBarIntensity: appBarIntensity,
          titleWeightBaseline: titleWeight,
          radiusMultiplier: radiusMultiplier,
          appBarForegroundMode: appBarForegroundMode,
          accentColor: seedColor,
          heroAssetPath: heroAssetPath,
          fallbackGradient: fallbackGradient,
          surfaceRenderMode: surfaceRenderMode,
          scrimGradient: scrimGradient,
          peerDotColor: peerDotColor,
          avatarAssetPath: avatarAssetPath,
          fabAssetPath: fabAssetPath,
        ),
      ],
    );
  }

  ThemeData _applyAccessibility(ThemeData base) {
    if (fontSizeScale == 1.0 && dividerThickness == 0.5 && !forceBorders) {
      return base;
    }
    return base.copyWith(
      textTheme: _scaleTextTheme(base.textTheme),
      dividerTheme: DividerThemeData(thickness: dividerThickness),
      listTileTheme: ListTileThemeData(
        minVerticalPadding: forceBorders ? 12.0 : null,
        minTileHeight: minTouchTarget,
      ),
    );
  }

  TextTheme _scaleTextTheme(TextTheme base) {
    if (fontSizeScale == 1.0) return base;
    TextStyle scale(TextStyle? style) =>
        (style ?? const TextStyle()).copyWith(
          fontSize: ((style?.fontSize ?? 14) * fontSizeScale),
        );
    return base.copyWith(
      displayLarge: scale(base.displayLarge),
      displayMedium: scale(base.displayMedium),
      displaySmall: scale(base.displaySmall),
      headlineLarge: scale(base.headlineLarge),
      headlineMedium: scale(base.headlineMedium),
      headlineSmall: scale(base.headlineSmall),
      titleLarge: scale(base.titleLarge),
      titleMedium: scale(base.titleMedium),
      titleSmall: scale(base.titleSmall),
      bodyLarge: scale(base.bodyLarge),
      bodyMedium: scale(base.bodyMedium),
      bodySmall: scale(base.bodySmall),
      labelLarge: scale(base.labelLarge),
      labelMedium: scale(base.labelMedium),
      labelSmall: scale(base.labelSmall),
    );
  }
}
