import 'package:flutter/material.dart';

@immutable
class Elevation {
  final List<BoxShadow> level0;
  final List<BoxShadow> level1;
  final List<BoxShadow> level2;
  final List<BoxShadow> level3;

  const Elevation({
    required this.level0,
    required this.level1,
    required this.level2,
    required this.level3,
  });

  static const Elevation standard = Elevation(
    level0: [],
    level1: [
      BoxShadow(blurRadius: 2, offset: Offset(0, 1), color: Color(0x0D000000)),
      BoxShadow(blurRadius: 3, offset: Offset(0, 1), color: Color(0x1A000000)),
    ],
    level2: [
      BoxShadow(blurRadius: 4, offset: Offset(0, 2), color: Color(0x14000000)),
      BoxShadow(blurRadius: 8, offset: Offset(0, 4), color: Color(0x26000000)),
    ],
    level3: [
      BoxShadow(blurRadius: 8, offset: Offset(0, 4), color: Color(0x1F000000)),
      BoxShadow(blurRadius: 24, offset: Offset(0, 8), color: Color(0x33000000)),
    ],
  );
}
