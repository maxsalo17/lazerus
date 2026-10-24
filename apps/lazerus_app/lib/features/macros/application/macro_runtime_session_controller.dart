import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../../../core/macros/registry/macro_module_registry.dart';
import '../../../core/macros/runtime/macro_lighting_delivery_bridge.dart';
import '../../debug/application/debug_devices_controller.dart';
import '../../groups/application/custom_groups_controller.dart';
import '../../groups/application/group_targets.dart';
import 'macro_library_controller.dart';

/// Builds a short-lived delivery bridge for exactly one runtime session.
///
/// A bridge must not be shared between sessions: each owns bounded pending
/// writes and a status stream that are closed when its runtime stops.
final macroLightingDeliveryBridgeFactoryProvider =
    Provider<MacroLightingDeliveryBridge Function()>((ref) {
      Iterable<LightingTarget> currentGroups() {
        final devices = ref.read(debugDevicesProvider).devices.values;
        final customGroups = ref.read(customGroupsProvider);
        return <LightingTarget>[
          ...protocolGroupTargets(devices),
          ...customGroupTargets(customGroups.groups, devices),
        ];
      }

      return () => MacroLightingDeliveryBridge(
        targetResolver: DebugMacroLightingTargetResolver(
          currentDevices: () => ref.read(debugDevicesProvider),
          currentGroups: currentGroups,
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
/// This intentionally has no PCM payload. It carries only an RMS dBFS meter
/// reading and a decimated frequency spectrum that the macro editor can draw.
final class MacroRuntimeTelemetry {
  const MacroRuntimeTelemetry({
    required this.sourcePortId,
    required this.timestamp,
    required this.sequence,
    this.level,
    this.inputLevelDbfs,
    this.spectrum,
  });

  final String sourcePortId;
  final Duration timestamp;
  final int sequence;
  final double? level;

  /// Root-mean-square microphone level in dBFS, clamped to the visible
  /// -72…0 dBFS range. This is transient presentation telemetry only.
  final double? inputLevelDbfs;

  /// A decimated, frequency-addressable audio spectrum for the editor.
  ///
  /// The visual analyzer must not be used as a control input: the EQ trigger
  /// remains the source of truth for all runtime band calculations.
  final MacroRuntimeSpectrum? spectrum;
}

/// One in-memory spectrum snapshot for the macro editor.
///
/// Levels are linear, normalized amplitudes in the inclusive range 0…1;
/// [frequenciesHz] gives each corresponding bin centre. No PCM is retained.
final class MacroRuntimeSpectrum {
  MacroRuntimeSpectrum({
    required Iterable<double> frequenciesHz,
    required Iterable<double> levels,
    required this.sampleRateHz,
  }) : frequenciesHz = List<double>.unmodifiable(frequenciesHz),
       levels = List<double>.unmodifiable(levels) {
    if (this.frequenciesHz.length != this.levels.length) {
      throw ArgumentError(
        'Spectrum frequencies and levels must have the same length.',
      );
    }
  }

  final List<double> frequenciesHz;
  final List<double> levels;
  final int sampleRateHz;
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

/// State intended for Scene and presentation consumers. [recentEvents] is a
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
/// Scenes call [start] and [stop] rather than retaining runtime objects. This
/// controller validates each saved graph against the currently installed
/// module registry, then owns the runtime, its lighting binding, delivery
/// bridge, and all diagnostic subscriptions until teardown completes.
final class MacroRuntimeSessionController
    extends Notifier<MacroRuntimeSessionsState> {
  static const _maxRecentEvents = 100;
  static const _visualTelemetryInterval = Duration(milliseconds: 50);

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
  final StreamController<MacroRuntimeSessionEvent> _events =
      StreamController<MacroRuntimeSessionEvent>.broadcast();
  var _disposed = false;

  /// A live diagnostic stream. Consumers must cancel their own subscription.
  Stream<MacroRuntimeSessionEvent> get events => _events.stream;

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
    final runtime = MacroRuntime(graph: definition, registry: _registry);
    final issues = runtime.validate();
    if (issues.isNotEmpty) {
      await runtime.dispose();
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

    final bridge = _newBridge();
    final binding = bridge.bind(runtime);
    final candidate = _ActiveMacroRuntimeSession(
      runtime: runtime,
      bridge: bridge,
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
    bridge.captureStatesBeforeMacroWrites(definition.targetBindings);
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
      _reportLaunchFailure(
        macroId: macroId,
        error: error,
        preserveRunning: false,
      );
      return false;
    }
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
  /// macro is safe and leaves an explicit stopped diagnostic state. Before
  /// releasing the session it restores the locally tracked state from before
  /// the macro's first write, for devices this macro actually changed.
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
    final value = event.primaryValue;
    if (value is TriggerGateValue ||
        value is TriggerLevelValue ||
        value is TriggerHsvValue) {
      _onOutputValue(macroId, event.sourcePortId, value);
      return;
    }
    if (value is! TriggerMonoAudioValue) return;

    // The microphone may deliver smaller frames faster than Flutter should
    // repaint. Sampling at the EQ's default 50 ms cadence keeps the editor
    // visibly live without turning a source stream into a rebuild storm.
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
        spectrum: _spectrumFromMono(value),
      ),
    );
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

  /// Produces a short visual spectrum and immediately discards PCM samples.
  ///
  /// This is deliberately presentation telemetry, not an audio-analysis
  /// contract. Runtime modules remain the source of lighting decisions.
  static MacroRuntimeSpectrum _spectrumFromMono(TriggerMonoAudioValue audio) {
    const maximumBars = 36;
    final samples = audio.values;
    // A two-point Hann window has no non-zero samples, so it cannot produce
    // a meaningful normalized spectrum. The dB meter still uses that frame.
    if (samples.length < 3) {
      return MacroRuntimeSpectrum(
        frequenciesHz: const <double>[],
        levels: const <double>[],
        sampleRateHz: audio.sampleRateHz,
      );
    }
    // A bounded DFT frame is sufficient for the UI analyser. The EQ retains
    // its own deterministic DSP path and does not depend on this display work.
    final frameSize = math.min(samples.length, 1024);
    final maximumBin = frameSize ~/ 2;
    final binNumbers = <int>{};
    for (var index = 0; index < maximumBars; index++) {
      final fraction = maximumBars == 1 ? 0.0 : index / (maximumBars - 1);
      final bin = math.pow(maximumBin, fraction).round().clamp(1, maximumBin);
      binNumbers.add(bin.toInt());
    }
    final bins = binNumbers.toList()..sort();
    var windowSum = 0.0;
    final windowed = List<double>.generate(frameSize, (index) {
      final window =
          0.5 - 0.5 * math.cos((2 * math.pi * index) / (frameSize - 1));
      windowSum += window;
      return samples[index] * window;
    }, growable: false);
    final frequencies = <double>[];
    final levels = <double>[];
    for (final bin in bins) {
      // Goertzel has the same relevant single-bin DFT magnitude while avoiding
      // a trigonometric call for every source sample and visual bar.
      final coefficient = 2 * math.cos((2 * math.pi * bin) / frameSize);
      var previous = 0.0;
      var previousPrevious = 0.0;
      for (final sample in windowed) {
        final next = sample + coefficient * previous - previousPrevious;
        previousPrevious = previous;
        previous = next;
      }
      final power = math.max(
        0.0,
        previousPrevious * previousPrevious +
            previous * previous -
            coefficient * previous * previousPrevious,
      );
      frequencies.add(bin * audio.sampleRateHz / frameSize);
      levels.add((2 * math.sqrt(power) / windowSum).clamp(0.0, 1.0).toDouble());
    }
    return MacroRuntimeSpectrum(
      frequenciesHz: frequencies,
      levels: levels,
      sampleRateHz: audio.sampleRateHz,
    );
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
    required this.binding,
    required this.deliverySubscription,
    required this.telemetrySubscription,
  });

  final MacroRuntime runtime;
  final MacroLightingDeliveryBridge bridge;
  final MacroRuntimeLightingBinding binding;
  final StreamSubscription<MacroLightingDeliveryStatus> deliverySubscription;
  final StreamSubscription<TriggerEvent> telemetrySubscription;

  /// Stops event production, lets an already accepted macro write settle, and
  /// restores the captured pre-macro desired state before closing the bridge.
  Future<void> stopAndRestore() async {
    await binding.close();
    await runtime.dispose();
    await bridge.drain();
    await bridge.restoreChangedDeviceStates();
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
