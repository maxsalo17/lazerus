import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../../core/macros/registry/macro_module_registry.dart';
import '../../../core/macros/runtime/macro_lighting_delivery_bridge.dart';
import '../../../core/macros/templates/macro_template_transformer.dart';
import '../../debug/application/debug_devices_controller.dart';
import 'macro_library_controller.dart';

/// Builds a short-lived delivery bridge for exactly one runtime session.
///
/// A bridge must not be shared between sessions: each owns bounded pending
/// writes and a status stream that are closed when its runtime stops.
final macroLightingDeliveryBridgeFactoryProvider =
    Provider<MacroLightingDeliveryBridge Function()>((ref) {
      return () => MacroLightingDeliveryBridge(
        targetResolver: DebugMacroLightingTargetResolver(
          currentDevices: () => ref.read(debugDevicesProvider),
        ),
        deviceGateway: DebugMacroLightingDeviceGateway(
          currentDevices: () => ref.read(debugDevicesProvider),
          devicesController: ref.read(debugDevicesProvider.notifier),
        ),
      );
    });

final macroRuntimeSessionsProvider =
    NotifierProvider<MacroRuntimeSessionController, MacroRuntimeSessionsState>(
      MacroRuntimeSessionController.new,
    );

enum MacroRuntimeSessionLifecycle {
  idle,
  starting,
  running,
  stopped,
  invalid,
  error,
}

enum MacroRuntimeSessionEventKind {
  lifecycle,
  validation,
  delivery,
  telemetry,
  error,
}

/// Compact, transient telemetry derived from a runtime event.
///
/// This intentionally has no PCM payload. It carries only a compact RMS dBFS
/// meter reading for the microphone presentation module.
final class MacroRuntimeTelemetry {
  const MacroRuntimeTelemetry({
    required this.sourcePortId,
    required this.timestamp,
    required this.sequence,
    this.level,
    this.inputLevelDbfs,
  });

  final String sourcePortId;
  final Duration timestamp;
  final int sequence;
  final double? level;

  /// Root-mean-square microphone level in dBFS, clamped to the visible
  /// -72…0 dBFS range. This is transient presentation telemetry only.
  final double? inputLevelDbfs;
}

/// One UI-safe diagnostic event from a macro runtime session.
final class MacroRuntimeSessionEvent {
  const MacroRuntimeSessionEvent.lifecycle({
    required this.macroId,
    required this.lifecycle,
    this.detail,
  }) : kind = MacroRuntimeSessionEventKind.lifecycle,
       validationIssues = const <MacroGraphValidationIssue>[],
       delivery = null,
       telemetry = null,
       error = null;

  const MacroRuntimeSessionEvent.validation({
    required this.macroId,
    required this.validationIssues,
  }) : kind = MacroRuntimeSessionEventKind.validation,
       lifecycle = MacroRuntimeSessionLifecycle.invalid,
       detail = null,
       delivery = null,
       telemetry = null,
       error = null;

  const MacroRuntimeSessionEvent.delivery({
    required this.macroId,
    required this.delivery,
  }) : kind = MacroRuntimeSessionEventKind.delivery,
       lifecycle = null,
       validationIssues = const <MacroGraphValidationIssue>[],
       detail = null,
       telemetry = null,
       error = null;

  const MacroRuntimeSessionEvent.telemetry({
    required this.macroId,
    required this.telemetry,
  }) : kind = MacroRuntimeSessionEventKind.telemetry,
       lifecycle = null,
       validationIssues = const <MacroGraphValidationIssue>[],
       delivery = null,
       detail = null,
       error = null;

  const MacroRuntimeSessionEvent.error({
    required this.macroId,
    required this.error,
    required this.detail,
  }) : kind = MacroRuntimeSessionEventKind.error,
       lifecycle = MacroRuntimeSessionLifecycle.error,
       validationIssues = const <MacroGraphValidationIssue>[],
       delivery = null,
       telemetry = null;

  final String macroId;
  final MacroRuntimeSessionEventKind kind;
  final MacroRuntimeSessionLifecycle? lifecycle;
  final List<MacroGraphValidationIssue> validationIssues;
  final MacroLightingDeliveryStatus? delivery;
  final MacroRuntimeTelemetry? telemetry;
  final String? detail;
  final Object? error;
}

