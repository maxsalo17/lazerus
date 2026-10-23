import '../../debug/application/debug_devices_controller.dart';
import '../domain/lighting_group.dart';

enum LightingTargetKind { device, protocolGroup, customGroup }

class LightingTarget {
  LightingTarget({
    required this.id,
    required this.name,
    required this.kind,
    required Iterable<String> memberDeviceIds,
    this.protocolId,
    this.customGroup,
  }) : memberDeviceIds = Set<String>.unmodifiable(memberDeviceIds);

  final String id;
  final String name;
  final LightingTargetKind kind;
  final Set<String> memberDeviceIds;
  final String? protocolId;
  final CustomLightingGroup? customGroup;

  bool get isGroup => kind != LightingTargetKind.device;
  bool get isEditable => kind == LightingTargetKind.customGroup;
}

List<LightingTarget> protocolGroupTargets(Iterable<DebugDevice> devices) {
  final deviceIdsByProtocol = <String, Set<String>>{};
  for (final device in devices) {
    deviceIdsByProtocol
        .putIfAbsent(device.protocolId, () => <String>{})
        .add(device.appDeviceId);
  }
  return deviceIdsByProtocol.entries
      .map(
        (entry) => LightingTarget(
          id: 'protocol:${entry.key}',
          name: 'Common · ${protocolDisplayName(entry.key)}',
          kind: LightingTargetKind.protocolGroup,
          protocolId: entry.key,
          memberDeviceIds: entry.value,
        ),
      )
      .toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
}

List<LightingTarget> customGroupTargets(
  Iterable<CustomLightingGroup> groups,
  Iterable<DebugDevice> devices,
) {
  final deviceIdsByProtocol = <String, Set<String>>{};
  for (final device in devices) {
    deviceIdsByProtocol
        .putIfAbsent(device.protocolId, () => <String>{})
        .add(device.appDeviceId);
  }
  return groups
      .map((group) {
        final memberDeviceIds = <String>{...group.memberDeviceIds};
        final autoProtocol = group.autoAddProtocolId;
        if (autoProtocol != null) {
          memberDeviceIds.addAll(deviceIdsByProtocol[autoProtocol] ?? const {});
        }
        return LightingTarget(
          id: 'custom:${group.id}',
          name: group.name,
          kind: LightingTargetKind.customGroup,
          memberDeviceIds: memberDeviceIds,
          protocolId: autoProtocol,
          customGroup: group,
        );
      })
      .toList(growable: false)
    ..sort((left, right) => left.name.compareTo(right.name));
}

String protocolDisplayName(String protocolId) {
  if (protocolId.endsWith('lotus_lamp_x')) {
    return 'Lotus Lamp X';
  }
  return protocolId;
}
