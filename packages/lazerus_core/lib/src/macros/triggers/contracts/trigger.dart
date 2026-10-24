import '../../contracts/macro_port.dart';

/// A value that can be carried by a trigger event.
sealed class TriggerValue {
  const TriggerValue();

  MacroPortType get portType;
}

/// A generic immutable numeric array used by [MacroPortType.triggerArray].
class TriggerArrayValue extends TriggerValue {
  TriggerArrayValue(Iterable<double> values)
    : values = List<double>.unmodifiable(values) {
    if (this.values.any((value) => !value.isFinite)) {
      throw ArgumentError.value(values, 'values', 'Values must be finite.');
    }
  }

  final List<double> values;

  @override
  MacroPortType get portType => MacroPortType.triggerArray;
}

/// Immutable mono PCM samples with their source sample rate.
///
/// This is intentionally a distinct value rather than a generic array with an
/// optional field: an audio port always has an explicit sample rate.
final class TriggerMonoAudioValue extends TriggerArrayValue {
  TriggerMonoAudioValue({
    required Iterable<double> values,
    required this.sampleRateHz,
  }) : super(values) {
    if (sampleRateHz <= 0) {
      throw ArgumentError.value(
        sampleRateHz,
        'sampleRateHz',
        'Must be greater than zero.',
      );
    }
  }

  final int sampleRateHz;

  @override
  MacroPortType get portType => MacroPortType.triggerMonoAudio;
}

/// A binary trigger value.
final class TriggerGateValue extends TriggerValue {
  const TriggerGateValue(this.value);

  final bool value;

  @override
  MacroPortType get portType => MacroPortType.triggerGate;
}

/// A normalized continuous trigger value.
final class TriggerLevelValue extends TriggerValue {
  TriggerLevelValue(this.value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value', 'Must be in the range 0..1.');
    }
  }

  final double value;

  @override
  MacroPortType get portType => MacroPortType.triggerLevel;
}

/// A protocol-neutral HSV colour value carried by [MacroPortType.triggerHsv].
///
/// [hue] is in the inclusive 0..360 degree domain. [saturation] and [value]
/// use the inclusive normalized domain. Keeping HSV in the macro contract
/// lets a graph combine a colour source with a reactive level without making
/// the graph depend on any lighting-controller wire encoding.
final class TriggerHsvValue extends TriggerValue {
  TriggerHsvValue({
    required this.hue,
    required this.saturation,
    required this.value,
  }) {
    if (!hue.isFinite || hue < 0 || hue > 360) {
      throw ArgumentError.value(hue, 'hue', 'Must be in the range 0..360.');
    }
    if (!saturation.isFinite || saturation < 0 || saturation > 1) {
      throw ArgumentError.value(
        saturation,
        'saturation',
        'Must be in the range 0..1.',
      );
    }
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value', 'Must be in the range 0..1.');
    }
  }

  final double hue;
  final double saturation;
  final double value;

  @override
  MacroPortType get portType => MacroPortType.triggerHsv;
}

/// Transient data emitted by a running trigger or modifier.
///
/// Events are never part of persisted macro JSON. [timestamp] is expressed on
/// the macro runtime's monotonic clock and [sequence] is monotonic per source
/// port.
final class TriggerEvent {
  TriggerEvent({
    required this.sourcePortId,
    required this.timestamp,
    required this.sequence,
    required this.primaryValue,
    this.secondaryValue,
  }) {
    _requireId(sourcePortId, 'sourcePortId');
    if (timestamp.isNegative) {
      throw ArgumentError.value(
        timestamp,
        'timestamp',
        'Must not be negative.',
      );
    }
    if (sequence < 0) {
      throw ArgumentError.value(sequence, 'sequence', 'Must not be negative.');
    }
  }

  final String sourcePortId;
  final Duration timestamp;
  final int sequence;
  final TriggerValue primaryValue;
  final TriggerValue? secondaryValue;
}

/// Public declaration implemented by a concrete trigger module.
///
/// Implementations depend only on this contract and graph contracts; they must
/// not import other trigger implementations.
abstract interface class MacroTriggerDefinition {
  String get kind;
  String get displayName;
  List<MacroPortDeclaration> get ports;
}

void _requireId(String value, String name) {
  if (value.trim().isEmpty) {
    throw ArgumentError.value(value, name, 'Must not be blank.');
  }
}
