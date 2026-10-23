import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/debug/application/debug_devices_controller.dart';
import 'package:lazerus_app/features/groups/application/custom_groups_controller.dart';
import 'package:lazerus_app/features/groups/application/group_targets.dart';
import 'package:lazerus_app/features/scenes/application/scene_controls_controller.dart';
import 'package:lazerus_app/features/scenes/domain/lighting_scene.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  final groupReference = SceneTargetReference(
    type: SceneTargetType.group,
    targetId: 'protocol:lotus',
  );
  final deviceReference = SceneTargetReference(
    type: SceneTargetType.device,
    targetId: 'device-a',
  );

  test('deduplicates devices shared by a group and a direct binding', () {
    final scene = _scene(
      targets: <SceneTargetReference>[groupReference, deviceReference],
      control: _control(
        type: SceneControlType.toggle,
        bindings: <SceneControlBinding>[
          _binding(groupReference, SceneParameter.power),
          _binding(deviceReference, SceneParameter.power),
        ],
      ),
    );
    final plan = resolveSceneControlDispatch(
      scene: scene,
      control: _firstControl(scene),
      groups: <LightingTarget>[_group()],
      devices: <DebugDevice>[_device('device-a'), _device('device-b')],
    );

    expect(plan.commandTarget.memberDeviceIds, <String>{
      'device-a',
      'device-b',
    });
    expect(plan.issues, isEmpty);
  });

  test('keeps the available members and reports stale capability bindings', () {
    final scene = _scene(
      targets: <SceneTargetReference>[groupReference],
      control: _control(
        type: SceneControlType.brightnessSlider,
        bindings: <SceneControlBinding>[
          _binding(groupReference, SceneParameter.brightness),
        ],
      ),
    );
    final plan = resolveSceneControlDispatch(
      scene: scene,
      control: _firstControl(scene),
      groups: <LightingTarget>[_group()],
      devices: <DebugDevice>[
        _device('device-a'),
        _device(
          'device-b',
          status: DebugDeviceConnectionStatus.disconnected,
          features: <LightingFeature>{LightingFeature.power},
        ),
      ],
    );

    expect(plan.commandTarget.memberDeviceIds, <String>{'device-a'});
    expect(plan.issues.single.detail, contains('не підключено'));
  });

  test(
    'dispatches just the final slider value to a deduplicated target',
    () async {
      final dispatcher = _RecordingDispatcher();
      final scene = _scene(
        targets: <SceneTargetReference>[groupReference, deviceReference],
        control: _control(
          type: SceneControlType.brightnessSlider,
          bindings: <SceneControlBinding>[
            _binding(groupReference, SceneParameter.brightness),
            _binding(deviceReference, SceneParameter.brightness),
          ],
        ),
      );
      final container = _container(
        dispatcher: dispatcher,
        devices: <String, DebugDevice>{
          'device-a': _device('device-a'),
          'device-b': _device('device-b'),
        },
      );
      addTearDown(container.dispose);
      final controller = container.read(sceneControlsProvider.notifier);
      final control = _firstControl(scene);

      controller.previewBrightness(scene, control, 0.2);
      controller.previewBrightness(scene, control, 0.6);
      await controller.commitBrightness(scene, control, 0.8);

      expect(dispatcher.calls, hasLength(1));
      expect(dispatcher.calls.single.target.memberDeviceIds, <String>{
        'device-a',
        'device-b',
      });
      expect((dispatcher.calls.single.command as SetBrightness).value, 0.8);
    },
  );

  test(
    'rechecks live connection state when a queued value is emitted',
    () async {
      final dispatcher = _RecordingDispatcher();
      final scene = _scene(
        targets: <SceneTargetReference>[deviceReference],
        control: _control(
          type: SceneControlType.colorSlider,
          bindings: <SceneControlBinding>[
            _binding(deviceReference, SceneParameter.color),
          ],
        ),
      );
      final container = _container(
        dispatcher: dispatcher,
        devices: <String, DebugDevice>{'device-a': _device('device-a')},
      );
      addTearDown(container.dispose);
      final controller = container.read(sceneControlsProvider.notifier);
      final debug =
          container.read(debugDevicesProvider.notifier)
              as _StaticDebugDevicesController;

      controller.previewColor(scene, _firstControl(scene), RgbColor(255, 0, 0));
      debug.replaceDevices(<String, DebugDevice>{
        'device-a': _device(
          'device-a',
          status: DebugDeviceConnectionStatus.disconnected,
        ),
      });
      await Future<void>.delayed(const Duration(milliseconds: 130));

      expect(dispatcher.calls, isEmpty);
      final view = controller.viewStateFor(scene, _firstControl(scene));
      expect(view.status.issues.single.detail, contains('не підключено'));
    },
  );
}

ProviderContainer _container({
  required _RecordingDispatcher dispatcher,
  required Map<String, DebugDevice> devices,
}) {
  return ProviderContainer(
    overrides: [
      debugDevicesProvider.overrideWith(
        () => _StaticDebugDevicesController(devices),
      ),
      customGroupsProvider.overrideWith(_StaticCustomGroupsController.new),
      sceneCommandDispatcherProvider.overrideWithValue(dispatcher),
    ],
  );
}

LightingScene _scene({
  required Iterable<SceneTargetReference> targets,
  required SceneCustomControl control,
}) {
  return LightingScene(
    id: 'scene-1',
    name: 'Desk',
    targets: targets,
    controlSlots: <SceneControlSlot>[
      SceneControlSlot(id: 'slot-1', control: control),
    ],
  );
}

SceneCustomControl _control({
  required SceneControlType type,
  required Iterable<SceneControlBinding> bindings,
}) {
  return SceneCustomControl(id: 'control-1', type: type, bindings: bindings);
}

SceneCustomControl _firstControl(LightingScene scene) =>
    scene.controlSlots.single.control!;

SceneControlBinding _binding(
  SceneTargetReference target,
  SceneParameter parameter,
) => SceneControlBinding(target: target, parameter: parameter);

LightingTarget _group() {
  return LightingTarget(
    id: 'protocol:lotus',
    name: 'Common · Lotus',
    kind: LightingTargetKind.protocolGroup,
    memberDeviceIds: const <String>{'device-a', 'device-b'},
  );
}

DebugDevice _device(
  String id, {
  DebugDeviceConnectionStatus status = DebugDeviceConnectionStatus.connected,
  Set<LightingFeature> features = const <LightingFeature>{
    LightingFeature.power,
    LightingFeature.brightness,
    LightingFeature.rgb,
  },
}) {
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
    status: status,
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

class _StaticDebugDevicesController extends DebugDevicesController {
  _StaticDebugDevicesController(this._devices);

  Map<String, DebugDevice> _devices;

  @override
  DebugModuleState build() => DebugModuleState(devices: _devices);

  void replaceDevices(Map<String, DebugDevice> devices) {
    _devices = devices;
    state = DebugModuleState(devices: devices);
  }
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
