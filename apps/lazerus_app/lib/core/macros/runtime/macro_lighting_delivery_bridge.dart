import 'dart:async';
import 'dart:developer' as developer;

import 'package:lazerus_core/lazerus_core.dart';

import '../../../features/debug/application/debug_devices_controller.dart';
import '../../../features/groups/application/group_targets.dart';

/// Resolves saved macro target references against the app's current devices
/// and derived/custom groups.
///
/// Resolution intentionally happens for every [MacroLightingIntent]. A saved
/// group is only configuration; its available members can change while a macro
/// is running.
abstract interface class MacroLightingTargetResolver {
  Iterable<String> resolve({
    required MacroTargetKind targetKind,
    required String targetId,
  });
}

/// Narrow application boundary used by [MacroLightingDeliveryBridge].
///
/// The bridge knows neither BLE nor a protocol adapter. The implementation at
/// the composition root must check the current connection and capabilities
/// immediately before it calls the existing device command controller.
abstract interface class MacroLightingDeviceGateway {
  /// Returns whether [state] can be sent to this device *now*.
  ///
  /// This must include connection state and every represented capability. A
  /// false result is a local drop, not a statement about a controller.
  bool canDispatch(String appDeviceId, DesiredLightingState state);

  /// Requests a transport write. A returned [CommandOutcome.transmitted] only
  /// reports the transport boundary; it is not physical-device confirmation.
  Future<CommandResult> dispatch(
    String appDeviceId,
    ApplyLightingState command,
  );
}

/// Resolves macro references against the current Debug Devices state and the
/// current derived protocol/custom group targets.
///
/// The two getters keep this adapter UI-free while allowing a composition root
/// to supply fresh Riverpod state for every intent. A stale saved group or
/// device reference simply resolves to no live targets and is reported as a
/// dropped update by the bridge.
final class DebugMacroLightingTargetResolver
    implements MacroLightingTargetResolver {
  DebugMacroLightingTargetResolver({
    required DebugModuleState Function() currentDevices,
    required Iterable<LightingTarget> Function() currentGroups,
  }) : _currentDevices = currentDevices,
       _currentGroups = currentGroups;

  final DebugModuleState Function() _currentDevices;
  final Iterable<LightingTarget> Function() _currentGroups;

  @override
  Iterable<String> resolve({
    required MacroTargetKind targetKind,
    required String targetId,
  }) {
    final devices = _currentDevices().devices;
    return switch (targetKind) {
      MacroTargetKind.device =>
        devices.containsKey(targetId) ? <String>{targetId} : const <String>{},
      MacroTargetKind.group =>
        _currentGroups()
            .where((group) => group.id == targetId)
            .expand((group) => group.memberDeviceIds)
            .where(devices.containsKey)
            .toSet(),
    };
  }
}

/// Current app adapter for [DebugDevicesController].
///
/// Capability and connection checks happen both here and in the controller's
/// command path. The duplicate boundary is intentional: macro requests can
/// wait behind an in-flight write while a device disconnects or changes its
/// profile.
final class DebugMacroLightingDeviceGateway
    implements MacroLightingDeviceGateway {
  DebugMacroLightingDeviceGateway({
    required DebugModuleState Function() currentDevices,
    required DebugDevicesController devicesController,
  }) : _currentDevices = currentDevices,
       _devicesController = devicesController;

  final DebugModuleState Function() _currentDevices;
  final DebugDevicesController _devicesController;

  @override
  bool canDispatch(String appDeviceId, DesiredLightingState state) {
    if (state.isEmpty) {
      return false;
    }
    final current = _currentDevices();
    if (!current.diagnosticCommandsEnabled) {
      return false;
    }
    final device = current.devices[appDeviceId];
    if (device == null ||
        device.status != DebugDeviceConnectionStatus.connected) {
      return false;
    }
    final capabilities = device.capabilities;
    if (capabilities == null) {
      return false;
    }
    return (state.power == null ||
            capabilities.supports(
              LightingFeature.power,
              allowInferred: true,
            )) &&
        (state.color == null ||
            (capabilities.supports(LightingFeature.rgb, allowInferred: true) ||
                capabilities.supports(
                  LightingFeature.rgbw,
                  allowInferred: true,
                ))) &&
        (state.brightness == null ||
            capabilities.supports(
              LightingFeature.brightness,
              allowInferred: true,
            ));
  }

  @override
  Future<CommandResult> dispatch(
    String appDeviceId,
    ApplyLightingState command,
  ) => _devicesController.execute(appDeviceId, command);
}

