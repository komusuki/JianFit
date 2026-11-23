import 'package:flutter/material.dart';

/// Color sets the user can pick in Settings (design canvas H1 to H4).
///
/// [primary] is the darker shade, so text buttons and links stay readable on
/// white. [fill] is the bright shade for containers, with [onFill] text on it.
/// [highlight] marks selections (strictness, tabs), with [onHighlight] text.
/// Camera screens keep their own meaning colors (green good rep, red missed
/// rep, amber cue) whichever set is picked.
enum AppPalette {
  greenYellow(
    label: 'Green and yellow',
    primary: Color(0xFF00775A),
    fill: Color(0xFF00C48C),
    onFill: Color(0xFF0B2E25),
    highlight: Color(0xFFFFD21F),
    onHighlight: Color(0xFF0B2E25),
  ),
  blueLime(
    label: 'Blue and lime',
    primary: Color(0xFF2448E0),
    fill: Color(0xFF2D5BFF),
    onFill: Color(0xFFFFFFFF),
    highlight: Color(0xFFC6F432),
    onHighlight: Color(0xFF0B1B3F),
  ),
  coralPlum(
    label: 'Coral and plum',
    primary: Color(0xFFC8174C),
    fill: Color(0xFFFF3D71),
    onFill: Color(0xFF2A0E2E),
    highlight: Color(0xFFFFC2D3),
    onHighlight: Color(0xFF2A0E2E),
  ),
  redNavy(
    label: 'Red and navy',
    primary: Color(0xFFC0102F),
    fill: Color(0xFFD9143A),
    onFill: Color(0xFFFFFFFF),
    highlight: Color(0xFFDCE2F5),
    onHighlight: Color(0xFF12204A),
  );

  const AppPalette({
    required this.label,
    required this.primary,
    required this.fill,
    required this.onFill,
    required this.highlight,
    required this.onHighlight,
  });

  final String label;
  final Color primary;
  final Color fill;
  final Color onFill;
  final Color highlight;
  final Color onHighlight;

  ColorScheme get colorScheme => ColorScheme.fromSeed(
    seedColor: primary,
    primary: primary,
    onPrimary: Colors.white,
    primaryContainer: fill,
    onPrimaryContainer: onFill,
    secondaryContainer: highlight,
    onSecondaryContainer: onHighlight,
  );
}
