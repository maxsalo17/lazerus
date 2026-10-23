import 'dart:typed_data';

import '../contracts/transport.dart';

/// An RGB color represented by 8-bit channels.
class RgbColor {
  RgbColor(this.red, this.green, this.blue) {
    _requireChannel(red, 'red');
    _requireChannel(green, 'green');
    _requireChannel(blue, 'blue');
  }

  final int red;
  final int green;
  final int blue;

  @override
  bool operator ==(Object other) {
    return other is RgbColor &&
        other.red == red &&
        other.green == green &&
        other.blue == blue;
  }

  @override
  int get hashCode => Object.hash(red, green, blue);

  static void _requireChannel(int value, String name) {
    if (value < 0 || value > 255) {
      throw RangeError.range(value, 0, 255, name);
    }
  }
}

/// A partial state resolved by the lighting domain before transport encoding.
class DesiredLightingState {
  DesiredLightingState({this.power, this.color, this.brightness}) {
    if (brightness != null &&
        (!brightness!.isFinite || brightness! < 0 || brightness! > 1)) {
      throw ArgumentError.value(
        brightness,
        'brightness',
        'Must be between 0 and 1.',
      );
    }
  }

  final bool? power;
  final RgbColor? color;

  /// Normalized brightness in the inclusive range 0 to 1.
  final double? brightness;

  bool get isEmpty => power == null && color == null && brightness == null;
}

/// A reusable device-native effect reference.
class DeviceEffect {
  DeviceEffect({
    required this.id,
    required this.displayName,
    Map<String, String> parameters = const <String, String>{},
  }) : parameters = Map.unmodifiable(parameters);

  final String id;
  final String displayName;
  final Map<String, String> parameters;
}

/// Shared commands that a protocol-aware device session can receive.
abstract class LightingCommand {
  const LightingCommand();
}

final class SetPower extends LightingCommand {
  const SetPower(this.enabled);

  final bool enabled;
}

final class SetColor extends LightingCommand {
  const SetColor(this.color);

  final RgbColor color;
}

final class SetBrightness extends LightingCommand {
  SetBrightness(this.value) {
    if (!value.isFinite || value < 0 || value > 1) {
      throw ArgumentError.value(value, 'value', 'Must be between 0 and 1.');
    }
  }

  /// Normalized brightness in the inclusive range 0 to 1.
  final double value;
}

final class SetNativeEffect extends LightingCommand {
  const SetNativeEffect(this.effect);

  final DeviceEffect effect;
}

final class ApplyLightingState extends LightingCommand {
  ApplyLightingState(this.state) {
    if (state.isEmpty) {
      throw ArgumentError.value(
        state,
        'state',
        'Must contain at least one value.',
      );
    }
  }

  final DesiredLightingState state;
}

enum LightingFeature {
  power,
  rgb,
  rgbw,
  cct,
  brightness,
  nativeEffects,
  effectSpeed,
  addressablePixels,
  segments,
  notifications,
}

/// Evidence level for a capability of this protocol/device combination.
enum CapabilityAvailability { unsupported, inferred, verified }

class NumericRange {
  const NumericRange(this.minimum, this.maximum) : assert(minimum <= maximum);

  final double minimum;
  final double maximum;

  bool contains(double value) => value >= minimum && value <= maximum;
}

class FeatureCapability {
  FeatureCapability({
    required this.availability,
    this.range,
    Set<String> supportedValues = const <String>{},
    Map<String, String> metadata = const <String, String>{},
  }) : supportedValues = Set.unmodifiable(supportedValues),
       metadata = Map.unmodifiable(metadata);

  final CapabilityAvailability availability;
  final NumericRange? range;
  final Set<String> supportedValues;
  final Map<String, String> metadata;

  bool isOperational({bool allowInferred = false}) {
    return availability == CapabilityAvailability.verified ||
        (allowInferred && availability == CapabilityAvailability.inferred);
  }
}

/// A typed, namespaced extension without changing common lighting controls.
class ProtocolCapability {
  ProtocolCapability({
    required this.id,
    required this.availability,
    Map<String, String> metadata = const <String, String>{},
  }) : metadata = Map.unmodifiable(metadata);

  final String id;
  final CapabilityAvailability availability;
  final Map<String, String> metadata;
}

/// Device behavior declared by a selected protocol adapter.
class DeviceCapabilities {
  DeviceCapabilities({
    Map<LightingFeature, FeatureCapability> features =
        const <LightingFeature, FeatureCapability>{},
    Map<String, ProtocolCapability> protocolExtensions =
        const <String, ProtocolCapability>{},
    this.maximumUpdateRateHz,
  }) : features = Map.unmodifiable(features),
       protocolExtensions = Map.unmodifiable(protocolExtensions);

  final Map<LightingFeature, FeatureCapability> features;
  final Map<String, ProtocolCapability> protocolExtensions;
  final double? maximumUpdateRateHz;

  FeatureCapability capabilityFor(LightingFeature feature) {
    return features[feature] ??
        FeatureCapability(availability: CapabilityAvailability.unsupported);
  }

  bool supports(LightingFeature feature, {bool allowInferred = false}) {
    return capabilityFor(feature).isOperational(allowInferred: allowInferred);
  }
}

enum DeviceObservationKind { state, notification, rawProtocolMessage }

/// Information reported by a device or its protocol, if supported.
class DeviceObservation {
  DeviceObservation({
    required this.kind,
    DateTime? occurredAt,
    this.state,
    Uint8List? rawData,
    this.detail,
  }) : occurredAt = occurredAt ?? DateTime.now().toUtc(),
       rawData = rawData == null ? null : Uint8List.fromList(rawData);

  final DeviceObservationKind kind;
  final DateTime occurredAt;
  final DesiredLightingState? state;
  final Uint8List? rawData;
  final String? detail;
}

enum CommandOutcome {
  rejected,
  queued,
  transmitted,
  acknowledged,
  observed,
  failed,
  timedOut,
  superseded,
  dropped,
}

/// The status of a lighting command at a known boundary in the runtime.
class CommandResult {
  CommandResult({
    required this.command,
    required this.outcome,
    Iterable<TransportReceipt> receipts = const <TransportReceipt>[],
    this.detail,
    this.error,
  }) : receipts = List.unmodifiable(receipts);

  final LightingCommand command;
  final CommandOutcome outcome;
  final List<TransportReceipt> receipts;
  final String? detail;
  final Object? error;

  factory CommandResult.rejected(LightingCommand command, String detail) {
    return CommandResult(
      command: command,
      outcome: CommandOutcome.rejected,
      detail: detail,
    );
  }

  factory CommandResult.failed(
    LightingCommand command,
    Object error, {
    String? detail,
    Iterable<TransportReceipt> receipts = const <TransportReceipt>[],
  }) {
    return CommandResult(
      command: command,
      outcome: CommandOutcome.failed,
      detail: detail,
      error: error,
      receipts: receipts,
    );
  }
}
