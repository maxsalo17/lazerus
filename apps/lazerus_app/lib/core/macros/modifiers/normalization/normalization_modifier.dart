import 'dart:collection';
import 'dart:math' as math;

import 'package:lazerus_core/lazerus_core.dart';

/// Stateful audio normalization over the latest configured time window.
///
/// The modifier owns no capture session and retains only one dBFS value per
/// transient input frame. This lets it normalize audio dynamics without
/// persisting PCM or depending on the microphone implementation.
const String normalizationModifierKind = 'modifier.normalization';

const double normalizationMinimumDbfs = -72;
const double normalizationMaximumDbfs = 0;
const Duration normalizationDefaultWindow = Duration(seconds: 5);
const Duration normalizationMaximumWindow = Duration(minutes: 10);

enum NormalizationOutputMode {
  pcm,
  value;

  static NormalizationOutputMode parse(Object? raw) {
    if (raw is! String) {
      throw FormatException('"outputMode" must be "pcm" or "value".');
    }
    for (final mode in values) {
      if (mode.name == raw) return mode;
    }
    throw FormatException('"outputMode" must be "pcm" or "value".');
  }
}

/// Immutable, serializable settings for one normalization node.
final class NormalizationModifierConfiguration {
  NormalizationModifierConfiguration({
    this.outputMode = NormalizationOutputMode.pcm,
    this.windowDuration = normalizationDefaultWindow,
  }) {
    _validateWindowDuration(windowDuration);
  }

  final NormalizationOutputMode outputMode;
  final Duration windowDuration;

  Map<String, Object?> toNodeParameters() => <String, Object?>{
    'outputMode': outputMode.name,
    'windowDurationMilliseconds': windowDuration.inMilliseconds,
  };

  factory NormalizationModifierConfiguration.fromNodeParameters(
    Map<String, Object?> parameters,
  ) {
    final rawMode =
        parameters['outputMode'] ?? NormalizationOutputMode.pcm.name;
    final rawWindow =
        parameters['windowDurationMilliseconds'] ??
        normalizationDefaultWindow.inMilliseconds;
    if (rawWindow is! num ||
        !rawWindow.isFinite ||
        rawWindow != rawWindow.roundToDouble()) {
      throw FormatException(
        '"windowDurationMilliseconds" must be a positive whole number.',
      );
    }
    try {
      return NormalizationModifierConfiguration(
        outputMode: NormalizationOutputMode.parse(rawMode),
        windowDuration: Duration(milliseconds: rawWindow.toInt()),
      );
    } on ArgumentError catch (error) {
      throw FormatException(error.message);
    }
  }
}

void _validateWindowDuration(Duration value) {
  if (value.inMilliseconds <= 0 || value > normalizationMaximumWindow) {
    throw ArgumentError.value(
      value,
      'windowDuration',
      'Must be greater than zero and no longer than '
          '${normalizationMaximumWindow.inMinutes} minutes.',
    );
  }
}

/// Provides the mode-specific typed ports and creates isolated modifier state.
final class NormalizationModifierFactory
    implements
        MacroModuleFactory,
        MacroNodePortContractProvider,
        MacroModifierDefinition {
  static const String audioInputSuffix = 'audio';
  static const String normalizedOutputSuffix = 'normalized';

  @override
  String get kind => normalizationModifierKind;

  @override
  String get displayName => 'Normalization';

  @override
  List<MacroPortDeclaration> get ports =>
      _portsForNode('normalization', NormalizationOutputMode.pcm);

  String audioInputPortId(MacroNode node) => '${node.id}.$audioInputSuffix';
  String normalizedOutputPortId(MacroNode node) =>
      '${node.id}.$normalizedOutputSuffix';

  @override
  List<MacroPortDeclaration> portsFor(MacroNode node) {
    final configuration = NormalizationModifierConfiguration.fromNodeParameters(
      node.parameters,
    );
    return _portsForNode(node.id, configuration.outputMode);
  }

  static List<MacroPortDeclaration> portsForNode(
    String nodeId,
    NormalizationOutputMode outputMode,
  ) => _portsForNode(nodeId, outputMode);

  static List<MacroPortDeclaration> _portsForNode(
    String nodeId,
    NormalizationOutputMode outputMode,
  ) => <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: '$nodeId.$audioInputSuffix',
      direction: MacroPortDirection.input,
      type: MacroPortType.triggerMonoAudio,
      displayIdentifier: 'normalization.audio',
      displayName: 'Audio',
    ),
    MacroPortDeclaration(
      id: '$nodeId.$normalizedOutputSuffix',
      direction: MacroPortDirection.output,
      type: outputMode == NormalizationOutputMode.pcm
          ? MacroPortType.triggerMonoAudio
          : MacroPortType.triggerLevel,
      displayIdentifier: 'normalization.output',
      displayName: outputMode == NormalizationOutputMode.pcm
          ? 'Normalized audio'
          : 'Normalized value',
    ),
  ];

  @override
  MacroModuleInstance create(MacroNode node) {
    final configuration = NormalizationModifierConfiguration.fromNodeParameters(
      node.parameters,
    );
    return _NormalizationModifierInstance(
      audioInputPortId: audioInputPortId(node),
      normalizedOutputPortId: normalizedOutputPortId(node),
      configuration: configuration,
    );
  }
}

