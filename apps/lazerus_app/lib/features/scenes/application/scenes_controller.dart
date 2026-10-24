import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:uuid/uuid.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/custom_groups_controller.dart';
import '../../groups/application/group_targets.dart';
import '../data/scene_repository.dart';
import '../domain/lighting_scene.dart';

final sceneRepositoryProvider = Provider<SceneRepository>(
  (ref) => SharedPreferencesSceneRepository(),
);

final scenesProvider = NotifierProvider<ScenesController, ScenesState>(
  ScenesController.new,
);

class ScenesState {
  const ScenesState({
    this.isLoading = true,
    this.configuration = SceneConfiguration.empty,
    this.error,
  });

  final bool isLoading;
  final SceneConfiguration configuration;
  final String? error;

  List<LightingScene> get scenes => configuration.scenes;

  ScenesState copyWith({
    bool? isLoading,
    SceneConfiguration? configuration,
    String? error,
  }) {
    return ScenesState(
      isLoading: isLoading ?? this.isLoading,
      configuration: configuration ?? this.configuration,
      error: error,
    );
  }
}

/// The resolution state of a persisted reference. It keeps a missing reference
/// visible instead of deleting it during discovery or group changes.
enum SceneTargetResolutionStatus { available, pending, unavailable }

class SceneTargetResolution {
  const SceneTargetResolution({
    required this.reference,
    required this.status,
    this.target,
    this.detail,
  });

  final SceneTargetReference reference;
  final SceneTargetResolutionStatus status;
  final LightingTarget? target;
  final String? detail;

  bool get isAvailable => status == SceneTargetResolutionStatus.available;
}

/// CRUD and live reference resolution for persisted Scene compositions.
///
/// It is deliberately independent of command dispatch; Task 3 will bind valid
/// controls to [LightingControlsController] through a separate controller.
class ScenesController extends Notifier<ScenesState> {
  late final SceneRepository _repository;
  final Uuid _uuid = const Uuid();
  var _disposed = false;

  @override
  ScenesState build() {
    _repository = ref.watch(sceneRepositoryProvider);
    ref.onDispose(() => _disposed = true);
    unawaited(_load());
    return const ScenesState();
  }

