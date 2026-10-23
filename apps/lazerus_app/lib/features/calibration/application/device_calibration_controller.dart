import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:uuid/uuid.dart';

import '../data/device_calibration_repository.dart';
import '../domain/hue_calibration.dart';

final deviceCalibrationRepositoryProvider =
    Provider<DeviceCalibrationRepository>(
      (ref) => SharedPreferencesDeviceCalibrationRepository(),
    );

final deviceCalibrationProvider =
    NotifierProvider<DeviceCalibrationController, DeviceCalibrationState>(
      DeviceCalibrationController.new,
    );

class DeviceCalibrationState {
  const DeviceCalibrationState({
    this.isLoading = true,
    this.configuration = DeviceCalibrationConfiguration.empty,
    this.error,
  });

  final bool isLoading;
  final DeviceCalibrationConfiguration configuration;
  final String? error;

  DeviceCalibrationState copyWith({
    bool? isLoading,
    DeviceCalibrationConfiguration? configuration,
    String? error,
  }) {
    return DeviceCalibrationState(
      isLoading: isLoading ?? this.isLoading,
      configuration: configuration ?? this.configuration,
      error: error,
    );
  }
}

/// Owns persistent device-profile assignments and transient editor previews.
///
/// It deliberately has no BLE dependency. The debug command boundary asks it
/// for a mapped colour immediately before a protocol session receives a frame.
class DeviceCalibrationController extends Notifier<DeviceCalibrationState> {
  late final DeviceCalibrationRepository _repository;
  final Uuid _uuid = const Uuid();
  final Map<String, HueCalibrationProfile> _previewProfiles =
      <String, HueCalibrationProfile>{};
  Future<void>? _loadOperation;
  var _disposed = false;

  @override
  DeviceCalibrationState build() {
    _repository = ref.watch(deviceCalibrationRepositoryProvider);
    ref.onDispose(() {
      _disposed = true;
      _previewProfiles.clear();
    });
    _loadOperation = _load();
    return const DeviceCalibrationState();
  }

  /// Lets the command boundary wait for local profiles after an app restart.
  /// A load failure is already represented in [state] and results in identity
  /// mapping instead of preventing an otherwise valid lighting command.
  Future<void> ensureLoaded() => _loadOperation ?? Future<void>.value();

  RgbColor mapColorForDevice({
    required String appDeviceId,
    required String protocolId,
    required RgbColor color,
  }) {
    final profile =
        _previewProfiles[appDeviceId] ??
        state.configuration.profileForDevice(appDeviceId);
    if (profile == null || profile.protocolId != protocolId) {
      return color;
    }
    return profile.mapColor(color);
  }

  List<HueCalibrationProfile> profilesAssignedTo(
    Iterable<String> appDeviceIds, {
    required String protocolId,
  }) {
    final ids = <String>{};
    for (final deviceId in appDeviceIds) {
      final profileId = state.configuration.assignments[deviceId];
      if (profileId != null) {
        ids.add(profileId);
      }
    }
    return state.configuration.profiles
        .where((profile) => ids.contains(profile.id))
        .where((profile) => profile.protocolId == protocolId)
        .toList(growable: false);
  }

  void preview({
    required Iterable<String> appDeviceIds,
    required HueCalibrationProfile profile,
  }) {
    for (final deviceId in appDeviceIds) {
      _previewProfiles[deviceId] = profile;
    }
  }

  void clearPreview(Iterable<String> appDeviceIds) {
    for (final deviceId in appDeviceIds) {
      _previewProfiles.remove(deviceId);
    }
  }

  /// Stores a fresh profile ID even when [draft] originated from a dropdown.
  /// That copy-on-save behaviour keeps unrelated device assignments stable.
  Future<bool> saveForDevices({
    required Iterable<String> appDeviceIds,
    required HueCalibrationProfile draft,
  }) async {
    final deviceIds = appDeviceIds.toSet();
    if (deviceIds.isEmpty) {
      _setError('Select at least one device to save a calibration.');
      return false;
    }
    final profile = draft.copyWith(id: _uuid.v4(), name: draft.name.trim());
    final previous = state.configuration;
    final assignments = Map<String, String>.of(previous.assignments);
    for (final deviceId in deviceIds) {
      assignments[deviceId] = profile.id;
    }
    final configuration = previous.copyWith(
      profiles: <HueCalibrationProfile>[...previous.profiles, profile],
      assignments: assignments,
    );
    state = DeviceCalibrationState(
      isLoading: false,
      configuration: configuration,
    );
    try {
      await _repository.save(configuration);
      clearPreview(deviceIds);
      return true;
    } on Object catch (error) {
      if (!_disposed) {
        state = DeviceCalibrationState(
          isLoading: false,
          configuration: previous,
          error: 'Could not save calibration: $error',
        );
      }
      return false;
    }
  }

  Future<void> _load() async {
    try {
      final configuration = await _repository.load();
      if (!_disposed) {
        state = DeviceCalibrationState(
          isLoading: false,
          configuration: configuration,
        );
      }
    } on Object catch (error) {
      if (!_disposed) {
        state = DeviceCalibrationState(
          isLoading: false,
          error: 'Could not load calibrations: $error',
        );
      }
    }
  }

  void _setError(String error) {
    if (!_disposed) {
      state = state.copyWith(error: error);
    }
  }
}
