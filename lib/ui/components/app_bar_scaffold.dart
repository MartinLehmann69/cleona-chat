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

import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'package:cleona/core/update/binary_update_manager.dart';
import 'package:cleona/core/update/update_manifest.dart';
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
              const _GlobalUpdateBanner(),
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

class _GlobalUpdateBanner extends StatelessWidget {
  const _GlobalUpdateBanner();

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final manifest = appState.availableUpdateManifest;
    if (manifest == null || appState.updateBannerDismissed ||
        appState.service?.reducedMode == true) {
      return const SizedBox.shrink();
    }

    final locale = AppLocale.read(context);
    final state = appState.updateState;
    final progress = appState.updateProgress;
    final cs = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: state == BinaryUpdateState.idle
          ? appState.startInNetworkUpdate
          : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: cs.primaryContainer,
        child: Row(
          children: [
            Expanded(child: _content(state, progress, manifest, locale, cs)),
            if (state == BinaryUpdateState.idle ||
                state == BinaryUpdateState.failed ||
                state == BinaryUpdateState.ready)
              _actionButton(appState, state, locale, cs),
            if (state == BinaryUpdateState.idle)
              IconButton(
                icon: Icon(Icons.close, size: 18, color: cs.onPrimaryContainer),
                visualDensity: VisualDensity.compact,
                onPressed: appState.dismissUpdateBanner,
              ),
          ],
        ),
      ),
    );
  }

  Widget _content(BinaryUpdateState state, double progress,
      UpdateManifest manifest, AppLocale locale, ColorScheme cs) {
    switch (state) {
      case BinaryUpdateState.idle:
        return Text(
          '${locale.get('update_available_title')}: v${manifest.version}',
          style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
        );
      case BinaryUpdateState.checking:
        return Row(children: [
          const SizedBox(width: 80, child: LinearProgressIndicator()),
          const SizedBox(width: 8),
          Text(locale.get('update_verifying'),
              style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13)),
        ]);
      case BinaryUpdateState.downloading:
      case BinaryUpdateState.assembling:
      case BinaryUpdateState.verifying:
        final label = state == BinaryUpdateState.downloading
            ? locale.get('update_downloading')
            : state == BinaryUpdateState.assembling
                ? locale.get('update_assembling')
                : locale.get('update_verifying');
        final indeterminate = progress <= 0 || progress >= 1;
        return Row(children: [
          SizedBox(
            width: 80,
            child: indeterminate
                ? const LinearProgressIndicator()
                : LinearProgressIndicator(value: progress),
          ),
          const SizedBox(width: 8),
          Text(indeterminate ? '$label...' : '$label ${(progress * 100).toInt()}%',
              style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13)),
        ]);
      case BinaryUpdateState.ready:
        return const SizedBox.shrink();
      case BinaryUpdateState.failed:
        return Text(locale.get('update_failed'),
            style: TextStyle(color: cs.error, fontSize: 13));
    }
  }

  Widget _actionButton(CleonaAppState appState, BinaryUpdateState state,
      AppLocale locale, ColorScheme cs) {
    if (state == BinaryUpdateState.ready) {
      final label = Platform.isAndroid
          ? locale.get('update_ready_install')
          : locale.get('update_ready_restart');
      return TextButton(
        onPressed: appState.applyUpdate,
        child: Text(label, style: TextStyle(color: cs.onPrimaryContainer)),
      );
    }
    if (state == BinaryUpdateState.failed) {
      return TextButton(
        onPressed: appState.startInNetworkUpdate,
        child: Text(locale.get('update_retry'),
            style: TextStyle(color: cs.onPrimaryContainer)),
      );
    }
    return TextButton(
      onPressed: appState.startInNetworkUpdate,
      child: Text(locale.get('update_download'),
          style: TextStyle(color: cs.onPrimaryContainer)),
    );
  }
}
