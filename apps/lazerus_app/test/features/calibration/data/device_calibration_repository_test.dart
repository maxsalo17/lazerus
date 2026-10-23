import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/calibration/data/device_calibration_repository.dart';
import 'package:lazerus_app/features/calibration/domain/hue_calibration.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test(
    'persists the versioned JSON configuration across repository instances',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final profile = HueCalibrationProfile.identity(
        id: 'profile',
        name: 'Saved correction',
        protocolId: 'lazerus.protocol.lotus_lamp_x',
        hueStartDegrees: 0,
        hueEndDegrees: 285,
      );
      final configuration = DeviceCalibrationConfiguration(
        profiles: <HueCalibrationProfile>[profile],
        assignments: const <String, String>{'device-a': 'profile'},
      );

      await SharedPreferencesDeviceCalibrationRepository().save(configuration);
      final reloaded = await SharedPreferencesDeviceCalibrationRepository()
          .load();

      expect(reloaded.profileForDevice('device-a')!.name, 'Saved correction');
    },
  );
}
