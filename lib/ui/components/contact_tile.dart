// lib/ui/components/contact_tile.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/theme_access.dart';
import 'package:cleona/ui/theme/character_profile.dart';

enum ContactVerification { unverified, seen, verified, trusted }

class ContactTile extends StatelessWidget {
  final String name;
  final String status;
  final ContactVerification verificationLevel;
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? avatarOverride;

  const ContactTile({
    super.key,
    required this.name,
    required this.status,
    required this.verificationLevel,
    this.trailing,
    this.onTap,
    this.avatarOverride,
  });

  // ── Verification icon / colour ────────────────────────────────────────────

  IconData _levelIcon() {
    switch (verificationLevel) {
      case ContactVerification.unverified:
        return Icons.help_outline;
      case ContactVerification.seen:
        return Icons.remove_red_eye_outlined;
      case ContactVerification.verified:
        return Icons.verified_outlined;
      case ContactVerification.trusted:
        return Icons.verified;
    }
  }

  Color _levelColor(SurfaceRenderMode mode, ColorScheme scheme) {
    switch (verificationLevel) {
      case ContactVerification.unverified:
        return mode == SurfaceRenderMode.photo
            ? Colors.white.withValues(alpha: 0.4)
            : scheme.onSurface.withValues(alpha: 0.4);
      case ContactVerification.seen:
        return mode == SurfaceRenderMode.photo
            ? Colors.white.withValues(alpha: 0.6)
            : scheme.primary.withValues(alpha: 0.6);
      case ContactVerification.verified:
        return mode == SurfaceRenderMode.photo
            ? Colors.white
            : scheme.primary;
      case ContactVerification.trusted:
        return const Color(0xFF2E7D32);
    }
  }

  // ── Card chrome ───────────────────────────────────────────────────────────

  BoxDecoration _cardDecoration(SurfaceRenderMode mode) {
    switch (mode) {
      case SurfaceRenderMode.photo:
        return BoxDecoration(
          color: const Color(0x80000000),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0x26FFFFFF),
            width: 1,
          ),
        );
      case SurfaceRenderMode.cssTeal:
        return BoxDecoration(
          color: const Color(0xCCFFFFFF),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0x3300897B),
            width: 1,
          ),
        );
      case SurfaceRenderMode.cssSlate:
        return BoxDecoration(
          color: const Color(0xFF1e272e),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0xFF263238),
            width: 1,
          ),
        );
      case SurfaceRenderMode.brutalist:
        return BoxDecoration(
          color: const Color(0xFFFFFFFF),
          borderRadius: BorderRadius.zero,
          border: Border.all(
            color: const Color(0xFF000000),
            width: 2.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Color(0xFF000000),
              offset: Offset(4, 4),
              blurRadius: 0,
            ),
          ],
        );
    }
  }

  // ── Text colours ──────────────────────────────────────────────────────────

  Color _nameColor(SurfaceRenderMode mode) {
    switch (mode) {
      case SurfaceRenderMode.photo:
        return const Color(0xFFFFFFFF);
      case SurfaceRenderMode.cssTeal:
        return const Color(0xFF000000);
      case SurfaceRenderMode.cssSlate:
        return const Color(0xFF00E5FF);
      case SurfaceRenderMode.brutalist:
        return const Color(0xFF000000);
    }
  }

  Color _statusColor(SurfaceRenderMode mode) {
    switch (mode) {
      case SurfaceRenderMode.photo:
        return const Color(0xCCFFFFFF);
      case SurfaceRenderMode.cssTeal:
        return const Color(0xCC000000);
      case SurfaceRenderMode.cssSlate:
        return const Color(0xCC69F0AE);
      case SurfaceRenderMode.brutalist:
        return const Color(0xCC000000);
    }
  }

  // ── Small avatar (36×36) ──────────────────────────────────────────────────

  Widget _buildAvatar(
    SurfaceRenderMode mode,
    Color accentColor,
    String? avatarAssetPath,
  ) {
    final initial = name.isNotEmpty ? name[0].toUpperCase() : '?';

    switch (mode) {
      case SurfaceRenderMode.photo:
        final avatarDecoration = avatarAssetPath != null
            ? BoxDecoration(
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: const Color(0x4DFFFFFF),
                  width: 1,
                ),
                image: DecorationImage(
                  image: AssetImage(avatarAssetPath),
                  fit: BoxFit.cover,
                ),
              )
            : BoxDecoration(
                color: accentColor,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: const Color(0x4DFFFFFF),
                  width: 1,
                ),
              );
        return Container(
          width: 36,
          height: 36,
          decoration: avatarDecoration,
          child: avatarAssetPath == null
              ? Center(
                  child: Text(
                    initial,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                )
              : null,
        );

      case SurfaceRenderMode.cssTeal:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [accentColor, accentColor.withValues(alpha: 0.7)],
            ),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Center(
            child: Text(
              initial,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        );

      case SurfaceRenderMode.cssSlate:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF0f1419),
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: const Color(0xFF00E5FF), width: 1),
          ),
          child: Center(
            child: Text(
              '[$initial]',
              style: const TextStyle(
                color: Color(0xFF00E5FF),
                fontSize: 10,
                fontWeight: FontWeight.w700,
                fontFamily: 'SF Mono',
              ),
            ),
          ),
        );

      case SurfaceRenderMode.brutalist:
        return Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: const Color(0xFF000000),
            borderRadius: BorderRadius.zero,
            border: Border.all(color: const Color(0xFF000000), width: 2.5),
          ),
          child: Center(
            child: Text(
              initial,
              style: const TextStyle(
                color: Color(0xFFFFFF00),
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
    }
  }

  // ── Name style ────────────────────────────────────────────────────────────

  TextStyle _nameStyle(SurfaceRenderMode mode) {
    final base = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w800,
      color: _nameColor(mode),
    );
    if (mode == SurfaceRenderMode.brutalist) {
      return base.copyWith(letterSpacing: 0.5);
    }
    return base;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final character = theme.character;
    final mode = character.surfaceRenderMode;
    final useBlur = mode == SurfaceRenderMode.photo;
    final levelColor = _levelColor(mode, theme.colorScheme);

    Widget cardContent = Container(
      decoration: _cardDecoration(mode),
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              avatarOverride ??
                  _buildAvatar(mode, character.accentColor, character.avatarAssetPath),
              Positioned(
                right: -3,
                bottom: -3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: mode == SurfaceRenderMode.photo
                        ? const Color(0x4D000000)
                        : theme.colorScheme.surface,
                    shape: BoxShape.circle,
                    border: Border.all(color: levelColor, width: 1.5),
                  ),
                  child: Icon(
                    _levelIcon(),
                    size: 10,
                    color: levelColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  mode == SurfaceRenderMode.brutalist
                      ? name.toUpperCase()
                      : name,
                  style: _nameStyle(mode),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  status,
                  style: TextStyle(
                    fontSize: 11,
                    color: _statusColor(mode),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 8),
            trailing!,
          ],
        ],
      ),
    );

    // Photo mode: wrap in ClipRRect + BackdropFilter for frosted-glass blur
    if (useBlur) {
      cardContent = ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: cardContent,
        ),
      );
    }

    return InkWell(
      onTap: onTap,
      borderRadius: mode == SurfaceRenderMode.brutalist
          ? BorderRadius.zero
          : BorderRadius.circular(12),
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.lg,
          vertical: tokens.spacing.xs,
        ),
        child: cardContent,
      ),
    );
  }
}