final class _NormalizationModifierInstance implements MacroModuleInstance {
  _NormalizationModifierInstance({
    required this.audioInputPortId,
    required this.normalizedOutputPortId,
    required this.configuration,
  });

  static const double _rangeEpsilonDb = 0.000001;

  final String audioInputPortId;
  final String normalizedOutputPortId;
  final NormalizationModifierConfiguration configuration;
  final ListQueue<_FrameLevel> _history = ListQueue<_FrameLevel>();
  MacroRuntimeEventEmitter? _emitter;
  Duration? _latestTimestamp;

  @override
  void start(MacroRuntimeEventEmitter emitter) => _emitter = emitter;

  @override
  void onInput(String inputPortId, TriggerEvent event) {
    if (inputPortId != audioInputPortId ||
        event.primaryValue is! TriggerMonoAudioValue) {
      return;
    }
    final emitter = _emitter;
    if (emitter == null) return;
    final audio = event.primaryValue as TriggerMonoAudioValue;
    if (audio.values.isEmpty) return;

    _resetForOutOfOrderTimestamp(event.timestamp);
    final rms = _rms(audio.values);
    final currentDb = _dbfsForRms(rms);
    _evictExpired(event.timestamp);
    _history.addLast(_FrameLevel(event.timestamp, currentDb));
    _latestTimestamp = event.timestamp;

    final range = _range();
    final hasDynamics = range.maximum - range.minimum > _rangeEpsilonDb;
    final normalized = hasDynamics
        ? ((currentDb - range.minimum) / (range.maximum - range.minimum))
              .clamp(0.0, 1.0)
              .toDouble()
        : 0.0;

    final TriggerValue output;
    switch (configuration.outputMode) {
      case NormalizationOutputMode.value:
        output = TriggerLevelValue(normalized);
      case NormalizationOutputMode.pcm:
        output = TriggerMonoAudioValue(
          sampleRateHz: audio.sampleRateHz,
          values: _normalizedPcm(
            audio.values,
            rms: rms,
            normalized: normalized,
            hasDynamics: hasDynamics,
          ),
        );
    }
    emitter.emit(
      TriggerEvent(
        sourcePortId: normalizedOutputPortId,
        timestamp: event.timestamp,
        sequence: event.sequence,
        primaryValue: output,
      ),
    );
  }

  /// A modifier receives one routed source, whose timestamps are monotonic.
  /// Resetting on malformed/replayed time avoids letting future data influence
  /// a historical event while keeping state bounded and deterministic.
  void _resetForOutOfOrderTimestamp(Duration timestamp) {
    final latest = _latestTimestamp;
    if (latest != null && timestamp < latest) {
      _history.clear();
    }
  }

  void _evictExpired(Duration timestamp) {
    final cutoff = timestamp > configuration.windowDuration
        ? timestamp - configuration.windowDuration
        : Duration.zero;
    while (_history.isNotEmpty && _history.first.timestamp < cutoff) {
      _history.removeFirst();
    }
  }

  _DbRange _range() {
    var minimum = normalizationMaximumDbfs;
    var maximum = normalizationMinimumDbfs;
    for (final frame in _history) {
      minimum = math.min(minimum, frame.dbfs);
      maximum = math.max(maximum, frame.dbfs);
    }
    return _DbRange(minimum, maximum);
  }

  Iterable<double> _normalizedPcm(
    List<double> samples, {
    required double rms,
    required double normalized,
    required bool hasDynamics,
  }) {
    if (rms <= 0) {
      return List<double>.filled(samples.length, 0, growable: false);
    }
    if (!hasDynamics) {
      return samples
          .map((sample) => sample.clamp(-1.0, 1.0).toDouble())
          .toList(growable: false);
    }
    final targetDb =
        normalizationMinimumDbfs +
        (normalizationMaximumDbfs - normalizationMinimumDbfs) * normalized;
    final targetRms = math.pow(10, targetDb / 20).toDouble();
    final gain = targetRms / rms;
    return samples
        .map((sample) => (sample * gain).clamp(-1.0, 1.0).toDouble())
        .toList(growable: false);
  }

  @override
  void stop() {
    _emitter = null;
    _history.clear();
    _latestTimestamp = null;
  }
}

double _rms(List<double> samples) {
  var sumSquares = 0.0;
  for (final sample in samples) {
    sumSquares += sample * sample;
  }
  return math.sqrt(sumSquares / samples.length);
}

double _dbfsForRms(double rms) {
  if (rms <= 0) return normalizationMinimumDbfs;
  return (20 * math.log(rms) / math.ln10)
      .clamp(normalizationMinimumDbfs, normalizationMaximumDbfs)
      .toDouble();
}

final class _FrameLevel {
  const _FrameLevel(this.timestamp, this.dbfs);

  final Duration timestamp;
  final double dbfs;
}

final class _DbRange {
  const _DbRange(this.minimum, this.maximum);

  final double minimum;
  final double maximum;
}
