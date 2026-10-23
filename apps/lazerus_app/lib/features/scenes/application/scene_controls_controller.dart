import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../control/application/lighting_controls_controller.dart';
import '../../control/application/replaceable_command_ticker.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../diagnostics/application/diagnostics_controller.dart';
import '../../groups/application/custom_groups_controller.dart';
import '../../groups/application/group_targets.dart';
import '../domain/lighting_scene.dart';
import 'scene_target_options.dart';

/// Narrow command boundary used by Scene controls. It keeps Scene UI and its
/// tests independent from BLE sessions while reusing the normal lighting
/// controller for the actual device writes.
abstract interface class SceneCommandDispatcher {
  Future<List<CommandResult>> dispatch(
    LightingTarget target,
    LightingCommand command,
  );
}

class LightingControlsSceneCommandDispatcher implements SceneCommandDispatcher {
  LightingControlsSceneCommandDispatcher(this._controls);

  final LightingControlsController _controls;

  @override
  Future<List<CommandResult>> dispatch(
    LightingTarget target,
    LightingCommand command,
  ) {
    return _controls.dispatch(target, command);
  }
}

final sceneCommandDispatcherProvider = Provider<SceneCommandDispatcher>((ref) {
  return LightingControlsSceneCommandDispatcher(
    ref.read(lightingControlsProvider.notifier),
  );
});

final sceneControlsProvider =
    NotifierProvider<
      SceneControlsController,
      Map<String, SceneControlDispatchStatus>
    >(SceneControlsController.new);

/// Why one persisted binding could not participate in a runtime command.
class SceneControlBindingIssue {
  const SceneControlBindingIssue({
    required this.reference,
    required this.detail,
  });

  final SceneTargetReference reference;
  final String detail;
}

/// The current live command target resolved from one custom control.
class SceneControlDispatchPlan {
  SceneControlDispatchPlan({
    required this.commandTarget,
    Iterable<SceneControlBindingIssue> issues =
        const <SceneControlBindingIssue>[],
  }) : issues = List<SceneControlBindingIssue>.unmodifiable(issues);

  final LightingTarget commandTarget;
  final List<SceneControlBindingIssue> issues;

  bool get canDispatch => commandTarget.memberDeviceIds.isNotEmpty;
}

class SceneControlDispatchStatus {
  SceneControlDispatchStatus({
    this.isDispatching = false,
    this.targetDeviceCount = 0,
    Iterable<SceneControlBindingIssue> issues =
        const <SceneControlBindingIssue>[],
    this.lastError,
  }) : issues = List<SceneControlBindingIssue>.unmodifiable(issues);

  final bool isDispatching;
  final int targetDeviceCount;
  final List<SceneControlBindingIssue> issues;
  final String? lastError;
}

class SceneControlViewState {
  const SceneControlViewState({
    required this.plan,
    required this.controlState,
    required this.status,
  });

  final SceneControlDispatchPlan plan;
  final TargetControlState controlState;
  final SceneControlDispatchStatus status;
}

