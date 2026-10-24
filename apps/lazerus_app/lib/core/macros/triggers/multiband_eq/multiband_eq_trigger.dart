/// A transport-neutral, deterministic multi-band audio trigger.
library;

import 'dart:math' as math;

import 'package:lazerus_core/lazerus_core.dart';

/// The persisted node kind for [MultibandEqTriggerFactory].
const String multibandEqTriggerKind = 'trigger.multiband_eq';

/// The lowest representable amplitude for EQ configuration and display.
///
/// Zero-amplitude legacy values are mapped here because dBFS is undefined at
/// zero. This matches the bounded analyzer scale.
const double multibandEqMinimumDbfs = -72;
const double multibandEqMaximumDbfs = 0;
const String _amplitudeUnitDbfs = 'dbfs';

/// The kind of event emitted for a configured frequency band.
enum MultibandEqBandMode { gate, level }

/// Serializable configuration for a single output band.
///
/// [id] is part of the saved graph contract. Renaming it changes the output
/// port and must therefore be treated as a graph edit, rather than presentation
/// metadata.
final class MultibandEqBandDefinition {
  MultibandEqBandDefinition({
    required this.id,
    required this.lowerFrequencyHz,
    required this.upperFrequencyHz,
    required this.mode,
    this.gateThreshold,
    this.gateHysteresis = 0,
    this.normalizationMinimum,
    this.normalizationMaximum,
    this.attack = Duration.zero,
    this.release = Duration.zero,
    this.outputBuffer = const Duration(milliseconds: 50),
  }) {
    if (id.trim().isEmpty) {
      throw ArgumentError.value(id, 'id', 'Must not be blank.');
    }
    if (!lowerFrequencyHz.isFinite || lowerFrequencyHz < 0) {
      throw ArgumentError.value(
        lowerFrequencyHz,
        'lowerFrequencyHz',
        'Must be finite and at least zero.',
      );
    }
    if (!upperFrequencyHz.isFinite || upperFrequencyHz <= lowerFrequencyHz) {
      throw ArgumentError.value(
        upperFrequencyHz,
        'upperFrequencyHz',
        'Must be finite and greater than lowerFrequencyHz.',
      );
    }
    if (attack.isNegative || release.isNegative || outputBuffer.isNegative) {
      throw ArgumentError(
        'Attack, release and output buffer must not be negative.',
      );
    }
    switch (mode) {
      case MultibandEqBandMode.gate:
        if (gateThreshold == null ||
            !gateThreshold!.isFinite ||
            gateThreshold! < multibandEqMinimumDbfs ||
            gateThreshold! > multibandEqMaximumDbfs) {
          throw ArgumentError.value(
            gateThreshold,
            'gateThreshold',
            'A gate threshold in dBFS is required for gate bands.',
          );
        }
        if (!gateHysteresis.isFinite ||
            gateHysteresis < 0 ||
            gateHysteresis > gateThreshold! - multibandEqMinimumDbfs) {
          throw ArgumentError.value(
            gateHysteresis,
            'gateHysteresis',
            'Must be in the range 0..(gateThreshold - minimum dBFS).',
          );
        }
        if (normalizationMinimum != null || normalizationMaximum != null) {
          throw ArgumentError(
            'Gate bands cannot specify a normalization range.',
          );
        }
      case MultibandEqBandMode.level:
        if (gateThreshold != null || gateHysteresis != 0) {
          throw ArgumentError(
            'Level bands cannot specify gate threshold or hysteresis.',
          );
        }
        if (normalizationMinimum == null ||
            normalizationMaximum == null ||
            !normalizationMinimum!.isFinite ||
            !normalizationMaximum!.isFinite ||
            normalizationMinimum! < multibandEqMinimumDbfs ||
            normalizationMaximum! > multibandEqMaximumDbfs ||
            normalizationMaximum! <= normalizationMinimum!) {
          throw ArgumentError(
            'Level bands require a finite normalization range where maximum '
            'is greater than minimum and both are within the dBFS range.',
          );
        }
    }
  }

