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
import 'package:provider/provider.dart';
import 'package:cleona/main.dart';
import 'package:cleona/core/i18n/app_locale.dart';
import 'dart:io' show Platform;

import 'package:cleona/core/update/binary_update_manager.dart';
import 'package:cleona/core/update/update_offer.dart';
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
              const _GlobalCoAuthWarningBanner(),
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
    final state = appState.updateState;
    final pending = appState.updateApplyPending;
    // ── ONLY WHAT IS FINISHED (owner decision 14.09.2026, S387) ───────────
    //
    // The banner appears when the update is complete AND verified —
    // not for a known manifest, not during collecting. Until
    // S387 it showed "Update available" + [Download] and on `ready`
    // "being installed", because `ready` back then already was the installation.
    if (manifest == null ||
        appState.service?.reducedMode == true ||
        !UpdateOffer.bannerVisible(
          state: state,
          dismissed: appState.updateBannerDismissed,
          installedCurrently: pending,
        )) {
      return const SizedBox.shrink();
    }

    final locale = AppLocale.read(context);
    final needsPermission = appState.updateNeedsInstallPermission;
    final cs = Theme.of(context).colorScheme;

    if (needsPermission && state == BinaryUpdateState.ready) {
      return _permissionHint(appState, locale, cs);
    }

    return GestureDetector(
      onTap: pending ? null : appState.applyUpdate,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        color: cs.primaryContainer,
        child: Row(
          children: [
            Expanded(child: _content(pending, manifest, locale, cs)),
            if (!pending) ...[
              IconButton(
                icon: Icon(Icons.system_update_alt,
                    size: 20, color: cs.onPrimaryContainer),
                tooltip: _readyLabel(locale),
                visualDensity: VisualDensity.compact,
                onPressed: appState.applyUpdate,
              ),
              IconButton(
                icon: Icon(Icons.close, size: 18, color: cs.onPrimaryContainer),
                visualDensity: VisualDensity.compact,
                onPressed: appState.dismissUpdateBanner,
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// "Update ready — tap to install" (Android) or "— restart
  /// required" (desktop). Existing keys, all 34 languages.
  String _readyLabel(AppLocale locale) => Platform.isAndroid
      ? locale.get('update_ready_install')
      : locale.get('update_ready_restart');

  Widget _permissionHint(
      CleonaAppState appState, AppLocale locale, ColorScheme cs) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: cs.primaryContainer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            locale.get('update_install_permission_hint'),
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: appState.cancelUpdate,
                child: Text(locale.get('update_cancel'),
                    style: TextStyle(color: cs.onPrimaryContainer, fontSize: 12)),
              ),
              const SizedBox(width: 8),
              TextButton(
                onPressed: appState.retryInstallPermission,
                child: Text(locale.get('update_install_permission_retry'),
                    style: TextStyle(
                        color: cs.onPrimaryContainer,
                        fontSize: 12,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _content(bool pending, UpdateManifest manifest, AppLocale locale,
      ColorScheme cs) {
    if (pending) {
      return Row(children: [
        const SizedBox(
          width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 8),
        Text('${locale.get('update_installing')}...',
            style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13)),
      ]);
    }
    return Text('${_readyLabel(locale)} (v${manifest.version})',
        style: TextStyle(color: cs.onPrimaryContainer, fontSize: 13));
  }
}

/// §7.5: "rotation quorum not met" warnings — the elevated "possible Primary
/// theft" signal. Shown the same way as [_GlobalUpdateBanner] (every screen,
/// via the shared [AppBarScaffold]) rather than as a one-shot dialog: unlike
/// the pairing/rotation-approval prompts this is purely informational (there
/// is nothing to answer), so it must stay visible until the user explicitly
/// acknowledges it — a transient dialog the user could miss while looking
/// elsewhere would defeat the point of a theft warning.
class _GlobalCoAuthWarningBanner extends StatelessWidget {
  const _GlobalCoAuthWarningBanner();

  /// One banner row. Every §7.5/§14.5 security notice renders through this so
  /// the three kinds cannot drift apart in shape — only in words and icon.
  static Widget _line({
    required ColorScheme cs,
    required IconData icon,
    required String title,
    required String body,
    required VoidCallback close,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: cs.errorContainer,
      child: Row(
        children: [
          Icon(icon, size: 18, color: cs.onErrorContainer),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: cs.onErrorContainer,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
                Text(
                  body,
                  style: TextStyle(color: cs.onErrorContainer, fontSize: 13),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 18, color: cs.onErrorContainer),
            visualDensity: VisualDensity.compact,
            onPressed: close,
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final appState = context.watch<CleonaAppState>();
    final warnings = appState.coAuthWarnings;
    // S360: the two other §14.5 messages did not reach the UI
    // at all — their callbacks were never assigned in `main.dart`
    // (reasoned there). They stand here because they have the same property
    // as the quorum warning: nothing to answer, but nothing that
    // a dialog may briefly show and take away again.
    final rotations = appState.contactRotationNotices;
    final rejections = appState.rotationRejections;
    if (warnings.isEmpty && rotations.isEmpty && rejections.isEmpty) {
      return const SizedBox.shrink();
    }

    final locale = AppLocale.read(context);
    final cs = Theme.of(context).colorScheme;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Order by severity: an ACTIVE rejection by a device
        // is the strongest theft signal (§7.5), the missed quorum the
        // second strongest, the mere rotation the weakest.
        for (final r in rejections)
          _line(
            cs: cs,
            icon: Icons.gpp_bad,
            title: locale.get('rotation_rejection_alert'),
            body: locale
                .tr('rotation_rejection_alert_body', {'name': r.displayName}),
            close: () =>
                appState.dismissRotationRejection(r.contactNodeIdHex),
          ),
        for (final w in warnings)
          _line(
            cs: cs,
            icon: Icons.gpp_maybe,
            title: locale.get('rotation_coauth_warning_title'),
            body: locale.tr('rotation_coauth_warning_body', {
              'name': w.displayName,
              'present': '${w.tokensPresent}',
              'required': '${w.tokensRequired}',
            }),
            close: () =>
                appState.dismissCoAuthWarning(w.contactNodeIdHex),
          ),
        for (final n in rotations)
          _line(
            cs: cs,
            icon: Icons.vpn_key_off,
            title: locale.get('contact_identity_rotated_title'),
            body: locale.tr(
                n.wasVerified
                    ? 'contact_identity_rotated_body_verified'
                    : 'contact_identity_rotated_body',
                {'name': n.displayName}),
            close: () =>
                appState.dismissContactRotationNotice(n.contactNodeIdHex),
          ),
      ],
    );
  }
}