/// A local lifecycle fact for one macro-to-device request.
enum MacroLightingDeliveryOutcome {
  queued,
  superseded,
  dropped,
  transmitted,
  rejected,
  failed,
  timedOut,
}

/// A diagnostic event emitted by [MacroLightingDeliveryBridge].
///
/// In particular, [MacroLightingDeliveryOutcome.transmitted] means that the
/// device gateway accepted a transport write. It deliberately does not claim
/// that a strip applied the requested state.
final class MacroLightingDeliveryStatus {
  const MacroLightingDeliveryStatus({
    required this.intent,
    required this.appDeviceId,
    required this.outcome,
    required this.desiredState,
    this.transportOutcome,
    this.detail,
    this.error,
  });

  final MacroLightingIntent intent;
  final String appDeviceId;
  final MacroLightingDeliveryOutcome outcome;
  final DesiredLightingState desiredState;
  final CommandOutcome? transportOutcome;
  final String? detail;
  final Object? error;
}

/// UI-free, bounded delivery adapter for reactive Scene Macro lighting output.
///
/// It permits exactly one write at a time for each physical device. A macro
/// value received while that write is pending or in flight is dropped locally;
/// it cannot replace the current write or form a delayed queue. This class is
/// not a retry queue and makes no delivery guarantee.
final class MacroLightingDeliveryBridge {
  MacroLightingDeliveryBridge({
    required MacroLightingTargetResolver targetResolver,
    required MacroLightingDeviceGateway deviceGateway,
  }) : _targetResolver = targetResolver,
       _deviceGateway = deviceGateway;

  final MacroLightingTargetResolver _targetResolver;
  final MacroLightingDeviceGateway _deviceGateway;
  final Map<String, _DeviceQueue> _queues = <String, _DeviceQueue>{};
  final StreamController<MacroLightingDeliveryStatus> _statuses =
      StreamController<MacroLightingDeliveryStatus>.broadcast();
  var _closed = false;

  Stream<MacroLightingDeliveryStatus> get statuses => _statuses.stream;

  /// Resolves and schedules one typed macro intent. Invalid value/parameter
  /// combinations are dropped locally rather than being sent as raw commands.
  void submit(MacroLightingIntent intent) {
    if (_closed) {
      return;
    }
    final partialState = _stateFor(intent);
    if (partialState == null) {
      _emit(
        MacroLightingDeliveryStatus(
          intent: intent,
          appDeviceId: '',
          outcome: MacroLightingDeliveryOutcome.dropped,
          desiredState: DesiredLightingState(),
          detail:
              'The trigger value is incompatible with this target parameter.',
        ),
      );
      return;
    }

    final deviceIds = _targetResolver
        .resolve(targetKind: intent.targetKind, targetId: intent.targetId)
        .toSet();
    if (deviceIds.isEmpty) {
      _emit(
        MacroLightingDeliveryStatus(
          intent: intent,
          appDeviceId: '',
          outcome: MacroLightingDeliveryOutcome.dropped,
          desiredState: partialState,
          detail: 'The macro target has no currently available devices.',
        ),
      );
      return;
    }

    for (final deviceId in deviceIds) {
      _submitToDevice(deviceId, intent, partialState);
    }
  }