  final String id;
  final double lowerFrequencyHz;
  final double upperFrequencyHz;
  final MultibandEqBandMode mode;
  final double? gateThreshold;
  final double gateHysteresis;
  final double? normalizationMinimum;
  final double? normalizationMaximum;
  final Duration attack;
  final Duration release;

  /// Per-output peak-hold window. A zero duration forwards every calculated
  /// trigger value immediately; any positive duration emits only the maximum
  /// level (or an OR-ed gate) observed during each window.
  final Duration outputBuffer;

  Map<String, Object?> toJson() => <String, Object?>{
    'id': id,
    'lowerFrequencyHz': lowerFrequencyHz,
    'upperFrequencyHz': upperFrequencyHz,
    'mode': mode.name,
    'amplitudeUnit': _amplitudeUnitDbfs,
    if (gateThreshold != null) 'gateThreshold': gateThreshold,
    if (gateHysteresis != 0) 'gateHysteresis': gateHysteresis,
    if (normalizationMinimum != null)
      'normalizationMinimum': normalizationMinimum,
    if (normalizationMaximum != null)
      'normalizationMaximum': normalizationMaximum,
    'attackMilliseconds': attack.inMilliseconds,
    'releaseMilliseconds': release.inMilliseconds,
    'outputBufferMilliseconds': outputBuffer.inMilliseconds,
  };

  factory MultibandEqBandDefinition.fromJson(Map<String, Object?> json) {
    T required<T>(String key) {
      final value = json[key];
      if (value is! T) {
        throw FormatException('"$key" must be a $T.');
      }
      return value;
    }

    double number(String key) {
      final value = json[key];
      if (value is num) return value.toDouble();
      throw FormatException('"$key" must be a number.');
    }

    double? optionalNumber(String key) {
      final value = json[key];
      if (value == null) return null;
      if (value is num) return value.toDouble();
      throw FormatException('"$key" must be a number when supplied.');
    }

    int durationMilliseconds(String key, {int defaultValue = 0}) {
      final value = json[key] ?? defaultValue;
      if (value is int) return value;
      throw FormatException('"$key" must be an integer.');
    }

    final modeName = required<String>('mode');
    final mode = MultibandEqBandMode.values.where(
      (candidate) => candidate.name == modeName,
    );
    if (mode.isEmpty) throw FormatException('Unknown band mode "$modeName".');
    final isLegacyLinear = json['amplitudeUnit'] == null;
    if (!isLegacyLinear && json['amplitudeUnit'] != _amplitudeUnitDbfs) {
      throw FormatException('"amplitudeUnit" must be "$_amplitudeUnitDbfs".');
    }
    final legacyGateThreshold = optionalNumber('gateThreshold');
    final legacyGateHysteresis = optionalNumber('gateHysteresis') ?? 0;
    final gateThreshold = isLegacyLinear && legacyGateThreshold != null
        ? _linearToDbfs(legacyGateThreshold)
        : legacyGateThreshold;
    final gateHysteresis = isLegacyLinear && legacyGateThreshold != null
        ? _legacyHysteresisToDb(
            threshold: legacyGateThreshold,
            hysteresis: legacyGateHysteresis,
          )
        : legacyGateHysteresis;
    final normalizationMinimum = optionalNumber('normalizationMinimum');
    final normalizationMaximum = optionalNumber('normalizationMaximum');
    return MultibandEqBandDefinition(
      id: required<String>('id'),
      lowerFrequencyHz: number('lowerFrequencyHz'),
      upperFrequencyHz: number('upperFrequencyHz'),
      mode: mode.single,
      gateThreshold: gateThreshold,
      gateHysteresis: gateHysteresis,
      normalizationMinimum: isLegacyLinear && normalizationMinimum != null
          ? _linearToDbfs(normalizationMinimum)
          : normalizationMinimum,
      normalizationMaximum: isLegacyLinear && normalizationMaximum != null
          ? _linearToDbfs(normalizationMaximum)
          : normalizationMaximum,
      attack: Duration(
        milliseconds: durationMilliseconds('attackMilliseconds'),
      ),
      release: Duration(
        milliseconds: durationMilliseconds('releaseMilliseconds'),
      ),
      // Existing macro JSON predates this field. Its compatibility default is
      // deliberately the safe, bounded cadence rather than an output burst.
      outputBuffer: Duration(
        milliseconds: durationMilliseconds(
          'outputBufferMilliseconds',
          defaultValue: 50,
        ),
      ),
    );
  }
}

