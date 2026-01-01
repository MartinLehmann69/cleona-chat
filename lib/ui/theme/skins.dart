import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/skin.dart';
import 'package:cleona/ui/theme/character_profile.dart';

/// The 10 predefined identity skins.
/// Browser-preview reference: docs/design/skins-final-browser-preview.html
class Skins {
  Skins._();

  // ── Scrim gradient helper (photo skins) ─────────────────────────────────
  // Per skins-final.html each photo skin has a tuned 3-stop top→bottom scrim.

  static const _oceanScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x8C05142D), Color(0x2605142D), Color(0xC705142D)],
    stops: [0.0, 0.4, 1.0],
  );

  static const _sunsetScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x59280A50), Color(0x00000000), Color(0x8C3C1400)],
    stops: [0.0, 0.4, 1.0],
  );

  static const _forestScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x4D001400), Color(0x00000000), Color(0xB3001400)],
    stops: [0.0, 0.35, 1.0],
  );

  static const _amethystScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x591E003C), Color(0x00000000), Color(0x8C1E003C)],
    stops: [0.0, 0.35, 1.0],
  );

  static const _fireScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x4D1E0000), Color(0x00000000), Color(0x661E0000)],
    stops: [0.0, 0.4, 1.0],
  );

  static const _stormScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x59050A19), Color(0x00000000), Color(0x99050A19)],
    stops: [0.0, 0.35, 1.0],
  );

  static const _goldScrim = LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [Color(0x66281900), Color(0x00000000), Color(0x73281900)],
    stops: [0.0, 0.3, 1.0],
  );

  static const teal = Skin(
    id: 'teal',
    name: 'Teal',
    seedColor: Color(0xFF00897B),
    titleWeight: FontWeight.w600,
    borderRadius: 12.0,
    borderWidth: 0.0,
    shadowElevation: 0.0,
    fabBorderRadius: 4.0,
    fabElevation: 0.0,
    appBarIntensity: AppBarIntensity.solid,
    appBarForegroundMode: AppBarForegroundMode.forceDark,
    radiusMultiplier: 1.0,
    heroAssetPath: null,
    fallbackGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFFAFEFD), Color(0xFFE0F2F1), Color(0xFFF5FDFC)],
      stops: [0.0, 0.5, 1.0],
    ),
    surfaceRenderMode: SurfaceRenderMode.cssTeal,
  );

  static const ocean = Skin(
    id: 'ocean',
    name: 'Ocean',
    seedColor: Color(0xFF1565C0),
    titleWeight: FontWeight.w400,
    borderRadius: 16.0,
    borderWidth: 0.0,
    shadowElevation: 1.0,
    fabBorderRadius: 16.0,
    fabElevation: 8.0,
    addContactIcon: Icons.sailing,
    addGroupIcon: Icons.waves,
    addChannelIcon: Icons.water,
    addIdentityIcon: Icons.anchor,
    appBarIntensity: AppBarIntensity.photo,
    radiusMultiplier: 1.3,
    heroAssetPath: 'assets/skins/ocean/hero.webp',
    fallbackGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0D2B52), Color(0xFF1565C0), Color(0xFF1E88E5)],
    ),
    surfaceRenderMode: SurfaceRenderMode.photo,
    scrimGradient: _oceanScrim,
    avatarAssetPath: 'assets/skins/ocean/avatar.webp',
    fabAssetPath: 'assets/skins/ocean/fab.webp',
  );

  static const sunset = Skin(
    id: 'sunset',
    name: 'Sunset',
    seedColor: Color(0xFFE65100),
    titleWeight: FontWeight.w500,
    borderRadius: 14.0,
    borderWidth: 0.0,
    shadowElevation: 1.0,
    fabBorderRadius: 16.0,
    fabElevation: 4.0,
    addContactIcon: Icons.wb_twilight,
    addGroupIcon: Icons.diversity_3,
    addChannelIcon: Icons.wb_sunny,
    addIdentityIcon: Icons.flare,
    appBarIntensity: AppBarIntensity.photo,
    radiusMultiplier: 1.2,
    heroAssetPath: 'assets/skins/sunset/hero.webp',
    fallbackGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF4A148C), Color(0xFFC2185B), Color(0xFFFF6F00), Color(0xFFFFA726)],
      stops: [0.0, 0.4, 0.8, 1.0],
    ),
    surfaceRenderMode: SurfaceRenderMode.photo,
    scrimGradient: _sunsetScrim,
    avatarAssetPath: 'assets/skins/sunset/avatar.webp',
    fabAssetPath: 'assets/skins/sunset/fab.webp',
  );

  static const forest = Skin(
    id: 'forest',
    name: 'Forest',
    seedColor: Color(0xFF2E7D32),
    titleWeight: FontWeight.w500,
    borderRadius: 10.0,
    borderWidth: 0.5,
    shadowElevation: 0.0,
    fabBorderRadius: 12.0,
    fabElevation: 2.0,
    fabBorderWidth: 1.0,
    addContactIcon: Icons.eco,
    addGroupIcon: Icons.forest,
    addChannelIcon: Icons.park,
    addIdentityIcon: Icons.spa,
    appBarIntensity: AppBarIntensity.photo,
    radiusMultiplier: 1.0,
    heroAssetPath: 'assets/skins/forest/hero.webp',
    fallbackGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF2E7D32), Color(0xFF1B5E20), Color(0xFF0B3D12)],
    ),
    surfaceRenderMode: SurfaceRenderMode.photo,
    scrimGradient: _forestScrim,
    avatarAssetPath: 'assets/skins/forest/avatar.webp',
    fabAssetPath: 'assets/skins/forest/fab.webp',
  );

  static const amethyst = Skin(
    id: 'amethyst',
    name: 'Amethyst',
    seedColor: Color(0xFF6A1B9A),
    titleWeight: FontWeight.w400,
    borderRadius: 8.0,
    borderWidth: 0.0,
    shadowElevation: 0.5,
    fabBorderRadius: 16.0,
    fabElevation: 10.0,
    addContactIcon: Icons.diamond,
    addGroupIcon: Icons.auto_awesome,
    addChannelIcon: Icons.hexagon,
    addIdentityIcon: Icons.diamond,
    appBarIntensity: AppBarIntensity.photo,
    radiusMultiplier: 0.8,
    heroAssetPath: 'assets/skins/amethyst/hero.webp',
    fallbackGradient: LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF2D0A4E), Color(0xFF4A148C), Color(0xFF6A1B9A), Color(0xFF280832)],
    ),
    surfaceRenderMode: SurfaceRenderMode.photo,
    scrimGradient: _amethystScrim,
    avatarAssetPath: 'assets/skins/amethyst/avatar.webp',
    fabAssetPath: 'assets/skins/amethyst/fab.webp',
  );

  static const fire = Skin(
    id: 'fire',
    name: 'Fire',
    seedColor: Color(0xFFC62828),
    titleWeight: FontWeight.w700,
    borderRadius: 6.0,
    borderWidth: 0.0,
    shadowElevation: 0.0,
    fabBorderRadius: 16.0,
    fabElevation: 0.0,
    addContactIcon: Icons.local_fire_department,
    addGroupIcon: Icons.whatshot,
    addChannelIcon: Icons.flare,
    addIdentityIcon: Icons.local_fire_department,
    appBarIntensity: AppBarIntensity.photo,
    radiusMultiplier: 0.6,
    heroAssetPath: 'assets/skins/fire/hero.webp',
    fallbackGradient: LinearGradient(
      begin: Alignment.bottomCenter,
      end: Alignment.topCenter,
      colors: [Color(0xFFFFEB3B), Color(0xFFFF9800), Color(0xFFC62828), Color(0xFF3A0A00), Color(0xFF1A0000)],
      stops: [0.0, 0.2, 0.5, 0.8, 1.0],
    ),
    surfaceRenderMode: SurfaceRenderMode.photo,
    scrimGradient: _fireScrim,
    peerDotColor: Color(0xFFFFAB00),
    avatarAssetPath: 'assets/skins/fire/avatar.webp',
    fabAssetPath: 'assets/skins/fire/fab.webp',
  );

  static const storm = Skin(
    id: 'storm',
    name: 'Storm',
    seedColor: Color(0xFF1A3A7A),
    titleWeight: FontWeight.w700,
    borderRadius: 6.0,
    borderWidth: 0.0,
    shadowElevation: 0.0,
    fabBorderRadius: 16.0,
    fabElevation: 0.0,
    addContactIcon: Icons.bolt,
    addGroupIcon: Icons.flash_on,
    addChannelIcon: Icons.electric_bolt,
    addIdentityIcon: Icons.bolt,
    appBarIntensity: AppBarIntensity.photo,
    appBarForegroundMode: AppBarForegroundMode.forceLight,
    radiusMultiplier: 0.6,
    heroAssetPath: 'assets/skins/storm/hero.webp',
    fallbackGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF050912), Color(0xFF0A1628), Color(0xFF1A2B4A), Color(0xFF2A3F5A)],
    ),
    surfaceRenderMode: SurfaceRenderMode.photo,
    scrimGradient: _stormScrim,
    peerDotColor: Color(0xFF64B5F6),
    avatarAssetPath: 'assets/skins/storm/avatar.webp',
    fabAssetPath: 'assets/skins/storm/fab.webp',
  );

  static const slate = Skin(
    id: 'slate',
    name: 'Slate',
    seedColor: Color(0xFF546E7A),
    fontFamily: 'monospace',
    titleWeight: FontWeight.w500,
    borderRadius: 4.0,
    borderWidth: 1.0,
    shadowElevation: 0.0,
    fabBorderRadius: 4.0,
    fabElevation: 0.0,
    fabBorderWidth: 2.0,
    addContactIcon: Icons.terminal,
    addGroupIcon: Icons.developer_board,
    addChannelIcon: Icons.data_object,
    addIdentityIcon: Icons.add_box,
    appBarIntensity: AppBarIntensity.solid,
    appBarForegroundMode: AppBarForegroundMode.forceLight,
    radiusMultiplier: 0.25,
    heroAssetPath: null,
    fallbackGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF0F1419), Color(0xFF151C22), Color(0xFF0C1115)],
    ),
    surfaceRenderMode: SurfaceRenderMode.cssSlate,
    peerDotColor: Color(0xFF69F0AE),
  );

  static const gold = Skin(
    id: 'gold',
    name: 'Gold',
    seedColor: Color(0xFFF9A825),
    titleWeight: FontWeight.w500,
    borderRadius: 16.0,
    borderWidth: 0.0,
    shadowElevation: 1.5,
    fabBorderRadius: 16.0,
    fabElevation: 8.0,
    addContactIcon: Icons.workspace_premium,
    addGroupIcon: Icons.emoji_events,
    addChannelIcon: Icons.military_tech,
    addIdentityIcon: Icons.star,
    appBarIntensity: AppBarIntensity.photo,
    radiusMultiplier: 1.4,
    heroAssetPath: 'assets/skins/gold/hero.webp',
    fallbackGradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [Color(0xFF3E2723), Color(0xFF5D4037), Color(0xFF8B6914), Color(0xFFDAA520), Color(0xFFFFD700)],
    ),
    surfaceRenderMode: SurfaceRenderMode.photo,
    scrimGradient: _goldScrim,
    avatarAssetPath: 'assets/skins/gold/avatar.webp',
    fabAssetPath: 'assets/skins/gold/fab.webp',
  );

  static const contrast = Skin(
    id: 'contrast',
    name: 'Contrast',
    seedColor: Color(0xFF000000),
    titleWeight: FontWeight.w800,
    borderRadius: 0.0,
    borderWidth: 3.0,
    shadowElevation: 0.0,
    fontSizeScale: 1.15,
    dividerThickness: 2.0,
    minTouchTarget: 56.0,
    forceBorders: true,
    fabBorderRadius: 0.0,
    fabElevation: 0.0,
    fabBorderWidth: 3.0,
    addContactIcon: Icons.person_add,
    addGroupIcon: Icons.group_add,
    addChannelIcon: Icons.campaign,
    addIdentityIcon: Icons.add,
    appBarIntensity: AppBarIntensity.brutalist,
    radiusMultiplier: 0.0,
    heroAssetPath: null,
    fallbackGradient: null,
    surfaceRenderMode: SurfaceRenderMode.brutalist,
    peerDotColor: Color(0xFF000000),
  );

  /// All available skins in display order.
  static const List<Skin> all = [
    teal,
    ocean,
    sunset,
    forest,
    amethyst,
    fire,
    storm,
    slate,
    gold,
    contrast,
  ];

  /// Look up a skin by id. Returns teal if not found.
  static Skin byId(String? id) {
    if (id == null) return teal;
    if (id == 'crimson') return fire;
    for (final s in all) {
      if (s.id == id) return s;
    }
    return teal;
  }
}