/// Resolves, validates and dispatches custom Scene controls.
///
/// This controller is the only Scene-layer code that calls the normal lighting
/// command boundary. Widgets request typed actions here; neither widgets nor
/// persisted Scene data know protocol frames or BLE APIs.
class SceneControlsController
    extends Notifier<Map<String, SceneControlDispatchStatus>> {
  late final SceneCommandDispatcher _dispatcher;
  late final DiagnosticsController _diagnostics;
  final Map<String, ReplaceableCommandTicker<_QueuedSceneCommand>> _tickers =
      <String, ReplaceableCommandTicker<_QueuedSceneCommand>>{};
  final Map<String, int> _revisions = <String, int>{};
  var _disposed = false;

  @override
  Map<String, SceneControlDispatchStatus> build() {
    _dispatcher = ref.watch(sceneCommandDispatcherProvider);
    _diagnostics = ref.read(diagnosticsProvider.notifier);
    ref.onDispose(() {
      _disposed = true;
      for (final ticker in _tickers.values) {
        ticker.dispose();
      }
      _tickers.clear();
      _revisions.clear();
    });
    return const <String, SceneControlDispatchStatus>{};
  }

  SceneControlViewState viewStateFor(
    LightingScene scene,
    SceneCustomControl control,
  ) {
    final plan = planFor(scene, control);
    final key = _keyFor(scene, control);
    final previous = state[key];
    final status = SceneControlDispatchStatus(
      isDispatching: previous?.isDispatching ?? false,
      targetDeviceCount: plan.commandTarget.memberDeviceIds.length,
      issues: plan.issues,
      lastError: previous?.lastError,
    );
    return SceneControlViewState(
      plan: plan,
      controlState: TargetControlState.fromTarget(
        plan.commandTarget,
        ref.read(debugDevicesProvider).devices,
      ),
      status: status,
    );
  }

  /// Re-evaluates live groups, connection state and capabilities immediately
  /// before an action. The output contains each eligible device ID once.
  SceneControlDispatchPlan planFor(
    LightingScene scene,
    SceneCustomControl control,
  ) {
    final devices = ref.read(debugDevicesProvider).devices;
    final customGroups = ref.read(customGroupsProvider).groups;
    final groups = <LightingTarget>[
      ...protocolGroupTargets(devices.values),
      ...customGroupTargets(customGroups, devices.values),
    ];
    return resolveSceneControlDispatch(
      scene: scene,
      control: control,
      groups: groups,
      devices: devices.values,
    );
  }

  Future<void> setPower(
    LightingScene scene,
    SceneCustomControl control,
    bool enabled,
  ) {
    return _dispatchNow(scene, control, SetPower(enabled));
  }

  void previewBrightness(
    LightingScene scene,
    SceneCustomControl control,
    double value,
  ) {
    _queue(scene, control, SetBrightness(value));
  }

  Future<void> commitBrightness(
    LightingScene scene,
    SceneCustomControl control,
    double value,
  ) {
    return _commit(scene, control, SetBrightness(value));
  }

  void previewColor(
    LightingScene scene,
    SceneCustomControl control,
    RgbColor color,
  ) {
    _queue(scene, control, SetColor(color));
  }

  Future<void> commitColor(
    LightingScene scene,
    SceneCustomControl control,
    RgbColor color,
  ) {
    return _commit(scene, control, SetColor(color));
  }

  void cancelScene(String sceneId) {
    final prefix = 'scene:$sceneId:control:';
    final keys = _tickers.keys
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in keys) {
      _tickers.remove(key)?.dispose();
      _revisions.remove(key);
    }
  }

  Future<void> _dispatchNow(
    LightingScene scene,
    SceneCustomControl control,
    LightingCommand command,
  ) async {
    final plan = planFor(scene, control);
    final key = _keyFor(scene, control);
    final revision = _nextRevision(key);
    _recordPlan(key, plan, isDispatching: plan.canDispatch);
    if (!plan.canDispatch) {
      _recordIssues(scene, control, plan.issues);
      return;
    }
    final results = await _dispatcher.dispatch(plan.commandTarget, command);
    _complete(key, revision, scene, control, plan, results, logIssues: true);
  }

  void _queue(
    LightingScene scene,
    SceneCustomControl control,
    LightingCommand command, {
    bool logIssues = false,
  }) {
    final plan = planFor(scene, control);
    final key = _keyFor(scene, control);
    final revision = _nextRevision(key);
    // A queued preview is not a transport write. Keep the control interactive
    // until the ticker actually emits it, so further drag samples can replace
    // this value and release can flush the latest one.
    _recordPlan(key, plan, isDispatching: state[key]?.isDispatching ?? false);
    if (!plan.canDispatch) {
      return;
    }
    final ticker = _tickers.putIfAbsent(
      key,
      () => ReplaceableCommandTicker<_QueuedSceneCommand>(onEmit: _emitQueued),
    );
    ticker.push(
      _QueuedSceneCommand(
        key: key,
        revision: revision,
        scene: scene,
        control: control,
        command: command,
        logIssues: logIssues,
      ),
    );
  }

  Future<void> _commit(
    LightingScene scene,
    SceneCustomControl control,
    LightingCommand command,
  ) async {
    _queue(scene, control, command, logIssues: true);
    final key = _keyFor(scene, control);
    final ticker = _tickers[key];
    if (ticker == null) {
      final plan = planFor(scene, control);
      _recordIssues(scene, control, plan.issues);
      return;
    }
    await ticker.flush();
  }

  Future<void> _emitQueued(_QueuedSceneCommand queued) async {
    // A value can wait in the ticker for up to one tick. Resolve again at the
    // point of transport dispatch so a disconnect, relink or capability change
    // cannot make a stale target bypass the current safety checks.
    final plan = planFor(queued.scene, queued.control);
    if (!plan.canDispatch) {
      _complete(
        queued.key,
        queued.revision,
        queued.scene,
        queued.control,
        plan,
        const <CommandResult>[],
        logIssues: queued.logIssues,
      );
      return;
    }
    _recordPlan(queued.key, plan, isDispatching: true);
    final results = await _dispatcher.dispatch(
      plan.commandTarget,
      queued.command,
    );
    _complete(
      queued.key,
      queued.revision,
      queued.scene,
      queued.control,
      plan,
      results,
      logIssues: queued.logIssues,
    );
  }

  void _recordPlan(
    String key,
    SceneControlDispatchPlan plan, {
    required bool isDispatching,
  }) {
    if (_disposed) {
      return;
    }
    state = <String, SceneControlDispatchStatus>{
      ...state,
      key: SceneControlDispatchStatus(
        isDispatching: isDispatching,
        targetDeviceCount: plan.commandTarget.memberDeviceIds.length,
        issues: plan.issues,
      ),
    };
  }

  void _complete(
    String key,
    int revision,
    LightingScene scene,
    SceneCustomControl control,
    SceneControlDispatchPlan plan,
    List<CommandResult> results, {
    required bool logIssues,
  }) {
    if (_disposed || _revisions[key] != revision) {
      return;
    }
    final errors = _resultErrors(results);
    final message = errors.isEmpty ? null : errors.join(' ');
    state = <String, SceneControlDispatchStatus>{
      ...state,
      key: SceneControlDispatchStatus(
        targetDeviceCount: plan.commandTarget.memberDeviceIds.length,
        issues: plan.issues,
        lastError: message,
      ),
    };
    if (logIssues) {
      _recordIssues(scene, control, plan.issues);
    }
    if (message != null) {
      _diagnostics.error(
        'Scene «${scene.name}» · ${_controlLabel(control)}: $message',
      );
    }
  }

  void _recordIssues(
    LightingScene scene,
    SceneCustomControl control,
    Iterable<SceneControlBindingIssue> issues,
  ) {
    for (final issue in issues) {
      _diagnostics.warning(
        'Scene «${scene.name}» · ${_controlLabel(control)}: ${issue.detail}',
      );
    }
  }

  int _nextRevision(String key) {
    final revision = (_revisions[key] ?? 0) + 1;
    _revisions[key] = revision;
    return revision;
  }

  static String _keyFor(LightingScene scene, SceneCustomControl control) =>
      'scene:${scene.id}:control:${control.id}';

  static String _controlLabel(SceneCustomControl control) =>
      control.label ?? sceneParameterLabel(control.type.parameter);
}

