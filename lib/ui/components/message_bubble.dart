// lib/ui/components/message_bubble.dart
import 'package:flutter/material.dart';
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
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final character = theme.character;

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

    final bubbleColor = isOwn
        ? character.accentColor
        : theme.colorScheme.surface;
    final textColor = isOwn
        ? Colors.white
        : theme.colorScheme.onSurface;

    final bubble = GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.sm,
        ),
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: radius,
          border: isOwn ? null : Border.all(color: theme.colorScheme.outline.withValues(alpha: 0.2)),
          boxShadow: isOwn ? tokens.elevation.level1 : null,
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
            Text(text, style: tokens.typography.body.copyWith(color: textColor)),
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
      ),
    );

    return Align(
      alignment: isOwn ? Alignment.centerRight : Alignment.centerLeft,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: tokens.spacing.md,
          vertical: tokens.spacing.xs,
        ),
        child: bubble,
      ),
    );
  }
}
