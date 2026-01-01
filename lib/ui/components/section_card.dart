// lib/ui/components/section_card.dart
import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/theme_access.dart';

class SectionCard extends StatelessWidget {
  final String title;
  final List<SectionRow> children;

  const SectionCard({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final character = theme.character;
    final radius = tokens.radius.md * character.radiusMultiplier;
    final fg = theme.colorScheme.onPrimary;

    return Padding(
      padding: EdgeInsets.only(
        left: tokens.spacing.lg,
        right: tokens.spacing.lg,
        bottom: tokens.spacing.md,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.1),
            width: 1,
          ),
          boxShadow: tokens.elevation.level1,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              color: character.accentColor,
              padding: EdgeInsets.symmetric(
                horizontal: tokens.spacing.lg,
                vertical: tokens.spacing.sm,
              ),
              child: Text(
                title.toUpperCase(),
                style: tokens.typography.label.copyWith(
                  color: fg,
                  letterSpacing: 1.0,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            ...children.asMap().entries.map((e) {
              final isFirst = e.key == 0;
              return Padding(
                padding: EdgeInsets.only(top: isFirst ? 0 : 0),
                child: e.value._build(context, isFirst),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class SectionRow {
  final String label;
  final String? value;
  final Widget? trailing;
  final bool? toggle;
  final ValueChanged<bool>? onToggleChanged;
  final VoidCallback? onTap;

  const SectionRow({
    required this.label,
    this.value,
    this.trailing,
    this.toggle,
    this.onToggleChanged,
    this.onTap,
  });

  Widget _build(BuildContext context, bool isFirst) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;

    final content = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: tokens.spacing.lg,
        vertical: tokens.spacing.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(label, style: tokens.typography.body),
          ),
          if (toggle != null)
            Switch(
              value: toggle!,
              onChanged: onToggleChanged,
            )
          else if (trailing != null)
            trailing!
          else if (value != null)
            Text(
              value!,
              style: tokens.typography.mono.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
        ],
      ),
    );

    return Column(
      children: [
        if (!isFirst)
          Divider(height: 1, thickness: 1, color: theme.colorScheme.outline.withValues(alpha: 0.05)),
        onTap != null
            ? InkWell(onTap: onTap, child: content)
            : content,
      ],
    );
  }
}