/// Serializable dynamic port configuration stored in a node's `bands` field.
final class MultibandEqTriggerConfiguration {
  MultibandEqTriggerConfiguration({
    required Iterable<MultibandEqBandDefinition> bands,
    this.outputInterval = const Duration(milliseconds: 50),
  }) : bands = List<MultibandEqBandDefinition>.unmodifiable(bands) {
    if (this.bands.isEmpty) {
      throw ArgumentError.value(
        bands,
        'bands',
        'At least one band is required.',
      );
    }
    final ids = this.bands.map((band) => band.id).toSet();
    if (ids.length != this.bands.length) {
      throw ArgumentError.value(bands, 'bands', 'Band IDs must be unique.');
    }
    if (outputInterval <= Duration.zero) {
      throw ArgumentError.value(
        outputInterval,
        'outputInterval',
        'Must be greater than zero.',
      );
    }
  }

  final List<MultibandEqBandDefinition> bands;

  /// Legacy graph-level field retained only to decode existing macro JSON.
  ///
  /// Output cadence is now owned by [MultibandEqBandDefinition.outputBuffer],
  /// which preserves peak values instead of dropping frames before a band can
  /// observe them.
  @Deprecated('Configure MultibandEqBandDefinition.outputBuffer instead.')
  final Duration outputInterval;

  Map<String, Object?> toNodeParameters() => <String, Object?>{
    'bands': bands.map((band) => band.toJson()).toList(growable: false),
    'outputIntervalMilliseconds': outputInterval.inMilliseconds,
  };

  factory MultibandEqTriggerConfiguration.fromNodeParameters(
    Map<String, Object?> parameters,
  ) {
    final encodedBands = parameters['bands'];
    if (encodedBands is! List<Object?>) {
      throw FormatException('"bands" must be a list of band definitions.');
    }
    final outputIntervalMilliseconds =
        parameters['outputIntervalMilliseconds'] ?? 50;
    if (outputIntervalMilliseconds is! int) {
      throw FormatException('"outputIntervalMilliseconds" must be an integer.');
    }
    return MultibandEqTriggerConfiguration(
      bands: encodedBands.map((value) {
        if (value is! Map<Object?, Object?>) {
          throw FormatException('Each band must be a JSON object.');
        }
        return MultibandEqBandDefinition.fromJson(
          Map<String, Object?>.from(value),
        );
      }),
      outputInterval: Duration(milliseconds: outputIntervalMilliseconds),
    );
  }
}

/// Factory for a node with one mono-audio input and one typed output per band.
final class MultibandEqTriggerFactory
    implements
        MacroModuleFactory,
        MacroNodePortContractProvider,
        MacroTriggerDefinition {
  @override
  String get kind => multibandEqTriggerKind;

  @override
  String get displayName => 'Multiband EQ';

  /// Backwards-compatible static fallback. Configured nodes use [portsFor].
  @override
  List<MacroPortDeclaration> get ports => <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: 'audio',
      direction: MacroPortDirection.input,
      type: MacroPortType.triggerMonoAudio,
      displayIdentifier: 'audio',
    ),
  ];

  /// Dynamic node contract. The runtime registry should use this method when
  /// validating a configured node, rather than the static [ports] fallback.
  @override
  List<MacroPortDeclaration> portsFor(MacroNode node) {
    final configuration = MultibandEqTriggerConfiguration.fromNodeParameters(
      node.parameters,
    );
    return <MacroPortDeclaration>[
      MacroPortDeclaration(
        id: inputPortId(node),
        direction: MacroPortDirection.input,
        type: MacroPortType.triggerMonoAudio,
        displayIdentifier: 'audio',
        displayName: 'Mono audio',
      ),
      for (final band in configuration.bands)
        MacroPortDeclaration(
          id: outputPortId(node, band.id),
          direction: MacroPortDirection.output,
          type: band.mode == MultibandEqBandMode.gate
              ? MacroPortType.triggerGate
              : MacroPortType.triggerLevel,
          displayIdentifier: 'band.${band.id}',
          displayName: band.id,
        ),
    ];
  }

  String inputPortId(MacroNode node) => '${node.id}.audio';

  String outputPortId(MacroNode node, String bandId) =>
      '${node.id}.band.$bandId';

  @override
  MacroModuleInstance create(MacroNode node) => _MultibandEqTriggerInstance(
    inputPortId: inputPortId(node),
    configuration: MultibandEqTriggerConfiguration.fromNodeParameters(
      node.parameters,
    ),
    outputPortId: (bandId) => outputPortId(node, bandId),
  );
}