/// Latest runtime state for a single graph. Delivery diagnostics distinguish a
/// transport acceptance from physical-controller confirmation.
final class MacroRuntimeSessionStatus {
  const MacroRuntimeSessionStatus({
    required this.macroId,
    required this.lifecycle,
    this.validationIssues = const <MacroGraphValidationIssue>[],
    this.lastDelivery,
    this.lastTelemetry,
    this.outputValues = const <String, TriggerValue>{},
    this.detail,
    this.error,
  });

  final String macroId;
  final MacroRuntimeSessionLifecycle lifecycle;
  final List<MacroGraphValidationIssue> validationIssues;
  final MacroLightingDeliveryStatus? lastDelivery;
  final MacroRuntimeTelemetry? lastTelemetry;

  /// Latest typed value emitted by each macro output port.
  ///
  /// This is ephemeral runtime state for the patcher only. It is never merged
  /// into a graph definition, persistence record or diagnostic export.
  final Map<String, TriggerValue> outputValues;
  final String? detail;
  final Object? error;

  MacroRuntimeSessionStatus copyWith({
    MacroRuntimeSessionLifecycle? lifecycle,
    List<MacroGraphValidationIssue>? validationIssues,
    MacroLightingDeliveryStatus? lastDelivery,
    MacroRuntimeTelemetry? lastTelemetry,
    Map<String, TriggerValue>? outputValues,
    String? detail,
    Object? error,
  }) => MacroRuntimeSessionStatus(
    macroId: macroId,
    lifecycle: lifecycle ?? this.lifecycle,
    validationIssues: validationIssues ?? this.validationIssues,
    lastDelivery: lastDelivery ?? this.lastDelivery,
    lastTelemetry: lastTelemetry ?? this.lastTelemetry,
    outputValues: outputValues ?? this.outputValues,
    detail: detail ?? this.detail,
    error: error ?? this.error,
  );
}

/// State intended for presentation consumers. [recentEvents] is a
/// bounded snapshot; use [MacroRuntimeSessionController.events] for a live
/// diagnostic stream.
final class MacroRuntimeSessionsState {
  const MacroRuntimeSessionsState({
    this.sessions = const <String, MacroRuntimeSessionStatus>{},
    this.recentEvents = const <MacroRuntimeSessionEvent>[],
  });

  final Map<String, MacroRuntimeSessionStatus> sessions;
  final List<MacroRuntimeSessionEvent> recentEvents;

  MacroRuntimeSessionStatus? statusFor(String macroId) => sessions[macroId];
}

