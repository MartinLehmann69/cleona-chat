import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/skin.dart';

/// The 9 predefined identity skins.
class Skins {
  Skins._();

  static const teal = Skin(
    id: 'teal',
    name: 'Teal',
    seedColor: Color(0xFF00897B),
    titleWeight: FontWeight.w600,
    borderRadius: 12.0,
    borderWidth: 0.0,
    shadowElevation: 0.0,
    // Icons: default
  );

  static const ocean = Skin(
    id: 'ocean',
    name: 'Ocean',
    seedColor: Color(0xFF1565C0),
    titleWeight: FontWeight.w400,
    borderRadius: 16.0,
    borderWidth: 0.0,
    shadowElevation: 1.0,
    fabBorderRadius: 20.0,
    fabElevation: 8.0,
    addContactIcon: Icons.sailing,
    addGroupIcon: Icons.waves,
    addChannelIcon: Icons.water,
    addIdentityIcon: Icons.anchor,
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
  );

  static const amethyst = Skin(
    id: 'amethyst',
    name: 'Amethyst',
    seedColor: Color(0xFF6A1B9A),
    titleWeight: FontWeight.w400,
    borderRadius: 8.0,
    borderWidth: 0.0,
    shadowElevation: 0.5,
    fabElevation: 10.0,
    addContactIcon: Icons.diamond,
    addGroupIcon: Icons.auto_awesome,
    addChannelIcon: Icons.hexagon,
    addIdentityIcon: Icons.diamond,
  );

  static const crimson = Skin(
    id: 'crimson',
    name: 'Crimson',
    seedColor: Color(0xFFC62828),
    titleWeight: FontWeight.w700,
    borderRadius: 6.0,
    borderWidth: 0.0,
    shadowElevation: 0.0,
    fabBorderRadius: 8.0,
    fabElevation: 0.0,
    addContactIcon: Icons.bolt,
    addGroupIcon: Icons.local_fire_department,
    addChannelIcon: Icons.electric_bolt,
    addIdentityIcon: Icons.bolt,
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
    fabBorderWidth: 1.5,
    addContactIcon: Icons.terminal,
    addGroupIcon: Icons.developer_board,
    addChannelIcon: Icons.data_object,
    addIdentityIcon: Icons.add_box,
  );

  static const gold = Skin(
    id: 'gold',
    name: 'Gold',
    seedColor: Color(0xFFF9A825),
    titleWeight: FontWeight.w500,
    borderRadius: 16.0,
    borderWidth: 0.0,
    shadowElevation: 1.5,
    fabBorderRadius: 24.0,
    fabElevation: 8.0,
    addContactIcon: Icons.workspace_premium,
    addGroupIcon: Icons.emoji_events,
    addChannelIcon: Icons.military_tech,
    addIdentityIcon: Icons.star,
  );

  static const contrast = Skin(
    id: 'contrast',
    name: 'Contrast',
    seedColor: Color(0xFF000000),
    titleWeight: FontWeight.w800,
    borderRadius: 4.0,
    borderWidth: 3.0,
    shadowElevation: 0.0,
    fontSizeScale: 1.15,
    dividerThickness: 2.0,
    minTouchTarget: 56.0,
    forceBorders: true,
    fabBorderRadius: 4.0,
    fabElevation: 0.0,
    fabBorderWidth: 3.0,
    addContactIcon: Icons.person_add,
    addGroupIcon: Icons.group_add,
    addChannelIcon: Icons.campaign,
    addIdentityIcon: Icons.add,
  );

  /// All available skins in display order.
  static const List<Skin> all = [
    teal,
    ocean,
    sunset,
    forest,
    amethyst,
    crimson,
    slate,
    gold,
    contrast,
  ];

  /// Look up a skin by id. Returns teal if not found.
  static Skin byId(String? id) {
    if (id == null) return teal;
    for (final s in all) {
      if (s.id == id) return s;
    }
    return teal;
  }
}