/// Pure, capability-aware target expansion used by the controller and tests.
SceneControlDispatchPlan resolveSceneControlDispatch({
  required LightingScene scene,
  required SceneCustomControl control,
  required Iterable<LightingTarget> groups,
  required Iterable<DebugDevice> devices,
}) {
  final groupsById = <String, LightingTarget>{
    for (final group in groups) group.id: group,
  };
  final devicesById = <String, DebugDevice>{
    for (final device in devices) device.appDeviceId: device,
  };
  final targetDeviceIds = <String>{};
  final issues = <SceneControlBindingIssue>[];
  final feature = _featureFor(control.type.parameter);

  for (final binding in control.bindings) {
    final target = switch (binding.target.type) {
      SceneTargetType.group => groupsById[binding.target.targetId],
      SceneTargetType.device => _directTarget(
        binding.target.targetId,
        devicesById[binding.target.targetId],
      ),
    };
    if (target == null) {
      issues.add(
        SceneControlBindingIssue(
          reference: binding.target,
          detail:
              'Ціль більше недоступна. Потрібне повторне виявлення або relink.',
        ),
      );
      continue;
    }
    if (target.memberDeviceIds.isEmpty) {
      issues.add(
        SceneControlBindingIssue(
          reference: binding.target,
          detail: 'Ціль «${target.name}» не має доступних девайсів.',
        ),
      );
      continue;
    }
    for (final deviceId in target.memberDeviceIds) {
      final device = devicesById[deviceId];
      if (device == null) {
        issues.add(
          SceneControlBindingIssue(
            reference: binding.target,
            detail: 'Один з девайсів цілі «${target.name}» недоступний.',
          ),
        );
        continue;
      }
      final deviceName = device.endpoint.displayName ?? device.appDeviceId;
      if (device.status != DebugDeviceConnectionStatus.connected) {
        issues.add(
          SceneControlBindingIssue(
            reference: binding.target,
            detail: 'Девайс «$deviceName» не підключено.',
          ),
        );
        continue;
      }
      if (!(device.capabilities?.supports(feature, allowInferred: true) ??
          false)) {
        issues.add(
          SceneControlBindingIssue(
            reference: binding.target,
            detail:
                'Девайс «$deviceName» не підтримує ${sceneParameterLabel(control.type.parameter)}.',
          ),
        );
        continue;
      }
      targetDeviceIds.add(deviceId);
    }
  }

  return SceneControlDispatchPlan(
    commandTarget: LightingTarget(
      id: 'scene:${scene.id}:control:${control.id}',
      name: '${scene.name} · ${_controlLabel(control)}',
      kind: LightingTargetKind.customGroup,
      memberDeviceIds: targetDeviceIds,
    ),
    issues: issues,
  );
}

