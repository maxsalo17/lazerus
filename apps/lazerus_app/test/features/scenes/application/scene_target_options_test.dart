import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/groups/application/group_targets.dart';
import 'package:lazerus_app/features/scenes/application/scene_target_options.dart';
import 'package:lazerus_app/features/scenes/domain/lighting_scene.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'only offers a group parameter when every current member supports it',
    () {
      final fullCapabilityDevice = _device(
        'device-a',
        features: <LightingFeature>{
          LightingFeature.power,
          LightingFeature.rgb,
          LightingFeature.brightness,
        },
      );
      final powerOnlyDevice = _device(
        'device-b',
        features: <LightingFeature>{LightingFeature.power},
      );
      final group = LightingTarget(
        id: 'custom:desk',
        name: 'Desk',
        kind: LightingTargetKind.customGroup,
        memberDeviceIds: const <String>{'device-a', 'device-b'},
      );

      final options = buildSceneTargetOptions(
        groups: <LightingTarget>[group],
        devices: <DebugDevice>[fullCapabilityDevice, powerOnlyDevice],
      );
      final groupOption = options.firstWhere(
        (option) => option.reference.targetId == group.id,
      );

      expect(groupOption.supports(SceneParameter.power), isTrue);
      expect(groupOption.supports(SceneParameter.brightness), isFalse);
      expect(groupOption.supports(SceneParameter.color), isFalse);
    },
  );

  test('keeps an unavailable saved reference available for repair', () {
    final missing = SceneTargetReference(
      type: SceneTargetType.device,
      targetId: 'previous-device',
    );

    final options = optionsForSceneTargets(
      availableOptions: const <SceneTargetOption>[],
      references: <SceneTargetReference>[missing],
    );

    expect(options.single.reference, missing);
    expect(options.single.isAvailable, isFalse);
    expect(options.single.availabilityLabel, contains('збережене'));
  });
}

DebugDevice _device(String id, {required Set<LightingFeature> features}) {
  return DebugDevice(
    appDeviceId: id,
    endpoint: TransportEndpoint(
      id: id,
      transport: TransportKind.ble,
      displayName: id,
    ),
    protocolId: 'lazerus.protocol.lotus_lamp_x',
    matchConfidence: 100,
    matchReason: 'test',
    status: DebugDeviceConnectionStatus.connected,
    capabilities: DeviceCapabilities(
      features: <LightingFeature, FeatureCapability>{
        for (final feature in features)
          feature: FeatureCapability(
            availability: CapabilityAvailability.verified,
          ),
      },
    ),
  );
}
