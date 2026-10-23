import 'package:flutter/material.dart';
import 'package:lazerus_core/lazerus_core.dart';

Color colorFromRgb(RgbColor color) =>
    Color.fromARGB(255, color.red, color.green, color.blue);

RgbColor rgbFromColor(Color color) => RgbColor(
  (color.r * 255).round(),
  (color.g * 255).round(),
  (color.b * 255).round(),
);

/// The initial Lotus X profile accepts saturated colours from red through
/// violet. Keeping the picker on this finite hue arc means it never produces
/// white or black RGB commands for that controller family.
const double lotusHueStart = 0;
const double lotusHueEnd = 285;

RgbColor lotusHueColor(double value) {
  final hue =
      lotusHueStart + (lotusHueEnd - lotusHueStart) * value.clamp(0.0, 1.0);
  final color = HSVColor.fromAHSV(1, hue, 1, 1).toColor();
  return rgbFromColor(color);
}

double lotusHueValueFor(RgbColor color) {
  final hsv = HSVColor.fromColor(colorFromRgb(color));
  final hue = hsv.saturation == 0 || hsv.value == 0
      ? lotusHueStart
      : hsv.hue.clamp(lotusHueStart, lotusHueEnd);
  return ((hue - lotusHueStart) / (lotusHueEnd - lotusHueStart)).clamp(
    0.0,
    1.0,
  );
}

const List<Color> lotusHueGradient = <Color>[
  Colors.red,
  Color(0xFFFF9800),
  Colors.yellow,
  Color(0xFF00C853),
  Colors.cyan,
  Color(0xFF2979FF),
  Color(0xFF8E24AA),
];
