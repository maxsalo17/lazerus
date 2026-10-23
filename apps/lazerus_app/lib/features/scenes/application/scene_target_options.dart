import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/custom_groups_controller.dart';
import '../../groups/application/group_targets.dart';
import '../domain/lighting_scene.dart';

/// A live target that may be selected in Scene Settings or bound to a control.
///
/// The stored Scene value stays a [SceneTargetReference]. This UI-facing model
/// is rebuilt from the current group/device state and therefore never persists
/// platform identifiers, group membership, or capability snapshots.
class SceneTargetOption {
  SceneTargetOption({
    required this.reference,
    required this.name,
    this.target,
    Iterable<SceneParameter> supportedParameters = const <SceneParameter>[],
  }) : supportedParameters = Set<SceneParameter>.unmodifiable(
         supportedParameters,
       );

  final SceneTargetReference reference;
  final String name;
  final LightingTarget? target;
  final Set<SceneParameter> supportedParameters;

  bool get isAvailable => target != null;

  bool supports(SceneParameter parameter) =>
      supportedParameters.contains(parameter);

  String get kindLabel => switch (reference.type) {
    SceneTargetType.group => 'Група',
    SceneTargetType.device => 'Девайс',
  };

  String get availabilityLabel {
    if (!isAvailable) {
      return 'Недоступна — збережене посилання';
    }
    if (supportedParameters.isEmpty) {
      return 'Можливості ще недоступні';
    }
    return supportedParameters.map(sceneParameterLabel).join(' · ');
  }
}

/// Current Scene candidates. The provider is intentionally presentation-safe:
/// it reads only existing app state and does not start discovery or send BLE
/// commands.
final sceneTargetOptionsProvider = Provider<List<SceneTargetOption>>((ref) {
  final devices = ref.watch(debugDevicesProvider).sortedDevices;
  final customGroups = ref.watch(customGroupsProvider).groups;
  final groups = <LightingTarget>[
    ...protocolGroupTargets(devices),
    ...customGroupTargets(customGroups, devices),
  ];
  return buildSceneTargetOptions(groups: groups, devices: devices);
});

/// Produces every currently known group and direct device target.
List<SceneTargetOption> buildSceneTargetOptions({
  required Iterable<LightingTarget> groups,
  required Iterable<DebugDevice> devices,
}) {
  final deviceList = devices.toList(growable: false);
  final devicesById = <String, DebugDevice>{
    for (final device in deviceList) device.appDeviceId: device,
  };
  final options = <SceneTargetOption>[];

  for (final group in groups) {
    options.add(
      SceneTargetOption(
        reference: SceneTargetReference(
          type: SceneTargetType.group,
          targetId: group.id,
        ),
        name: group.name,
        target: group,
        supportedParameters: _supportedParameters(group, devicesById),
      ),
    );
  }
  for (final device in deviceList) {
    final target = LightingTarget(
      id: device.appDeviceId,
      name: device.endpoint.displayName ?? 'Без назви',
      kind: LightingTargetKind.device,
      memberDeviceIds: <String>{device.appDeviceId},
      protocolId: device.protocolId,
    );
    options.add(
      SceneTargetOption(
        reference: SceneTargetReference(
          type: SceneTargetType.device,
          targetId: device.appDeviceId,
        ),
        name: target.name,
        target: target,
        supportedParameters: _supportedParameters(target, devicesById),
      ),
    );
  }
  options.sort((left, right) {
    final kind = left.reference.type.index.compareTo(
      right.reference.type.index,
    );
    return kind != 0 ? kind : left.name.compareTo(right.name);
  });
  return List<SceneTargetOption>.unmodifiable(options);
}

/// Resolves saved references for one Scene. A missing reference is deliberately
/// represented instead of dropped, so the user may remove or repair it.
List<SceneTargetOption> optionsForSceneTargets({
  required Iterable<SceneTargetOption> availableOptions,
  required Iterable<SceneTargetReference> references,
}) {
  final byReference = <SceneTargetReference, SceneTargetOption>{
    for (final option in availableOptions) option.reference: option,
  };
  return List<SceneTargetOption>.unmodifiable(
    references.map(
      (reference) =>
          byReference[reference] ??
          SceneTargetOption(
            reference: reference,
            name: switch (reference.type) {
              SceneTargetType.group => 'Недоступна група',
              SceneTargetType.device => 'Недоступний девайс',
            },
          ),
    ),
  );
}

String sceneParameterLabel(SceneParameter parameter) => switch (parameter) {
  SceneParameter.power => 'Живлення',
  SceneParameter.brightness => 'Яскравість',
  SceneParameter.color => 'Колір',
};

Set<SceneParameter> _supportedParameters(
  LightingTarget target,
  Map<String, DebugDevice> devicesById,
) {
  final members = target.memberDeviceIds
      .map((id) => devicesById[id])
      .whereType<DebugDevice>()
      .toList(growable: false);
  if (members.isEmpty || members.length != target.memberDeviceIds.length) {
    return const <SceneParameter>{};
  }
  final parameters = <SceneParameter>{};
  for (final parameter in SceneParameter.values) {
    final feature = switch (parameter) {
      SceneParameter.power => LightingFeature.power,
      SceneParameter.brightness => LightingFeature.brightness,
      // A generic colour control is currently RGB-only. RGBW/CCT needs an
      // explicit cross-domain mapping before it may appear in the editor.
      SceneParameter.color => LightingFeature.rgb,
    };
    if (members.every(
      (device) =>
          device.capabilities?.supports(feature, allowInferred: true) ?? false,
    )) {
      parameters.add(parameter);
    }
  }
  return Set<SceneParameter>.unmodifiable(parameters);
}