LightingTarget? _directTarget(String id, DebugDevice? device) {
  if (device == null) {
    return null;
  }
  return LightingTarget(
    id: device.appDeviceId,
    name: device.endpoint.displayName ?? 'Без назви',
    kind: LightingTargetKind.device,
    memberDeviceIds: <String>{device.appDeviceId},
    protocolId: device.protocolId,
  );
}

LightingFeature _featureFor(SceneParameter parameter) => switch (parameter) {
  SceneParameter.power => LightingFeature.power,
  SceneParameter.brightness => LightingFeature.brightness,
  SceneParameter.color => LightingFeature.rgb,
};

String _controlLabel(SceneCustomControl control) =>
    control.label ?? sceneParameterLabel(control.type.parameter);

List<String> _resultErrors(Iterable<CommandResult> results) {
  final errors = <String>[];
  for (final result in results) {
    if (result.outcome != CommandOutcome.rejected &&
        result.outcome != CommandOutcome.failed &&
        result.outcome != CommandOutcome.timedOut) {
      continue;
    }
    errors.add(
      result.detail ?? result.error?.toString() ?? 'Команда не була прийнята.',
    );
  }
  return List<String>.unmodifiable(errors);
}

class _QueuedSceneCommand {
  const _QueuedSceneCommand({
    required this.key,
    required this.revision,
    required this.scene,
    required this.control,
    required this.command,
    required this.logIssues,
  });

  final String key;
  final int revision;
  final LightingScene scene;
  final SceneCustomControl control;
  final LightingCommand command;
  final bool logIssues;
}