final class _MultibandEqTriggerInstance implements MacroModuleInstance {
  _MultibandEqTriggerInstance({
    required this.inputPortId,
    required this.configuration,
    required this.outputPortId,
  });

  final String inputPortId;
  final MultibandEqTriggerConfiguration configuration;
  final String Function(String bandId) outputPortId;
  final Map<String, _BandState> _states = <String, _BandState>{};
  MacroRuntimeEventEmitter? _emitter;

  List<MultibandEqBandDefinition> get bands => configuration.bands;

  @override
  void start(MacroRuntimeEventEmitter emitter) => _emitter = emitter;

  @override
  void onInput(String inputPortId, TriggerEvent event) {
    if (inputPortId != this.inputPortId ||
        event.primaryValue is! TriggerMonoAudioValue ||
        _emitter == null) {
      return;
    }
    final audio = event.primaryValue as TriggerMonoAudioValue;
    final energies = _bandEnergies(audio, bands);
    for (var index = 0; index < bands.length; index++) {
      final band = bands[index];
      final state = _states.putIfAbsent(band.id, _BandState.new);
      final smoothed = state.smooth(
        energies[index],
        event.timestamp,
        attack: band.attack,
        release: band.release,
      );
      final smoothedDbfs = _linearToDbfs(smoothed);
      final TriggerValue value;
      switch (band.mode) {
        case MultibandEqBandMode.gate:
          final closeThreshold = band.gateThreshold! - band.gateHysteresis;
          state.gateOpen = state.gateOpen
              ? smoothedDbfs >= closeThreshold
              : smoothedDbfs >= band.gateThreshold!;
          value = TriggerGateValue(state.gateOpen);
        case MultibandEqBandMode.level:
          value = TriggerLevelValue(
            ((smoothedDbfs - band.normalizationMinimum!) /
                    (band.normalizationMaximum! - band.normalizationMinimum!))
                .clamp(0.0, 1.0)
                .toDouble(),
          );
      }
      final buffered = state.bufferOutput(
        value,
        timestamp: event.timestamp,
        buffer: band.outputBuffer,
      );
      if (buffered == null) continue;
      _emitter!.emit(
        TriggerEvent(
          sourcePortId: outputPortId(band.id),
          timestamp: event.timestamp,
          sequence: event.sequence,
          primaryValue: buffered,
        ),
      );
    }
  }

  @override
  void stop() {
    _emitter = null;
    _states.clear();
  }
}

double _linearToDbfs(double level) {
  if (level <= 0) return multibandEqMinimumDbfs;
  return (20 * math.log(level) / math.ln10)
      .clamp(multibandEqMinimumDbfs, multibandEqMaximumDbfs)
      .toDouble();
}

double _legacyHysteresisToDb({
  required double threshold,
  required double hysteresis,
}) {
  final openDbfs = _linearToDbfs(threshold);
  final closeDbfs = _linearToDbfs(math.max(0, threshold - hysteresis));
  return openDbfs - closeDbfs;
}

final class _BandState {
  double? _smoothed;
  Duration? _lastTimestamp;
  bool gateOpen = false;
  _BandOutputWindow? _outputWindow;

