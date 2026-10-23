import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/hue_calibration.dart';

abstract interface class DeviceCalibrationRepository {
  Future<DeviceCalibrationConfiguration> load();
  Future<void> save(DeviceCalibrationConfiguration configuration);
}

class SharedPreferencesDeviceCalibrationRepository
    implements DeviceCalibrationRepository {
  static const _storageKey = 'lazerus.device_hue_calibrations.v1';

  @override
  Future<DeviceCalibrationConfiguration> load() async {
    final preferences = await SharedPreferences.getInstance();
    final raw = preferences.getString(_storageKey);
    if (raw == null || raw.isEmpty) {
      return DeviceCalibrationConfiguration.empty;
    }
    try {
      return DeviceCalibrationConfiguration.fromJson(jsonDecode(raw)) ??
          DeviceCalibrationConfiguration.empty;
    } on FormatException {
      return DeviceCalibrationConfiguration.empty;
    }
  }

  @override
  Future<void> save(DeviceCalibrationConfiguration configuration) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(
      _storageKey,
      jsonEncode(configuration.toJson()),
    );
  }
}

class InMemoryDeviceCalibrationRepository
    implements DeviceCalibrationRepository {
  DeviceCalibrationConfiguration _configuration =
      DeviceCalibrationConfiguration.empty;

  @override
  Future<DeviceCalibrationConfiguration> load() async => _configuration;

  @override
  Future<void> save(DeviceCalibrationConfiguration configuration) async {
    _configuration = configuration;
  }
}
