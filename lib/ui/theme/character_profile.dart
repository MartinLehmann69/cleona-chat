// lib/ui/theme/character_profile.dart
import 'package:flutter/material.dart';

/// Controls how the AppBar is rendered — see spec §3.3.
enum AppBarIntensity {
  solid,      // Full seedColor background, auto-luminance foreground
  photo,      // hero.webp background with scrim gradient
  tinted,     // Material-3 tinted surface (reserved, unused)
  surface,    // Neutral surface (reserved, unused)
  brutalist,  // Contrast skin: white bg, yellow title-badge, thick borders
}

/// Controls how the AppBar foreground (text, icons) is chosen.
enum AppBarForegroundMode {
  auto,       // Luminance-based (default)
  forceLight, // Always white
  forceDark,  // Always black
}

/// Controls how the FULLSCREEN surface behind the app is rendered.
/// Added per browser-preview alignment: photo skins cover full screen,
/// CSS skins (Teal/Slate/Contrast) use custom non-photo renderings.
enum SurfaceRenderMode {
  photo,      // heroAssetPath fullscreen + scrimGradient overlay
  cssTeal,    // Radial-gradient teal wash + 24px grid overlay
  cssSlate,   // Dark gradient + cyan-dot pattern + scanline
  brutalist,  // Pure white surface (for Contrast)
}

@immutable
class CharacterProfile extends ThemeExtension<CharacterProfile> {
  final AppBarIntensity appBarIntensity;
  final FontWeight titleWeightBaseline;
  final double radiusMultiplier;
  final AppBarForegroundMode appBarForegroundMode;
  final String? heroAssetPath;
  final LinearGradient? fallbackGradient;
  final Color accentColor;

  // Browser-preview fields
  final SurfaceRenderMode surfaceRenderMode;
  final LinearGradient? scrimGradient;
  final Color peerDotColor;
  final String? avatarAssetPath;
  final String? fabAssetPath;

  const CharacterProfile({
    required this.appBarIntensity,
    required this.titleWeightBaseline,
    required this.radiusMultiplier,
    required this.appBarForegroundMode,
    required this.accentColor,
    this.heroAssetPath,
    this.fallbackGradient,
    this.surfaceRenderMode = SurfaceRenderMode.photo,
    this.scrimGradient,
    this.peerDotColor = const Color(0xFF4ADE80),
    this.avatarAssetPath,
    this.fabAssetPath,
  });

  static const CharacterProfile standard = CharacterProfile(
    appBarIntensity: AppBarIntensity.solid,
    titleWeightBaseline: FontWeight.w600,
    radiusMultiplier: 1.0,
    appBarForegroundMode: AppBarForegroundMode.auto,
    accentColor: Color(0xFF00897B), // Teal
    surfaceRenderMode: SurfaceRenderMode.cssTeal,
  );

  @override
  CharacterProfile copyWith({
    AppBarIntensity? appBarIntensity,
    FontWeight? titleWeightBaseline,
    double? radiusMultiplier,
    AppBarForegroundMode? appBarForegroundMode,
    String? heroAssetPath,
    LinearGradient? fallbackGradient,
    Color? accentColor,
    SurfaceRenderMode? surfaceRenderMode,
    LinearGradient? scrimGradient,
    Color? peerDotColor,
    String? avatarAssetPath,
    String? fabAssetPath,
  }) {
    return CharacterProfile(
      appBarIntensity: appBarIntensity ?? this.appBarIntensity,
      titleWeightBaseline: titleWeightBaseline ?? this.titleWeightBaseline,
      radiusMultiplier: radiusMultiplier ?? this.radiusMultiplier,
      appBarForegroundMode: appBarForegroundMode ?? this.appBarForegroundMode,
      heroAssetPath: heroAssetPath ?? this.heroAssetPath,
      fallbackGradient: fallbackGradient ?? this.fallbackGradient,
      accentColor: accentColor ?? this.accentColor,
      surfaceRenderMode: surfaceRenderMode ?? this.surfaceRenderMode,
      scrimGradient: scrimGradient ?? this.scrimGradient,
      peerDotColor: peerDotColor ?? this.peerDotColor,
      avatarAssetPath: avatarAssetPath ?? this.avatarAssetPath,
      fabAssetPath: fabAssetPath ?? this.fabAssetPath,
    );
  }

  @override
  CharacterProfile lerp(ThemeExtension<CharacterProfile>? other, double t) {
    // Discrete profile, no animation between skins (skin switch is abrupt)
    return this;
  }
}
