import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/groups/application/custom_groups_controller.dart';
import 'package:lazerus_app/features/groups/application/group_targets.dart';
import 'package:lazerus_app/features/scenes/application/scene_controls_controller.dart';
import 'package:lazerus_app/features/scenes/application/scenes_controller.dart';
import 'package:lazerus_app/features/scenes/data/scene_repository.dart';
import 'package:lazerus_app/features/scenes/domain/lighting_scene.dart';
import 'package:lazerus_app/features/scenes/presentation/scene_detail_page.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  testWidgets(
    'renders custom controls before the Groups and Devices sections',
    (tester) async {
      final groupReference = SceneTargetReference(
        type: SceneTargetType.group,
        targetId: 'protocol:lotus',
      );
      final deviceReference = SceneTargetReference(
        type: SceneTargetType.device,
        targetId: 'device-a',
      );
      final control = SceneCustomControl(
        id: 'power',
        type: SceneControlType.toggle,
        label: 'Desk power',
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
      );
      final brightnessControl = SceneCustomControl(
        id: 'brightness',
        type: SceneControlType.brightnessSlider,
        label: 'Desk brightness',
        bindings: <SceneControlBinding>[
          SceneControlBinding(
            target: groupReference,
            parameter: SceneParameter.brightness,
          ),
          SceneControlBinding(
            target: deviceReference,
            parameter: SceneParameter.brightness,
          ),
        ],
      );
      final scene = LightingScene(
        id: 'scene-1',
        name: 'Evening',
        targets: <SceneTargetReference>[groupReference, deviceReference],
        controlSlots: <SceneControlSlot>[
          SceneControlSlot(id: 'slot-power', control: control),
          SceneControlSlot(id: 'slot-brightness', control: brightnessControl),
        ],
      );
      final dispatcher = _RecordingDispatcher();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sceneRepositoryProvider.overrideWithValue(
              InMemorySceneRepository(
                SceneConfiguration(scenes: <LightingScene>[scene]),
              ),
            ),
            debugDevicesProvider.overrideWith(
              () => _StaticDebugDevicesController(<String, DebugDevice>{
                'device-a': _device('device-a'),
                'device-b': _device('device-b'),
              }),
            ),
            customGroupsProvider.overrideWith(
              _StaticCustomGroupsController.new,
            ),
            sceneCommandDispatcherProvider.overrideWithValue(dispatcher),
          ],
          child: const MaterialApp(home: SceneDetailPage(sceneId: 'scene-1')),
        ),
      );
      await tester.pumpAndSettle();

      final controlsY = tester.getTopLeft(find.text('Custom controls')).dy;
      final groupsY = tester.getTopLeft(find.text('Групи')).dy;
      final devicesY = tester.getTopLeft(find.text('Девайси')).dy;
      expect(controlsY, lessThan(groupsY));
      expect(groupsY, lessThan(devicesY));
      expect(find.text('Desk power'), findsOneWidget);
      expect(
        find.byKey(const Key('scene-target-control-protocol:lotus')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('scene-target-control-device-a')),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('scene-control-power-toggle')));
      await tester.pumpAndSettle();

      expect(dispatcher.calls, hasLength(1));
      expect(dispatcher.calls.single.target.memberDeviceIds, <String>{
        'device-a',
        'device-b',
      });
      expect(dispatcher.calls.single.command, isA<SetPower>());

      final gesture = await tester.startGesture(
        tester.getCenter(
          find.byKey(const Key('scene-control-brightness-brightness')),
        ),
      );
      await tester.pump(const Duration(milliseconds: 600));
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      expect(dispatcher.calls, hasLength(2));
      expect(dispatcher.calls.last.command, isA<SetBrightness>());
    },
  );
}

DebugDevice _device(String id) {
  return DebugDevice(
    appDeviceId: id,
    endpoint: TransportEndpoint(
      id: id,
      transport: TransportKind.ble,
      displayName: id,
    ),
    protocolId: 'lotus',
    matchConfidence: 100,
    matchReason: 'test',
    status: DebugDeviceConnectionStatus.connected,
    capabilities: DeviceCapabilities(
      features: <LightingFeature, FeatureCapability>{
        LightingFeature.power: FeatureCapability(
          availability: CapabilityAvailability.verified,
        ),
        LightingFeature.brightness: FeatureCapability(
          availability: CapabilityAvailability.verified,
        ),
      },
    ),
  );
}

class _StaticDebugDevicesController extends DebugDevicesController {
  _StaticDebugDevicesController(this._devices);

  final Map<String, DebugDevice> _devices;

  @override
  DebugModuleState build() => DebugModuleState(devices: _devices);
}

class _StaticCustomGroupsController extends CustomGroupsController {
  @override
  CustomGroupsState build() => const CustomGroupsState(isLoading: false);
}

class _RecordingDispatcher implements SceneCommandDispatcher {
  final List<_RecordedDispatch> calls = <_RecordedDispatch>[];

  @override
  Future<List<CommandResult>> dispatch(
    LightingTarget target,
    LightingCommand command,
  ) async {
    calls.add(_RecordedDispatch(target, command));
    return target.memberDeviceIds
        .map(
          (_) => CommandResult(
            command: command,
            outcome: CommandOutcome.transmitted,
          ),
        )
        .toList(growable: false);
  }
}

class _RecordedDispatch {
  const _RecordedDispatch(this.target, this.command);

  final LightingTarget target;
  final LightingCommand command;
}
