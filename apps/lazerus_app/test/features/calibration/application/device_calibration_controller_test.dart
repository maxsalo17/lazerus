import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/calibration/application/device_calibration_controller.dart';
import 'package:lazerus_app/features/calibration/data/device_calibration_repository.dart';
import 'package:lazerus_app/features/calibration/domain/hue_calibration.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test('copy-on-save assigns a new profile only to selected devices', () async {
    final existing = _profile(id: 'existing', name: 'Existing correction');
    final repository = InMemoryDeviceCalibrationRepository();
    await repository.save(
      DeviceCalibrationConfiguration(
        profiles: <HueCalibrationProfile>[existing],
        assignments: const <String, String>{
          'selected': 'existing',
          'unselected': 'existing',
        },
      ),
    );
    final container = ProviderContainer(
      overrides: [
        deviceCalibrationRepositoryProvider.overrideWithValue(repository),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(deviceCalibrationProvider.notifier);
    await _settle();

    final saved = await controller.saveForDevices(
      appDeviceIds: const <String>{'selected'},
      draft: existing.copyWith(name: 'Selected correction'),
    );

    expect(saved, isTrue);
    final configuration = container
        .read(deviceCalibrationProvider)
        .configuration;
    expect(configuration.assignments['unselected'], 'existing');
    expect(configuration.assignments['selected'], isNot('existing'));
    expect(
      configuration.profileForDevice('selected')!.name,
      'Selected correction',
    );
  });

  test('uses an editor preview before the saved device assignment', () async {
    final container = ProviderContainer(
      overrides: [
        deviceCalibrationRepositoryProvider.overrideWithValue(
          InMemoryDeviceCalibrationRepository(),
        ),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(deviceCalibrationProvider.notifier);
    await _settle();
    final desired = RgbColor(255, 128, 0);
    final profile = _profile(id: 'draft', name: 'Draft');

    expect(
      controller.mapColorForDevice(
        appDeviceId: 'device',
        protocolId: profile.protocolId,
        color: desired,
      ),
      desired,
    );

    controller.preview(
      appDeviceIds: const <String>{'device'},
      profile: profile,
    );
    expect(
      controller.mapColorForDevice(
        appDeviceId: 'device',
        protocolId: profile.protocolId,
        color: desired,
      ),
      isNot(desired),
    );

    controller.clearPreview(const <String>{'device'});
    expect(
      controller.mapColorForDevice(
        appDeviceId: 'device',
        protocolId: profile.protocolId,
        color: desired,
      ),
      desired,
    );
  });
}

HueCalibrationProfile _profile({required String id, required String name}) {
  return HueCalibrationProfile(
    id: id,
    name: name,
    protocolId: 'lazerus.protocol.lotus_lamp_x',
    hueStartDegrees: 0,
    hueEndDegrees: 285,
    anchors: const <HueCalibrationAnchor>[
      HueCalibrationAnchor(input: 0, output: 0),
      HueCalibrationAnchor(input: .5, output: .75),
      HueCalibrationAnchor(input: 1, output: 1),
    ],
  );
}

Future<void> _settle() async {
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