/// Explicit owner of all running macro graph runtimes.
///
/// This controller validates each saved graph against the currently installed
/// module registry, then owns the runtime, its lighting binding, delivery
/// bridge, and all diagnostic subscriptions until teardown completes.
final class MacroRuntimeSessionController
    extends Notifier<MacroRuntimeSessionsState> {
  static const _maxRecentEvents = 100;
  static const _visualTelemetryInterval = Duration(milliseconds: 50);
  static const _templateTransformer = MacroTemplateTransformer();

  late final MacroModuleRegistry _registry;
  late final MacroLightingDeliveryBridge Function() _newBridge;
  final Map<String, _ActiveMacroRuntimeSession> _active =
      <String, _ActiveMacroRuntimeSession>{};
  // A live editor update prepares its replacement asynchronously.  A run
  // generation prevents a replacement that was already preparing from
  // reviving a macro after the user has stopped it.
  final Map<String, int> _runGenerations = <String, int>{};
  // Stop also awaits any launch that was already past the editor debounce.
  // Otherwise it could report a stopped macro before a stale replacement has
  // completed the restoration path it inherited from the previous session.
  final Map<String, Set<Completer<void>>> _launchCompletions =
      <String, Set<Completer<void>>>{};
  // Raw runtime events can arrive much faster than the editor should rebuild.
  // Presentation modules independently interpret only their own event types;
  // this controller owns neither visual analysis nor node-specific settings.
  final Map<String, StreamController<TriggerEvent>> _runtimeFrameFeeds =
      <String, StreamController<TriggerEvent>>{};
  final StreamController<MacroRuntimeSessionEvent> _events =
      StreamController<MacroRuntimeSessionEvent>.broadcast();
  var _disposed = false;

  /// A live diagnostic stream. Consumers must cancel their own subscription.
  Stream<MacroRuntimeSessionEvent> get events => _events.stream;

  /// Live, unpersisted runtime events for one running macro.
  ///
  /// The stream is absent while the macro is not running. Frames are delivered
  /// synchronously and are deliberately not buffered; a concrete presentation
  /// module decides how to coalesce and render its own data.
  Stream<Object>? runtimeFramesFor(String macroId) =>
      _runtimeFrameFeeds[macroId]?.stream;

  @override
  MacroRuntimeSessionsState build() {
    _registry = ref.watch(macroModuleRegistryProvider);
    _newBridge = ref.watch(macroLightingDeliveryBridgeFactoryProvider);
    ref.onDispose(() {
      _disposed = true;
      unawaited(_disposeAll());
    });
    return const MacroRuntimeSessionsState();
  }

  /// Validates and starts the currently saved definition for [macroId].
  ///
  /// A second start replaces the prior session only after a valid replacement
  /// is prepared, so a macro can never retain two active microphone/module
  /// instances while a bad definition need not tear down a working one.
  Future<bool> start(String macroId) async {
    final definition = ref.read(macroLibraryProvider).byId(macroId);
    if (definition == null) {
      _setStatus(
        MacroRuntimeSessionStatus(
          macroId: macroId,
          lifecycle: MacroRuntimeSessionLifecycle.error,
          detail: 'The saved macro definition is unavailable.',
        ),
      );
      return false;
    }
    return _launch(
      definition,
      preserveRunningOnFailure: false,
      expectedRunGeneration: _advanceRunGeneration(macroId),
    );
  }

  /// Replaces an already running session with [definition] from an editor's
  /// in-memory draft. It does not persist that draft. Invalid changes leave the
  /// previous runtime active and surface repair diagnostics instead.
  Future<bool> updateRunning(MacroGraph definition) {
    final runGeneration = _runGenerations[definition.id];
    if (runGeneration == null || !_active.containsKey(definition.id)) {
      return Future<bool>.value(false);
    }
    return _launch(
      definition,
      preserveRunningOnFailure: true,
      expectedRunGeneration: runGeneration,
    );
  }

  Future<bool> _launch(
    MacroGraph definition, {
    required bool preserveRunningOnFailure,
    required int expectedRunGeneration,
  }) {
    final completion = Completer<void>();
    _launchCompletions
        .putIfAbsent(definition.id, () => <Completer<void>>{})
        .add(completion);
    return _launchInternal(
      definition,
      preserveRunningOnFailure: preserveRunningOnFailure,
      expectedRunGeneration: expectedRunGeneration,
    ).whenComplete(() {
      completion.complete();
      final completions = _launchCompletions[definition.id];
      completions?.remove(completion);
      if (completions?.isEmpty ?? false) {
        _launchCompletions.remove(definition.id);
      }
    });
  }

  Future<bool> _launchInternal(
    MacroGraph definition, {
    required bool preserveRunningOnFailure,
    required int expectedRunGeneration,
  }) async {
    final macroId = definition.id;
    if (!_isCurrentRunGeneration(macroId, expectedRunGeneration)) {
      return false;
    }
    final previousSession = _active[macroId];
    final executionDefinition = _templateTransformer.executionGraph(definition);
    final runtime = MacroRuntime(
      graph: executionDefinition,
      registry: _registry,
    );
    final issues = runtime.validate();
    if (issues.isNotEmpty) {
      await runtime.dispose();
      return _reportValidationFailure(
        macroId: macroId,
        issues: issues,
        previousSession: previousSession,
        preserveRunningOnFailure: preserveRunningOnFailure,
        expectedRunGeneration: expectedRunGeneration,
      );
    }

    final bridge = _newBridge();
    final binding = bridge.bind(runtime);
    final candidate = _ActiveMacroRuntimeSession(
      runtime: runtime,
      bridge: bridge,
      resetOnStop: definition.resetOnStop,
      binding: binding,
      deliverySubscription: bridge.statuses.listen(
        (delivery) => _onDelivery(macroId, delivery),
      ),
      telemetrySubscription: runtime.events.listen(
        (event) => _onRuntimeEvent(macroId, event),
      ),
    );
    try {
      // Preparing before releasing the prior session preserves a valid live
      // runtime when a module factory rejects new configuration.
      runtime.prepare();
    } on Object catch (error) {
      await candidate.dispose();
      if (!_isCurrentRunGeneration(macroId, expectedRunGeneration)) {
        return false;
      }
      _reportLaunchFailure(
        macroId: macroId,
        error: error,
        preserveRunning: preserveRunningOnFailure && previousSession != null,
      );
      return false;
    }

    // A live edit is a runtime replacement, not a Stop. Preserve the state
    // that existed before the macro originally began, then capture only newly
    // introduced targets from this definition.
    if (previousSession != null) {
      bridge.inheritRestorationStateFrom(previousSession.bridge);
    }
    bridge.captureStatesBeforeMacroWrites(executionDefinition.targetBindings);
    if (!_isCurrentRunGeneration(macroId, expectedRunGeneration)) {
      await candidate.dispose();
      return false;
    }

    _setStatus(
      MacroRuntimeSessionStatus(
        macroId: macroId,
        lifecycle: MacroRuntimeSessionLifecycle.starting,
      ),
    );
    final previous = _active.remove(macroId);
    if (previous != null) await previous.dispose();
    if (!_isCurrentRunGeneration(macroId, expectedRunGeneration)) {
      // Stop can happen while a live replacement has released the former
      // session. This candidate inherited its restoration baseline, so it
      // must finish that restore instead of merely disposing it.
      await candidate.stopAndRestore();
      return false;
    }
    try {
      _active[macroId] = candidate;
      _ensureRuntimeFrameFeed(macroId);
      runtime.start();
      // Some source/modifier nodes emit synchronously from start(). Preserve
      // those first output values for the patcher and input-priority UI rather
      // than replacing them with a fresh running status.
      final started = state.sessions[macroId];
      _setStatus(
        (started ??
                MacroRuntimeSessionStatus(
                  macroId: macroId,
                  lifecycle: MacroRuntimeSessionLifecycle.starting,
                ))
            .copyWith(lifecycle: MacroRuntimeSessionLifecycle.running),
      );
      return true;
    } on Object catch (error) {
      _active.remove(macroId);
      // A source can fail while starting after an eager modifier already
      // emitted. Treat that as a stopped macro run and restore its baseline.
      await candidate.stopAndRestore();
      _disposeRuntimeFrameFeed(macroId);
      _reportLaunchFailure(
        macroId: macroId,
        error: error,
        preserveRunning: false,
      );
      return false;
    }
  }

  Future<bool> _reportValidationFailure({
    required String macroId,
    required List<MacroGraphValidationIssue> issues,
    required _ActiveMacroRuntimeSession? previousSession,
    required bool preserveRunningOnFailure,
    required int expectedRunGeneration,
  }) async {
    if (!_isCurrentRunGeneration(macroId, expectedRunGeneration)) {
      return false;
    }
    final current = state.sessions[macroId];
    if (preserveRunningOnFailure &&
        previousSession != null &&
        current != null) {
      _updateStatus(
        current.copyWith(
          validationIssues: issues,
          detail: 'Live changes must be repaired before they can apply.',
        ),
      );
    } else {
      final status = MacroRuntimeSessionStatus(
        macroId: macroId,
        lifecycle: MacroRuntimeSessionLifecycle.invalid,
        validationIssues: issues,
        detail: 'The macro graph must be repaired before it can run.',
      );
      _setStatus(status);
    }
    _emit(
      MacroRuntimeSessionEvent.validation(
        macroId: macroId,
        validationIssues: issues,
      ),
    );
    return false;
  }

  void _reportLaunchFailure({
    required String macroId,
    required Object error,
    required bool preserveRunning,
  }) {
    final current = state.sessions[macroId];
    final detail = preserveRunning
        ? 'Live changes could not be applied; the current runtime continues.'
        : 'Could not start macro runtime.';
    if (preserveRunning && current != null) {
      _updateStatus(current.copyWith(detail: detail, error: error));
    } else {
      _setStatus(
        MacroRuntimeSessionStatus(
          macroId: macroId,
          lifecycle: MacroRuntimeSessionLifecycle.error,
          detail: detail,
          error: error,
        ),
      );
    }
    _emit(
      MacroRuntimeSessionEvent.error(
        macroId: macroId,
        error: error,
        detail: detail,
      ),
    );
  }

  /// Stops and releases one active runtime. Calling this for an already stopped
  /// macro is safe and leaves an explicit stopped diagnostic state. A Macro
  /// restores its pre-run state only when its persisted reset-on-stop setting
  /// is enabled.
  Future<void> stop(String macroId) async {
    // Invalidates a possibly in-flight live replacement before it can put a
    // candidate runtime back into [_active] after this method restores state.
    _advanceRunGeneration(macroId);
    final pendingLaunches =
        (_launchCompletions[macroId] ?? const <Completer<void>>{})
            .map((completion) => completion.future)
            .toList(growable: false);
    final session = _active.remove(macroId);
    if (session != null) await session.stopAndRestore();
    await Future.wait(pendingLaunches);
    if (!_active.containsKey(macroId)) {
      _disposeRuntimeFrameFeed(macroId);
    }
    if (!_disposed) {
      _setStatus(
        MacroRuntimeSessionStatus(
          macroId: macroId,
          lifecycle: MacroRuntimeSessionLifecycle.stopped,
        ),
      );
    }
  }

  Future<void> _disposeAll() async {
    final active = _active.entries.toList(growable: false);
    _active.clear();
    for (final entry in active) {
      _advanceRunGeneration(entry.key);
    }
    await Future.wait(active.map((entry) => entry.value.stopAndRestore()));
    final runtimeFrameFeeds = _runtimeFrameFeeds.values.toList(growable: false);
    _runtimeFrameFeeds.clear();
    for (final feed in runtimeFrameFeeds) {
      unawaited(feed.close());
    }
    await _events.close();
  }

  int _advanceRunGeneration(String macroId) {
    final next = (_runGenerations[macroId] ?? 0) + 1;
    _runGenerations[macroId] = next;
    return next;
  }

  bool _isCurrentRunGeneration(String macroId, int expected) =>
      !_disposed && _runGenerations[macroId] == expected;

  void _onDelivery(String macroId, MacroLightingDeliveryStatus delivery) {
    if (_disposed) return;
    final previous = state.sessions[macroId];
    if (previous == null) return;
    _updateStatus(previous.copyWith(lastDelivery: delivery));
    _emit(
      MacroRuntimeSessionEvent.delivery(macroId: macroId, delivery: delivery),
    );
  }

  void _onTelemetry(String macroId, MacroRuntimeTelemetry telemetry) {
    if (_disposed) return;
    final previous = state.sessions[macroId];
    if (previous == null) return;
    _updateStatus(previous.copyWith(lastTelemetry: telemetry));
  }

  void _onRuntimeEvent(String macroId, TriggerEvent event) {
    // The generic runtime only forwards raw typed data. A node presentation
    // module owns any visualization and decides whether this event is one of
    // its connected inputs.
    final runtimeFrameFeed = _runtimeFrameFeeds[macroId];
    if (runtimeFrameFeed != null && !runtimeFrameFeed.isClosed) {
      runtimeFrameFeed.add(event);
    }

    final value = event.primaryValue;
    if (value is TriggerGateValue ||
        value is TriggerLevelValue ||
        value is TriggerHsvValue) {
      _onOutputValue(macroId, event.sourcePortId, value);
      return;
    }
    if (value is! TriggerMonoAudioValue) return;

    // Compact session telemetry also feeds non-spectrum UI such as the level
    // meter. Keep it low-frequency so the macro editor itself does not rebuild
    // for every microphone frame.
    final previousTelemetry = state.sessions[macroId]?.lastTelemetry;
    if (previousTelemetry != null &&
        event.timestamp >= previousTelemetry.timestamp &&
        event.timestamp - previousTelemetry.timestamp <
            _visualTelemetryInterval) {
      return;
    }

    _onTelemetry(
      macroId,
      MacroRuntimeTelemetry(
        sourcePortId: event.sourcePortId,
        timestamp: event.timestamp,
        sequence: event.sequence,
        inputLevelDbfs: _dbfsFromSamples(value.values),
      ),
    );
  }

  void _ensureRuntimeFrameFeed(String macroId) {
    _runtimeFrameFeeds.putIfAbsent(
      macroId,
      () => StreamController<TriggerEvent>.broadcast(sync: true),
    );
  }

  void _disposeRuntimeFrameFeed(String macroId) {
    final feed = _runtimeFrameFeeds.remove(macroId);
    if (feed != null && !feed.isClosed) {
      unawaited(feed.close());
    }
  }

  void _onOutputValue(String macroId, String outputPortId, TriggerValue value) {
    if (_disposed) return;
    final previous = state.sessions[macroId];
    if (previous == null) return;
    _updateStatus(
      previous.copyWith(
        outputValues: Map<String, TriggerValue>.unmodifiable(
          <String, TriggerValue>{...previous.outputValues, outputPortId: value},
        ),
      ),
    );
  }

  static double _dbfsFromSamples(List<double> samples) {
    if (samples.isEmpty) return -72;
    var sumSquares = 0.0;
    for (final sample in samples) {
      sumSquares += sample * sample;
    }
    final rms = math.sqrt(sumSquares / samples.length);
    if (rms <= 0) return -72;
    final dbfs = 20 * math.log(rms) / math.ln10;
    return dbfs.clamp(-72.0, 0.0).toDouble();
  }

  void _setStatus(MacroRuntimeSessionStatus status) {
    _updateStatus(status);
    _emit(
      MacroRuntimeSessionEvent.lifecycle(
        macroId: status.macroId,
        lifecycle: status.lifecycle,
        detail: status.detail,
      ),
    );
  }

  void _updateStatus(MacroRuntimeSessionStatus status) {
    if (_disposed) return;
    state = MacroRuntimeSessionsState(
      sessions: <String, MacroRuntimeSessionStatus>{
        ...state.sessions,
        status.macroId: status,
      },
      recentEvents: state.recentEvents,
    );
  }

  void _emit(MacroRuntimeSessionEvent event) {
    if (_disposed) return;
    _events.add(event);
    final next = <MacroRuntimeSessionEvent>[...state.recentEvents, event];
    final bounded = next.length <= _maxRecentEvents
        ? next
        : next.sublist(next.length - _maxRecentEvents);
    state = MacroRuntimeSessionsState(
      sessions: state.sessions,
      recentEvents: bounded,
    );
  }
}

