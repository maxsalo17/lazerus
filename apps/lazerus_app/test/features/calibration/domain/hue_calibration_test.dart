import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/calibration/domain/hue_calibration.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  final profile = HueCalibrationProfile(
    id: 'warm-strip',
    name: 'Warm strip correction',
    protocolId: 'lazerus.protocol.lotus_lamp_x',
    hueStartDegrees: 0,
    hueEndDegrees: 285,
    anchors: const <HueCalibrationAnchor>[
      HueCalibrationAnchor(input: 0, output: 0),
      HueCalibrationAnchor(input: .5, output: .75),
      HueCalibrationAnchor(input: 1, output: 1),
    ],
  );

  test('interpolates a monotonic hue curve', () {
    expect(profile.mapNormalizedHue(.25), closeTo(.375, .000001));
    expect(profile.mapNormalizedHue(.5), .75);
    expect(profile.mapNormalizedHue(.75), closeTo(.875, .000001));
  });

  test('maps supported hue while preserving neutral colours', () {
    final desiredOrange = RgbColor(255, 128, 0);
    final mapped = profile.mapColor(desiredOrange);

    expect(mapped, isNot(desiredOrange));
    expect(mapped.red, 255);
    expect(mapped.green, greaterThan(desiredOrange.green));
    expect(profile.mapColor(RgbColor(0, 0, 0)), RgbColor(0, 0, 0));
    expect(profile.mapColor(RgbColor(255, 255, 255)), RgbColor(255, 255, 255));
  });

  test(
    'serializes a versioned configuration and filters dangling assignments',
    () {
      final configuration = DeviceCalibrationConfiguration(
        profiles: <HueCalibrationProfile>[profile],
        assignments: const <String, String>{
          'device-a': 'warm-strip',
          'orphan': 'missing',
        },
      );

      final decoded = DeviceCalibrationConfiguration.fromJson(
        configuration.toJson(),
      );

      expect(decoded, isNotNull);
      expect(
        decoded!.profileForDevice('device-a')!.name,
        'Warm strip correction',
      );
      expect(decoded.profileForDevice('orphan'), isNull);
    },
  );

  test('rejects an invalid curve and unsupported schema', () {
    expect(
      HueCalibrationProfile.fromJson(<String, Object>{
        'id': 'invalid',
        'name': 'Invalid',
        'protocolId': 'protocol',
        'hueStartDegrees': 0,
        'hueEndDegrees': 285,
        'anchors': <Object>[
          <String, Object>{'input': 0, 'output': 0},
          <String, Object>{'input': .5, 'output': .9},
          <String, Object>{'input': 1, 'output': .8},
        ],
      }),
      isNull,
    );
    expect(
      DeviceCalibrationConfiguration.fromJson(<String, Object>{
        'schemaVersion': 99,
        'profiles': const <Object>[],
        'assignments': const <String, String>{},
      }),
      isNull,
    );
  });
}
