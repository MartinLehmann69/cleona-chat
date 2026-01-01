// lib/ui/components/form_group.dart
import 'package:flutter/material.dart';
import 'package:cleona/ui/theme/theme_access.dart';

/// A themed container for arbitrary form inputs / list rows.
///
/// Visually matches [SectionCard] (accent-colored uppercase title header,
/// opaque body with subtle border + level1 elevation, rounded corners
/// derived from `tokens.radius.md * character.radiusMultiplier`), but
/// accepts a free `List<Widget> children` so it can host
/// `TextFormField`, `TextField`, `DropdownButtonFormField`, `ListTile`,
/// `SwitchListTile`, `RadioListTile`, plain `Divider`, `Padding`, etc.
///
/// Each non-first child is preceded by a hairline [Divider] for visual
/// separation. Children are wrapped with consistent horizontal padding
/// (`tokens.spacing.lg`); set [padRows] to `false` if the caller already
/// supplies its own padding (e.g. when embedding a `ListTile` which has
/// Material's built-in 16 px content padding).
class FormGroup extends StatelessWidget {
  final String title;
  final List<Widget> children;

  /// Whether to wrap each row in horizontal padding of `tokens.spacing.lg`.
  /// Defaults to `false` because the rows most commonly used here
  /// ([ListTile], [SwitchListTile], [RadioListTile]) already bring their
  /// own content padding. Set to `true` when hosting raw form fields.
  final bool padRows;

  /// Whether to insert a hairline divider between rows.
  final bool dividers;

  const FormGroup({
    super.key,
    required this.title,
    required this.children,
    this.padRows = false,
    this.dividers = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tokens = theme.tokens;
    final character = theme.character;
    final radius = tokens.radius.md * character.radiusMultiplier;
    final fg = theme.colorScheme.onPrimary;

    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0 && dividers) {
        rows.add(Divider(
          height: 1,
          thickness: 1,
          color: theme.colorScheme.outline.withValues(alpha: 0.05),
        ));
      }
      final child = children[i];
      if (padRows) {
        rows.add(Padding(
          padding: EdgeInsets.symmetric(horizontal: tokens.spacing.lg),
          child: child,
        ));
      } else {
        rows.add(child);
      }
    }

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
            ...rows,
          ],
        ),
      ),
    );
  }
}
