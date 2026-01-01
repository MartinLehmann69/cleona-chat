import 'package:flutter/material.dart';

@immutable
class CleonaTypography {
  final TextStyle display;
  final TextStyle headline;
  final TextStyle title;
  final TextStyle body;
  final TextStyle label;
  final TextStyle caption;
  final TextStyle mono;

  const CleonaTypography({
    required this.display,
    required this.headline,
    required this.title,
    required this.body,
    required this.label,
    required this.caption,
    required this.mono,
  });

  static const CleonaTypography standard = CleonaTypography(
    display:  TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.5),
    headline: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
    title:    TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
    body:     TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.4),
    label:    TextStyle(fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0.5),
    caption:  TextStyle(fontSize: 11, fontWeight: FontWeight.w400),
    mono:     TextStyle(fontSize: 12, fontFamily: 'SF Mono', fontWeight: FontWeight.w500),
  );
}
