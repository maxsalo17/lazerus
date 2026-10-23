import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/control/presentation/color_utils.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'Lotus hue picker only produces saturated colours from red to violet',
    () {
      for (final value in <double>[0, .25, .5, .75, 1]) {
        final color = lotusHueColor(value);
        expect(color, isNot(RgbColor(0, 0, 0)));
        expect(color, isNot(RgbColor(255, 255, 255)));
      }

      final red = lotusHueColor(0);
      expect(red.red, 255);
      expect(red.green, 0);
      expect(red.blue, 0);
      final violet = lotusHueColor(1);
      expect(violet.red, greaterThan(0));
      expect(violet.blue, greaterThan(0));
      expect(violet.green, 0);
    },
  );

  test(
    'black or white legacy values begin at the valid red end of the arc',
    () {
      expect(lotusHueValueFor(RgbColor(0, 0, 0)), 0);
      expect(lotusHueValueFor(RgbColor(255, 255, 255)), 0);
    },
  );
}