  double smooth(
    double raw,
    Duration timestamp, {
    required Duration attack,
    required Duration release,
  }) {
    final previous = _smoothed;
    final lastTimestamp = _lastTimestamp;
    _lastTimestamp = timestamp;
    if (previous == null ||
        lastTimestamp == null ||
        timestamp <= lastTimestamp) {
      return _smoothed = raw;
    }
    final timeConstant = raw > previous ? attack : release;
    if (timeConstant == Duration.zero) return _smoothed = raw;
    final elapsed = timestamp - lastTimestamp;
    final alpha =
        1 - math.exp(-elapsed.inMicroseconds / timeConstant.inMicroseconds);
    return _smoothed = previous + alpha * (raw - previous);
  }

  TriggerValue? bufferOutput(
    TriggerValue value, {
    required Duration timestamp,
    required Duration buffer,
  }) {
    if (buffer == Duration.zero) {
      _outputWindow = null;
      return value;
    }
    final window = _outputWindow;
    if (window == null || timestamp < window.startedAt) {
      _outputWindow = _BandOutputWindow(timestamp, value);
      return null;
    }
    if (timestamp - window.startedAt < buffer) {
      window.include(value);
      return null;
    }
    final output = window.value;
    _outputWindow = _BandOutputWindow(timestamp, value);
    return output;
  }
}

/// Accumulates the largest compatible trigger value within one band's output
/// window. Band ports are invariant while a runtime is active, so mismatched
/// values are impossible for a valid graph and intentionally retain the newer
/// value as a defensive fallback.
final class _BandOutputWindow {
  _BandOutputWindow(this.startedAt, this.value);

  final Duration startedAt;
  TriggerValue value;

  void include(TriggerValue next) {
    value = switch ((value, next)) {
      (
        TriggerLevelValue(value: final current),
        TriggerLevelValue(value: final nextValue),
      ) =>
        TriggerLevelValue(math.max(current, nextValue)),
      (
        TriggerGateValue(value: final current),
        TriggerGateValue(value: final nextValue),
      ) =>
        TriggerGateValue(current || nextValue),
      _ => next,
    };
  }
}

/// Computes a deterministic normalized combined magnitude for every requested
/// band.
///
/// A direct DFT is intentional here: macro audio frames are short, this keeps
/// the trigger dependency-free, and its bin selection is stable across hosts.
/// The selected bin magnitudes use root-sum-of-squares instead of an RMS
/// average. Consequently, a tone's dBFS level does not change merely because
/// the user widens the frequency band to include more empty bins.
List<double> _bandEnergies(
  TriggerMonoAudioValue audio,
  List<MultibandEqBandDefinition> bands,
) {
  final samples = audio.values;
  if (samples.length < 2) return List<double>.filled(bands.length, 0);
  final nyquist = audio.sampleRateHz / 2;
  final sumSquares = List<double>.filled(bands.length, 0);
  final sampleCount = samples.length;
  for (var bin = 0; bin <= sampleCount ~/ 2; bin++) {
    final frequency = bin * audio.sampleRateHz / sampleCount;
    var real = 0.0;
    var imaginary = 0.0;
    for (var sample = 0; sample < sampleCount; sample++) {
      final angle = 2 * math.pi * bin * sample / sampleCount;
      real += samples[sample] * math.cos(angle);
      imaginary -= samples[sample] * math.sin(angle);
    }
    final scale = (bin == 0 || frequency == nyquist) ? 1 : 2;
    final magnitude =
        scale * math.sqrt(real * real + imaginary * imaginary) / sampleCount;
    for (var index = 0; index < bands.length; index++) {
      final band = bands[index];
      if (frequency >= band.lowerFrequencyHz &&
          frequency <= band.upperFrequencyHz &&
          frequency <= nyquist) {
        sumSquares[index] += magnitude * magnitude;
      }
    }
  }
  return List<double>.generate(
    bands.length,
    (index) => math.sqrt(sumSquares[index]).clamp(0.0, 1.0).toDouble(),
    growable: false,
  );
}