  /// Completes after all currently queued writes settle. It is intended for
  /// lifecycle teardown and focused tests, not for a Flutter widget build.
  Future<void> drain() async {
    while (_queues.values.any(
      (queue) => queue.inFlight || queue.pending != null,
    )) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    _queues.clear();
    await _statuses.close();
  }

  /// Starts forwarding [runtime] output through this bounded bridge.
  ///
  /// The caller starts this binding before starting the runtime, and closes it
  /// before disposing either owner. Keeping subscription ownership explicit
  /// prevents a macro graph or a widget from retaining a hidden stream.
  MacroRuntimeLightingBinding bind(MacroRuntime runtime) =>
      MacroRuntimeLightingBinding._(runtime, this);

  void _submitToDevice(
    String deviceId,
    MacroLightingIntent intent,
    DesiredLightingState partialState,
  ) {
    final existingQueue = _queues[deviceId];
    if (existingQueue != null &&
        (existingQueue.inFlight || existingQueue.pending != null)) {
      _emit(
        MacroLightingDeliveryStatus(
          intent: intent,
          appDeviceId: deviceId,
          outcome: MacroLightingDeliveryOutcome.dropped,
          desiredState: partialState,
          detail:
              'A macro device update is already pending or in flight; the newer value was ignored.',
        ),
      );
      return;
    }

    // Recheck before storing a desired state. This avoids retaining an
    // unsupported field which could poison a later merged update.
    if (!_deviceGateway.canDispatch(deviceId, partialState)) {
      _emit(
        MacroLightingDeliveryStatus(
          intent: intent,
          appDeviceId: deviceId,
          outcome: MacroLightingDeliveryOutcome.dropped,
          desiredState: partialState,
          detail: 'Device is disconnected or does not support this parameter.',
        ),
      );
      return;
    }

    final queue =
        existingQueue ?? _queues.putIfAbsent(deviceId, _DeviceQueue.new);
    final desired = _merge(queue.latestDesired, partialState);
    queue.latestDesired = desired;
    queue.pending = _PendingDelivery(intent, desired);
    _emit(
      MacroLightingDeliveryStatus(
        intent: intent,
        appDeviceId: deviceId,
        outcome: MacroLightingDeliveryOutcome.queued,
        desiredState: desired,
      ),
    );
    _pump(deviceId, queue);
  }

  void _pump(String deviceId, _DeviceQueue queue) {
    if (_closed || queue.inFlight) {
      return;
    }
    final pending = queue.pending;
    if (pending == null) {
      return;
    }
    queue.pending = null;
    queue.inFlight = true;
    unawaited(_dispatch(deviceId, queue, pending));
  }

  Future<void> _dispatch(
    String deviceId,
    _DeviceQueue queue,
    _PendingDelivery pending,
  ) async {
    try {
      // A device can disconnect or a capability profile can change between
      // enqueue and dispatch, so this is deliberately checked again here.
      if (!_deviceGateway.canDispatch(deviceId, pending.desiredState)) {
        _emit(
          MacroLightingDeliveryStatus(
            intent: pending.intent,
            appDeviceId: deviceId,
            outcome: MacroLightingDeliveryOutcome.dropped,
            desiredState: pending.desiredState,
            detail: 'Device is no longer available for this macro update.',
          ),
        );
        return;
      }
      final result = await _deviceGateway.dispatch(
        deviceId,
        ApplyLightingState(pending.desiredState),
      );
      _emit(_statusForResult(deviceId, pending, result));
    } on Object catch (error) {
      _emit(
        MacroLightingDeliveryStatus(
          intent: pending.intent,
          appDeviceId: deviceId,
          outcome: MacroLightingDeliveryOutcome.failed,
          desiredState: pending.desiredState,
          detail: 'The device gateway threw while sending the macro update.',
          error: error,
        ),
      );
    } finally {
      queue.inFlight = false;
      if (!_closed) {
        _pump(deviceId, queue);
      }
    }
  }

