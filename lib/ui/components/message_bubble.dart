// lib/ui/components/message_bubble.dart
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/character_profile.dart';
import 'package:cleona/ui/theme/theme_access.dart';

class MessageBubble extends StatelessWidget {
  final String text;
  final bool isOwn;
  final String timestamp;
  final String? statusTicks;
  final String? replyTo;
  final List<String> reactions;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  /// Opens the message-actions menu (reply/react/copy/edit/delete/...).
  /// Architecture §18.6.2: every actionable bubble shows a 3-dot icon in the
  /// top-right corner. Long-press is a secondary gesture, not the primary
  /// affordance.
  final VoidCallback? onActionsPressed;

  /// When true, an active per-chat disappearing-message timer applies to this
  /// message — render a small timer glyph next to the timestamp so the user
  /// can see at a glance that the message will expire (gui-42).
  final bool expiryActive;

  const MessageBubble({
    super.key,
    required this.text,
    required this.isOwn,
    required this.timestamp,
    this.statusTicks,
    this.replyTo,
    this.reactions = const [],
    this.onTap,
    this.onLongPress,
    this.onActionsPressed,
    this.expiryActive = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final character = theme.character;
    final mode = character.surfaceRenderMode;
    final useBlur = mode == SurfaceRenderMode.photo;

    final baseRadius = tokens.radius.xl * character.radiusMultiplier;
    final flatCorner = tokens.radius.sm * character.radiusMultiplier;

    // Asymmetric corners: one flat corner on the avatar-adjacent side
    final radius = isOwn
        ? BorderRadius.only(
            topLeft: Radius.circular(baseRadius),
            topRight: Radius.circular(flatCorner),
            bottomLeft: Radius.circular(baseRadius),
            bottomRight: Radius.circular(baseRadius),
          )
        : BorderRadius.only(
            topLeft: Radius.circular(flatCorner),
            topRight: Radius.circular(baseRadius),
            bottomLeft: Radius.circular(baseRadius),
            bottomRight: Radius.circular(baseRadius),
          );

    // Photo-skin frosted glass: let the hero asset shine through. Match the
    // chat_list_tile / contact_tile pattern (50%-black neutral fill + 15%
    // white hairline border) so home-screen tiles and chat bubbles share one
    // visual language. Own bubbles add a subtle accent tint on top of the
    // neutral dark so sender vs partner is still distinguishable, but keep
    // the alpha low enough that the BackdropFilter blur is clearly visible
    // (saturated 0.78 accent fills were too opaque — the previous values
    // collapsed the frosted-glass effect into a flat-color bubble, which is
    // exactly the regression the user reported).
    final Color partnerPhotoFill = const Color(0x80000000); // rgba(0,0,0,0.5)
    final Color ownPhotoFill = Color.alphaBlend(
      character.accentColor.withValues(alpha: 0.45),
      const Color(0x80000000),
    );
    final bubbleColor = isOwn
        ? (useBlur ? ownPhotoFill : character.accentColor)
        : (useBlur ? partnerPhotoFill : theme.colorScheme.surface);
    final textColor = useBlur
        ? Colors.white
        : (isOwn ? Colors.white : theme.colorScheme.onSurface);

    // Photo mode mirrors the tile chrome: hairline white border, no shadow
    // (BackdropFilter does the depth cue). Solid skins keep the original
    // outline + elevation language.
    final Border? bubbleBorder = useBlur
        ? Border.all(color: const Color(0x26FFFFFF), width: 1) // 15% white
        : (isOwn
            ? null
            : Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)));

    final hasActions = onActionsPressed != null;
    Widget bubbleContainer = Container(
      constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
      padding: EdgeInsets.only(
        left: tokens.spacing.md,
        right: hasActions ? tokens.spacing.md + 20 : tokens.spacing.md,
        top: tokens.spacing.sm,
        bottom: tokens.spacing.sm,
      ),
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: useBlur ? null : radius,
        border: bubbleBorder,
        boxShadow: isOwn && !useBlur ? tokens.elevation.level1 : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (replyTo != null) ...[
            Container(
              padding: EdgeInsets.all(tokens.spacing.xs),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(tokens.radius.sm),
                border: Border(
                  left: BorderSide(color: textColor.withValues(alpha: 0.6), width: 2),
                ),
              ),
              child: Text(
                replyTo!,
                style: tokens.typography.caption.copyWith(color: textColor.withValues(alpha: 0.7)),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            SizedBox(height: tokens.spacing.xs),
          ],
          Text(
            text,
            style: tokens.typography.body.copyWith(
              color: textColor,
              shadows: useBlur
                  ? const [
                      Shadow(color: Color(0x99000000), blurRadius: 4, offset: Offset(0, 1)),
                    ]
                  : null,
            ),
          ),
          SizedBox(height: tokens.spacing.xs),
          Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: isOwn ? MainAxisAlignment.end : MainAxisAlignment.start,
            children: [
              Text(
                timestamp,
                style: tokens.typography.mono.copyWith(
                  color: textColor.withValues(alpha: 0.6),
                ),
              ),
              if (statusTicks != null) ...[
                SizedBox(width: tokens.spacing.xs),
                Text(
                  statusTicks!,
                  style: tokens.typography.mono.copyWith(
                    color: textColor.withValues(alpha: 0.6),
                  ),
                ),
              ],
              if (expiryActive) ...[
                SizedBox(width: tokens.spacing.xs),
                Icon(
                  Icons.timer_outlined,
                  size: tokens.typography.mono.fontSize ?? 12,
                  color: textColor.withValues(alpha: 0.6),
                ),
              ],
            ],
          ),
          if (reactions.isNotEmpty) ...[
            SizedBox(height: tokens.spacing.xs),
            Wrap(
              spacing: tokens.spacing.xs,
              children: reactions.map((r) => Text(r, style: const TextStyle(fontSize: 16))).toList(),
            ),
          ],
        ],
      ),
    );

    // Photo mode: frosted-glass blur so the skin hero asset shines through.
    // Same pattern as chat_list_tile.dart / contact_tile.dart (Architektur
    // §V3.1.70 Design-System, Photo-Mode component parity).
    if (useBlur) {
      bubbleContainer = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: bubbleContainer,
        ),
      );
    }

    final bubble = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: bubbleContainer,
    );

    final bubbleWithActions = hasActions
        ? Stack(
            clipBehavior: Clip.none,
            children: [
              bubble,
              Positioned(
                top: 0,
                right: 0,
                child: Semantics(
                  label: 'message_actions',
                  button: true,
                  child: InkWell(
                    onTap: onActionsPressed,
                    customBorder: const CircleBorder(),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.more_vert,
                        size: 16,
                        color: textColor.withValues(alpha: 0.7),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          )
        : bubble;

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.xs,
        ),
        child: bubbleWithActions,
      ),
    );
  }
}