  Future<LightingScene?> create({
    required String name,
    Iterable<SceneTargetReference> targets = const <SceneTargetReference>[],
    Iterable<SceneControlSlot> controlSlots = const <SceneControlSlot>[],
  }) async {
    if (state.isLoading) {
      _setError('Scenes are still loading. Try again shortly.');
      return null;
    }
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      _setError('A Scene name is required.');
      return null;
    }
    final scene = LightingScene(
      id: _uuid.v4(),
      name: normalizedName,
      targets: targets,
      controlSlots: controlSlots,
    );
    final saved = await _replace(
      SceneConfiguration(scenes: <LightingScene>[...state.scenes, scene]),
    );
    return saved ? scene : null;
  }

  Future<bool> update(LightingScene scene) async {
    if (state.isLoading) {
      _setError('Scenes are still loading. Try again shortly.');
      return false;
    }
    final normalizedName = scene.name.trim();
    if (normalizedName.isEmpty) {
      _setError('A Scene name is required.');
      return false;
    }
    if (!state.scenes.any((current) => current.id == scene.id)) {
      _setError('The Scene no longer exists.');
      return false;
    }
    final normalized = scene.copyWith(name: normalizedName);
    return _replace(
      SceneConfiguration(
        scenes: state.scenes
            .map(
              (current) => current.id == normalized.id ? normalized : current,
            )
            .toList(growable: false),
      ),
    );
  }

  /// Replaces only a Scene's saved macro references.
  ///
  /// The method intentionally does not resolve the ids. Macro definitions live
  /// in their own repository, so a missing macro remains a persisted reference
  /// that presentation can surface and repair.
  Future<bool> updateMacroReferences(
    String sceneId,
    Iterable<SceneMacroReference> macroReferences,
  ) async {
    final normalizedReferences = List<SceneMacroReference>.from(
      macroReferences,
    );
    if (state.isLoading) {
      _setError('Scenes are still loading. Try again shortly.');
      return false;
    }
    LightingScene? scene;
    for (final candidate in state.scenes) {
      if (candidate.id == sceneId) {
        scene = candidate;
        break;
      }
    }
    if (scene == null) {
      _setError('The Scene no longer exists.');
      return false;
    }
    try {
      return update(scene.copyWith(macroReferences: normalizedReferences));
    } on ArgumentError catch (error) {
      _setError('Invalid Scene macro references: $error');
      return false;
    }
  }

  Future<bool> delete(String sceneId) async {
    if (state.isLoading) {
      _setError('Scenes are still loading. Try again shortly.');
      return false;
    }
    return _replace(
      SceneConfiguration(
        scenes: state.scenes
            .where((scene) => scene.id != sceneId)
            .toList(growable: false),
      ),
    );
  }

  /// Resolves references against the current group/device runtime state. A
  /// resolver result is advisory UI state, not a mutation of saved Scene JSON.
  List<SceneTargetResolution> resolveTargets(LightingScene scene) {
    final devices = ref.read(debugDevicesProvider).devices.values;
    final customGroups = ref.read(customGroupsProvider);
    final groups = <LightingTarget>[
      ...protocolGroupTargets(devices),
      ...customGroupTargets(customGroups.groups, devices),
    ];
    return resolveSceneTargets(
      scene: scene,
      groups: groups,
      devices: devices,
      groupsAreLoading: customGroups.isLoading,
    );
  }

  Future<void> _load() async {
    try {
      final configuration = await _repository.load();
      if (!_disposed) {
        state = ScenesState(isLoading: false, configuration: configuration);
      }
    } on Object catch (error) {
      if (!_disposed) {
        state = ScenesState(
          isLoading: false,
          error: 'Could not load Scenes: $error',
        );
      }
    }
  }

  Future<bool> _replace(SceneConfiguration configuration) async {
    final previous = state.configuration;
    state = ScenesState(isLoading: false, configuration: configuration);
    try {
      await _repository.save(configuration);
      return true;
    } on Object catch (error) {
      if (!_disposed) {
        state = ScenesState(
          isLoading: false,
          configuration: previous,
          error: 'Could not save Scenes: $error',
        );
      }
      return false;
    }
  }

  void _setError(String error) {
    if (!_disposed) {
      state = state.copyWith(error: error);
    }
  }
}

/// Pure reference resolver used by Scene controllers and focused tests.
List<SceneTargetResolution> resolveSceneTargets({
  required LightingScene scene,
  required Iterable<LightingTarget> groups,
  required Iterable<DebugDevice> devices,
  required bool groupsAreLoading,
}) {
  final groupsById = <String, LightingTarget>{
    for (final group in groups) group.id: group,
  };
  final devicesById = <String, DebugDevice>{
    for (final device in devices) device.appDeviceId: device,
  };
  final resolutions = <SceneTargetResolution>[];
  for (final reference in scene.targets) {
    switch (reference.type) {
      case SceneTargetType.group:
        final group = groupsById[reference.targetId];
        if (group != null) {
          resolutions.add(
            SceneTargetResolution(
              reference: reference,
              status: SceneTargetResolutionStatus.available,
              target: group,
            ),
          );
        } else if (groupsAreLoading) {
          resolutions.add(
            SceneTargetResolution(
              reference: reference,
              status: SceneTargetResolutionStatus.pending,
              detail: 'Group configuration is still loading.',
            ),
          );
        } else {
          resolutions.add(
            SceneTargetResolution(
              reference: reference,
              status: SceneTargetResolutionStatus.unavailable,
              detail: 'The referenced group is unavailable.',
            ),
          );
        }
      case SceneTargetType.device:
        final device = devicesById[reference.targetId];
        if (device == null) {
          resolutions.add(
            SceneTargetResolution(
              reference: reference,
              status: SceneTargetResolutionStatus.unavailable,
              detail: 'The referenced device needs rediscovery or relinking.',
            ),
          );
          continue;
        }
        resolutions.add(
          SceneTargetResolution(
            reference: reference,
            status: SceneTargetResolutionStatus.available,
            target: LightingTarget(
              id: device.appDeviceId,
              name: device.endpoint.displayName ?? 'Unnamed device',
              kind: LightingTargetKind.device,
              memberDeviceIds: <String>{device.appDeviceId},
              protocolId: device.protocolId,
            ),
          ),
        );
    }
  }
  return List<SceneTargetResolution>.unmodifiable(resolutions);
}
