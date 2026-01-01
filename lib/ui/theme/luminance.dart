// lib/ui/theme/luminance.dart
import 'package:flutter/material.dart';
import 'dart:math' show max, min;

/// Returns [Colors.black] or [Colors.white] depending on [bg] luminance.
/// Threshold 0.4 chosen to bias toward readability on medium-bright surfaces.
Color autoForeground(Color bg) {
  return bg.computeLuminance() > 0.4 ? Colors.black : Colors.white;
}

/// WCAG 2.1 contrast ratio between two colors.
/// Returns value between 1.0 (identical) and 21.0 (black on white).
double wcagContrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final lighter = max(la, lb);
  final darker = min(la, lb);
  return (lighter + 0.05) / (darker + 0.05);
}
