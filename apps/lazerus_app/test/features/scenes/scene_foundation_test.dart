import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/groups/application/group_targets.dart';
import 'package:lazerus_app/features/scenes/application/scenes_controller.dart';
import 'package:lazerus_app/features/scenes/data/scene_repository.dart';
import 'package:lazerus_app/features/scenes/domain/lighting_scene.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  final groupReference = SceneTargetReference(
    type: SceneTargetType.group,
    targetId: 'custom:desk',
  );
  final deviceReference = SceneTargetReference(
    type: SceneTargetType.device,
    targetId: 'device-a',
  );

  test('serializes typed targets, stable slots and bindings', () {
    final scene = LightingScene(
      id: 'scene-1',
      name: 'Desk scene',
      targets: <SceneTargetReference>[groupReference, deviceReference],
      controlSlots: <SceneControlSlot>[
        SceneControlSlot(
          id: 'slot-power',
          control: SceneCustomControl(
            id: 'control-power',
            type: SceneControlType.toggle,
            bindings: <SceneControlBinding>[
              SceneControlBinding(
                target: groupReference,
                parameter: SceneParameter.power,
              ),
              SceneControlBinding(
                target: deviceReference,
                parameter: SceneParameter.power,
              ),
            ],
          ),
        ),
        SceneControlSlot(id: 'slot-empty'),
      ],
    );

    final decoded = SceneConfiguration.fromJson(
      SceneConfiguration(scenes: <LightingScene>[scene]).toJson(),
    );

    expect(decoded, isNotNull);
    expect(decoded!.scenes.single.targets, orderedEquals(scene.targets));
    expect(decoded.scenes.single.controlSlots.last.control, isNull);
    expect(
      decoded.scenes.single.controlSlots.first.control!.bindings,
      hasLength(2),
    );
    expect(
      SceneConfiguration.fromJson(<String, Object>{
        'schemaVersion': 2,
        'scenes': <Object>[],
      }),
      isNull,
    );
  });

  test(
    'rejects controls with mismatched bindings or unknown Scene targets',
    () {
      expect(
        () => SceneCustomControl(
          id: 'bad',
          type: SceneControlType.toggle,
          bindings: <SceneControlBinding>[
            SceneControlBinding(
              target: groupReference,
              parameter: SceneParameter.brightness,
            ),
          ],
        ),
        throwsArgumentError,
      );
      final unattached = SceneTargetReference(
        type: SceneTargetType.device,
        targetId: 'other-device',
      );
      final control = SceneCustomControl(
        id: 'control-color',
        type: SceneControlType.colorSlider,
        bindings: <SceneControlBinding>[
          SceneControlBinding(
            target: unattached,
            parameter: SceneParameter.color,
          ),
        ],
      );
      expect(
        () => LightingScene(
          id: 'invalid',
          name: 'Invalid',
          targets: <SceneTargetReference>[groupReference],
          controlSlots: <SceneControlSlot>[
            SceneControlSlot(id: 'slot', control: control),
          ],
        ),
        throwsArgumentError,
      );
    },
  );

  test('persists versioned JSON through a fresh repository instance', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final configuration = SceneConfiguration(
      scenes: <LightingScene>[
        LightingScene(
          id: 'scene-1',
          name: 'Persisted',
          targets: <SceneTargetReference>[deviceReference],
        ),
      ],
    );

    await SharedPreferencesSceneRepository().save(configuration);
    final reloaded = await SharedPreferencesSceneRepository().load();

    expect(reloaded.scenes.single.name, 'Persisted');
    expect(reloaded.scenes.single.deviceTargets.single, deviceReference);
  });

  test('creates a Scene through the controller after loading', () async {
    final container = ProviderContainer(
      overrides: [
        sceneRepositoryProvider.overrideWithValue(InMemorySceneRepository()),
      ],
    );
    addTearDown(container.dispose);
    final controller = container.read(scenesProvider.notifier);
    await _settle();

    final created = await controller.create(
      name: '  Evening  ',
      targets: <SceneTargetReference>[deviceReference],
      controlSlots: <SceneControlSlot>[SceneControlSlot(id: 'slot-1')],
    );

    expect(created, isNotNull);
    expect(container.read(scenesProvider).scenes.single.name, 'Evening');
    expect(container.read(scenesProvider).scenes.single.id, isNotEmpty);
  });

  test('keeps missing Scene references visible to the resolver', () {
    final scene = LightingScene(
      id: 'scene',
      name: 'Repairable references',
      targets: <SceneTargetReference>[
        groupReference,
        deviceReference,
        SceneTargetReference(
          type: SceneTargetType.device,
          targetId: 'missing-device',
        ),
      ],
    );
    final group = LightingTarget(
      id: 'custom:desk',
      name: 'Desk',
      kind: LightingTargetKind.customGroup,
      memberDeviceIds: const <String>{'device-a'},
    );
    final device = _device('device-a');

    final resolutions = resolveSceneTargets(
      scene: scene,
      groups: <LightingTarget>[group],
      devices: <DebugDevice>[device],
      groupsAreLoading: false,
    );

    expect(
      resolutions.map((resolution) => resolution.status),
      orderedEquals(<SceneTargetResolutionStatus>[
        SceneTargetResolutionStatus.available,
        SceneTargetResolutionStatus.available,
        SceneTargetResolutionStatus.unavailable,
      ]),
    );
    expect(resolutions.last.detail, contains('rediscovery'));
  });
}

Future<void> _settle() async {
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}

DebugDevice _device(String id) {
  return DebugDevice(
    appDeviceId: id,
    endpoint: TransportEndpoint(
      id: id,
      transport: TransportKind.ble,
      displayName: 'Desk strip',
    ),
    protocolId: 'lazerus.protocol.lotus_lamp_x',
    matchConfidence: 100,
    matchReason: 'test',
    status: DebugDeviceConnectionStatus.connected,
  );
}
