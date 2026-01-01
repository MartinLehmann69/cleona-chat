// lib/ui/theme/theme_access.dart
import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/design_tokens.dart';
import 'package:cleona/ui/theme/character_profile.dart';

extension ThemeExtensionAccess on ThemeData {
  /// Safe accessor — falls back to DesignTokens.standard if extension missing.
  DesignTokens get tokens =>
      extension<DesignTokens>() ?? DesignTokens.standard;

  /// Safe accessor — falls back to CharacterProfile.standard if extension missing.
  CharacterProfile get character =>
      extension<CharacterProfile>() ?? CharacterProfile.standard;
}