final class _ActiveMacroRuntimeSession {
  const _ActiveMacroRuntimeSession({
    required this.runtime,
    required this.bridge,
    required this.resetOnStop,
    required this.binding,
    required this.deliverySubscription,
    required this.telemetrySubscription,
  });

  final MacroRuntime runtime;
  final MacroLightingDeliveryBridge bridge;
  final bool resetOnStop;
  final MacroRuntimeLightingBinding binding;
  final StreamSubscription<MacroLightingDeliveryStatus> deliverySubscription;
  final StreamSubscription<TriggerEvent> telemetrySubscription;

  /// Stops event production and lets an already accepted macro write settle.
  /// When configured, it then restores the captured pre-macro desired state
  /// before closing the bridge.
  Future<void> stopAndRestore() async {
    await binding.close();
    await runtime.dispose();
    await bridge.drain();
    if (resetOnStop) {
      await bridge.restoreChangedDeviceStates();
    }
    await _closeObserversAndBridge();
  }

  /// Releases a session for a validated live replacement. It intentionally
  /// does not restore device state: the replacement inherits that state and
  /// remains the same logical macro run.
  Future<void> dispose() async {
    await binding.close();
    await runtime.dispose();
    await bridge.drain();
    await _closeObserversAndBridge();
  }

  Future<void> _closeObserversAndBridge() async {
    await deliverySubscription.cancel();
    await telemetrySubscription.cancel();
    await bridge.close();
  }
}
