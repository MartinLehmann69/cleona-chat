import 'package:flutter/material.dart';

/// A home-screen tab with an unread counter.
///
/// The counter stands BESIDE the label, not on top of it (S405 A-1). Until
/// S405 it was Flutter's Badge laid over the label with 8 px of room: Flutter
/// lets a counted badge reach 12 px into its child in LTR, and in RTL it
/// aligns the badge by its own width, so it reaches further the wider the
/// number is (measured in `smoke_tab_badge_layout`: 15.5 px for "5"). The red
/// circle covered the last letter ("Aktuel⁵", lab 05.10.2026) and OCR read
/// `Aktuel@9`. A Row follows the text direction by itself, so no padding
/// guesses a width.
///
/// Out of `home_screen.dart` so that `smoke_tab_badge_layout` can render it
/// on its own and measure counter against label.
Tab tabWithBadge(String label, int count) {
  if (count == 0) return Tab(text: label);
  return Tab(
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label),
        const SizedBox(width: 4),
        Badge(label: Text('$count')),
      ],
    ),
  );
}
