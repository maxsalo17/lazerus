import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/control/application/lighting_controls_controller.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/groups/application/group_targets.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test('derives group colours from every member local state', () {
    final red = _device(
      id: 'red',
      name: 'A strip',
      power: true,
      color: RgbColor(255, 0, 0),
      brightness: 0.4,
    );
    final violet = _device(
      id: 'violet',
      name: 'B strip',
      power: true,
      color: RgbColor(160, 0, 255),
      brightness: 0.8,
    );
    final group = LightingTarget(
      id: 'protocol:lotus',
      name: 'Common',
      kind: LightingTargetKind.protocolGroup,
      memberDeviceIds: <String>{'violet', 'red'},
    );

    final state = TargetControlState.fromTarget(group, <String, DebugDevice>{
      red.appDeviceId: red,
      violet.appDeviceId: violet,
    });

    expect(state.power, isTrue);
    expect(state.brightness, closeTo(0.6, 0.0001));
    expect(
      state.displayColors,
      orderedEquals(<RgbColor>[RgbColor(255, 0, 0), RgbColor(160, 0, 255)]),
    );
  });

  test('uses the same local state for an individual target', () {
    final device = _device(
      id: 'strip',
      name: 'My strip',
      power: true,
      color: RgbColor(0, 64, 255),
      brightness: 0.7,
    );
    final target = LightingTarget(
      id: device.appDeviceId,
      name: 'My strip',
      kind: LightingTargetKind.device,
      memberDeviceIds: <String>{device.appDeviceId},
    );

    final state = TargetControlState.fromTarget(target, <String, DebugDevice>{
      device.appDeviceId: device,
    });

    expect(state.color, RgbColor(0, 64, 255));
    expect(state.brightness, 0.7);
    expect(state.power, isTrue);
  });
}

DebugDevice _device({
  required String id,
  required String name,
  required bool power,
  required RgbColor color,
  required double brightness,
}) {
  return DebugDevice(
    appDeviceId: id,
    endpoint: TransportEndpoint(
      id: id,
      transport: TransportKind.ble,
      displayName: name,
    ),
    protocolId: 'lotus',
    matchConfidence: 100,
    matchReason: null,
    status: DebugDeviceConnectionStatus.connected,
    requestedPower: power,
    requestedColor: color,
    requestedBrightness: brightness,
  );
}