  MacroLightingDeliveryStatus _statusForResult(
    String deviceId,
    _PendingDelivery pending,
    CommandResult result,
  ) {
    final outcome = switch (result.outcome) {
      CommandOutcome.queued => MacroLightingDeliveryOutcome.queued,
      CommandOutcome.transmitted ||
      CommandOutcome.acknowledged ||
      CommandOutcome.observed => MacroLightingDeliveryOutcome.transmitted,
      CommandOutcome.rejected => MacroLightingDeliveryOutcome.rejected,
      CommandOutcome.failed => MacroLightingDeliveryOutcome.failed,
      CommandOutcome.timedOut => MacroLightingDeliveryOutcome.timedOut,
      CommandOutcome.superseded ||
      CommandOutcome.dropped => MacroLightingDeliveryOutcome.dropped,
    };
    return MacroLightingDeliveryStatus(
      intent: pending.intent,
      appDeviceId: deviceId,
      outcome: outcome,
      desiredState: pending.desiredState,
      transportOutcome: result.outcome,
      detail: result.detail,
      error: result.error,
    );
  }

  static DesiredLightingState? _stateFor(MacroLightingIntent intent) {
    return switch ((intent.parameter, intent.value)) {
      (MacroTargetParameter.power, TriggerGateValue(:final value)) =>
        DesiredLightingState(power: value),
      (MacroTargetParameter.brightness, TriggerLevelValue(:final value)) =>
        DesiredLightingState(brightness: value),
      _ => null,
    };
  }

  static DesiredLightingState _merge(
    DesiredLightingState? previous,
    DesiredLightingState incoming,
  ) => DesiredLightingState(
    power: incoming.power ?? previous?.power,
    color: incoming.color ?? previous?.color,
    brightness: incoming.brightness ?? previous?.brightness,
  );

  void _emit(MacroLightingDeliveryStatus status) {
    if (!_closed) {
      _logDeliveryStatus(status);
      _statuses.add(status);
    }
  }

  /// Emits a compact IDE-console trace for the local delivery lifecycle.
  ///
  /// This deliberately logs only scalar lighting target values. In particular,
  /// it never stringifies a [TriggerValue], which could otherwise expose a
  /// microphone PCM payload from an incompatible trigger.
  static void _logDeliveryStatus(MacroLightingDeliveryStatus status) {
    final intent = status.intent;
    developer.log(
      'macroId=${intent.macroId} '
      'bindingId=${intent.bindingId} '
      'deviceId=${status.appDeviceId.isEmpty ? '<unresolved>' : status.appDeviceId} '
      'parameter=${intent.parameter.name} '
      'value=${_loggableValue(intent.value)} '
      'lifecycle=${status.outcome.name} '
      'transport=${status.transportOutcome?.name ?? 'none'}',
      name: 'Lazerus.MacroLightingDeliveryBridge',
    );
  }

  static String _loggableValue(TriggerValue value) => switch (value) {
    TriggerGateValue(:final value) => value.toString(),
    TriggerLevelValue(:final value) => value.toString(),
    _ => '<${value.runtimeType}>',
  };
}

/// Explicit subscription between a running macro and its delivery boundary.
///
/// This does not start or stop the runtime and does not own the bridge. The
/// application composition root selects those lifecycles; this small owner
/// only makes forwarding and cancellation deterministic.
final class MacroRuntimeLightingBinding {
  MacroRuntimeLightingBinding._(
    MacroRuntime runtime,
    MacroLightingDeliveryBridge bridge,
  ) : _subscription = runtime.lightingIntents.listen(bridge.submit);

  final StreamSubscription<MacroLightingIntent> _subscription;

  Future<void> close() => _subscription.cancel();
}

final class _DeviceQueue {
  var inFlight = false;
  DesiredLightingState? latestDesired;
  _PendingDelivery? pending;
}

final class _PendingDelivery {
  const _PendingDelivery(this.intent, this.desiredState);

  final MacroLightingIntent intent;
  final DesiredLightingState desiredState;
}
