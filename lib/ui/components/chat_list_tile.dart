// lib/ui/components/chat_list_tile.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/theme_access.dart';
import 'package:cleona/ui/theme/character_profile.dart';

class ChatListTile extends StatelessWidget {
  final String name;
  final String preview;
  final String timestamp;
  final int unreadCount;
  final bool isOnline;
  final Widget? avatarOverride;
  final VoidCallback? onTap;

  const ChatListTile({
    super.key,
    required this.name,
    required this.preview,
    required this.timestamp,
    required this.unreadCount,
    required this.isOnline,
    this.avatarOverride,
    this.onTap,
  });

  // ── Card chrome ──────────────────────────────────────────────────────────

  BoxDecoration _cardDecoration(SurfaceRenderMode mode) {
    switch (mode) {
      case SurfaceRenderMode.photo:
        return BoxDecoration(
          color: const Color(0x80000000), // rgba(0,0,0,0.5)
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0x26FFFFFF), // rgba(255,255,255,0.15)
            width: 1,
          ),
        );
      case SurfaceRenderMode.cssTeal:
        return BoxDecoration(
          color: const Color(0xCCFFFFFF), // rgba(255,255,255,0.8)
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: const Color(0x3300897B), // rgba(0,137,123,0.2)
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
        return const Color(0xFF00E5FF); // cyan
      case SurfaceRenderMode.brutalist:
        return const Color(0xFF000000);
    }
  }

  Color _previewColor(SurfaceRenderMode mode) {
    switch (mode) {
      case SurfaceRenderMode.photo:
        return const Color(0xCCFFFFFF); // 80% white
      case SurfaceRenderMode.cssTeal:
        return const Color(0xCC000000); // 80% black
      case SurfaceRenderMode.cssSlate:
        return const Color(0xCC69F0AE); // 80% green
      case SurfaceRenderMode.brutalist:
        return const Color(0xCC000000);
    }
  }

  Color _timestampColor(SurfaceRenderMode mode) {
    switch (mode) {
      case SurfaceRenderMode.photo:
        return const Color(0xC7FFFFFF); // ~78% white
      case SurfaceRenderMode.cssTeal:
        return const Color(0xC7000000);
      case SurfaceRenderMode.cssSlate:
        return const Color(0xC700E5FF); // ~78% cyan
      case SurfaceRenderMode.brutalist:
        return const Color(0xC7000000);
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
                  color: const Color(0x4DFFFFFF), // rgba(255,255,255,0.3)
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
                color: Color(0xFFFFFF00), // yellow
                fontSize: 14,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        );
    }
  }

  // ── Online dot ────────────────────────────────────────────────────────────

  Widget _buildOnlineDot(SurfaceRenderMode mode) {
    final dotColor = mode == SurfaceRenderMode.brutalist
        ? const Color(0xFF000000)
        : const Color(0xFF4CAF50);
    final borderColor = mode == SurfaceRenderMode.photo
        ? const Color(0x4D000000)
        : (mode == SurfaceRenderMode.cssSlate
            ? const Color(0xFF0f1419)
            : Colors.transparent);
    return Container(
      width: 10,
      height: 10,
      decoration: BoxDecoration(
        color: dotColor,
        shape: BoxShape.circle,
        border: Border.all(color: borderColor, width: 1.5),
      ),
    );
  }

  // ── Unread badge ──────────────────────────────────────────────────────────

  BoxDecoration _badgeDecoration(SurfaceRenderMode mode, Color accentColor) {
    switch (mode) {
      case SurfaceRenderMode.photo:
        return BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(6),
        );
      case SurfaceRenderMode.cssTeal:
        return BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(6),
        );
      case SurfaceRenderMode.cssSlate:
        return BoxDecoration(
          color: const Color(0xFF00E5FF),
          borderRadius: BorderRadius.circular(6),
        );
      case SurfaceRenderMode.brutalist:
        return BoxDecoration(
          color: const Color(0xFFFFFF00),
          borderRadius: BorderRadius.zero,
          border: Border.all(color: const Color(0xFF000000), width: 2),
        );
    }
  }

  Color _badgeTextColor(SurfaceRenderMode mode) {
    switch (mode) {
      case SurfaceRenderMode.photo:
      case SurfaceRenderMode.cssTeal:
        return Colors.white;
      case SurfaceRenderMode.cssSlate:
        return const Color(0xFF000000);
      case SurfaceRenderMode.brutalist:
        return const Color(0xFF000000);
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

    final cardDecoration = _cardDecoration(mode);
    final useBlur = mode == SurfaceRenderMode.photo;

    Widget cardContent = Container(
      decoration: cardDecoration,
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              avatarOverride ??
                  _buildAvatar(mode, character.accentColor, character.avatarAssetPath),
              if (isOnline)
                Positioned(
                  right: -2,
                  bottom: -2,
                  child: _buildOnlineDot(mode),
                ),
            ],
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        mode == SurfaceRenderMode.brutalist
                            ? name.toUpperCase()
                            : name,
                        style: _nameStyle(mode),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      timestamp,
                      style: TextStyle(
                        fontSize: 10,
                        fontFamily: 'SF Mono',
                        color: _timestampColor(mode),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        preview,
                        style: TextStyle(
                          fontSize: 11,
                          color: _previewColor(mode),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (unreadCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: _badgeDecoration(mode, character.accentColor),
                        child: Text(
                          unreadCount.toString(),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: _badgeTextColor(mode),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
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
