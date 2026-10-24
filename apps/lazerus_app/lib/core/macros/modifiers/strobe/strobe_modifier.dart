import 'dart:async';

import 'package:lazerus_core/lazerus_core.dart';

/// Emits one brightness flash for every rising gate edge.
///
/// The modifier deliberately has no knowledge of EQ, colour modules or device
/// protocols. It receives a typed gate and emits a typed normalized level, so
/// a graph can route the flash to a brightness target or to HSV Value through
/// the Color + brightness modifier.
const String strobeModifierKind = 'modifier.strobe';

final class StrobeModifierConfiguration {
  StrobeModifierConfiguration({
    this.flashDuration = const Duration(milliseconds: 100),
  }) : assert(flashDuration.inMicroseconds > 0);

  final Duration flashDuration;

  Map<String, Object?> toNodeParameters() => <String, Object?>{
    'flashDurationMilliseconds': flashDuration.inMilliseconds,
  };

  factory StrobeModifierConfiguration.fromNodeParameters(
    Map<String, Object?> parameters,
  ) {
    final rawMilliseconds =
        parameters['flashDurationMilliseconds'] ??
        const Duration(milliseconds: 100).inMilliseconds;
    if (rawMilliseconds is! num ||
        !rawMilliseconds.isFinite ||
        rawMilliseconds <= 0 ||
        rawMilliseconds != rawMilliseconds.roundToDouble()) {
      throw FormatException(
        '"flashDurationMilliseconds" must be a positive whole number.',
      );
    }
    return StrobeModifierConfiguration(
      flashDuration: Duration(milliseconds: rawMilliseconds.toInt()),
    );
  }
}

final class StrobeModifierFactory
    implements
        MacroModuleFactory,
        MacroNodePortContractProvider,
        MacroModifierDefinition {
  static const String gateInputSuffix = 'gate';
  static const String brightnessOutputSuffix = 'brightness';

  @override
  String get kind => strobeModifierKind;

  @override
  String get displayName => 'Strobe';

  @override
  List<MacroPortDeclaration> get ports => <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: gateInputSuffix,
      direction: MacroPortDirection.input,
      type: MacroPortType.triggerGate,
      displayIdentifier: 'strobe.gate',
      displayName: 'Activate',
    ),
    MacroPortDeclaration(
      id: brightnessOutputSuffix,
      direction: MacroPortDirection.output,
      type: MacroPortType.triggerLevel,
      displayIdentifier: 'strobe.brightness',
      displayName: 'Flash brightness',
    ),
  ];

  String gateInputPortId(MacroNode node) => '${node.id}.$gateInputSuffix';
  String brightnessOutputPortId(MacroNode node) =>
      '${node.id}.$brightnessOutputSuffix';

  @override
  List<MacroPortDeclaration> portsFor(MacroNode node) => _portsForNode(node.id);

  static List<MacroPortDeclaration> portsForNode(String nodeId) =>
      _portsForNode(nodeId);

  static List<MacroPortDeclaration> _portsForNode(String nodeId) =>
      <MacroPortDeclaration>[
        MacroPortDeclaration(
          id: '$nodeId.$gateInputSuffix',
          direction: MacroPortDirection.input,
          type: MacroPortType.triggerGate,
          displayIdentifier: 'strobe.gate',
          displayName: 'Activate',
        ),
        MacroPortDeclaration(
          id: '$nodeId.$brightnessOutputSuffix',
          direction: MacroPortDirection.output,
          type: MacroPortType.triggerLevel,
          displayIdentifier: 'strobe.brightness',
          displayName: 'Flash brightness',
        ),
      ];

  @override
  MacroModuleInstance create(MacroNode node) => _StrobeModifierInstance(
    gateInputPortId: gateInputPortId(node),
    brightnessOutputPortId: brightnessOutputPortId(node),
    configuration: StrobeModifierConfiguration.fromNodeParameters(
      node.parameters,
    ),
  );
}

final class _StrobeModifierInstance implements MacroModuleInstance {
  _StrobeModifierInstance({
    required this.gateInputPortId,
    required this.brightnessOutputPortId,
    required this.configuration,
  });

  final String gateInputPortId;
  final String brightnessOutputPortId;
  final StrobeModifierConfiguration configuration;
  MacroRuntimeEventEmitter? _emitter;
  Timer? _flashTimer;
  var _gateActive = false;
  var _isFlashing = false;
  var _sequence = 0;

  @override
  void start(MacroRuntimeEventEmitter emitter) => _emitter = emitter;

  @override
  void onInput(String inputPortId, TriggerEvent event) {
    if (inputPortId != gateInputPortId ||
        event.primaryValue is! TriggerGateValue) {
      return;
    }
    final active = (event.primaryValue as TriggerGateValue).value;
    if (!active) {
      final wasFlashing = _isFlashing;
      _gateActive = false;
      _isFlashing = false;
      _flashTimer?.cancel();
      _flashTimer = null;
      if (wasFlashing) {
        _emit(0, event.timestamp);
      }
      return;
    }
    if (_gateActive) return;

    _gateActive = true;
    _isFlashing = true;
    _emit(1, event.timestamp);
    _flashTimer = Timer(configuration.flashDuration, () {
      _flashTimer = null;
      if (!_gateActive || !_isFlashing) return;
      _isFlashing = false;
      _emit(0, event.timestamp + configuration.flashDuration);
    });
  }

  void _emit(double value, Duration timestamp) {
    final emitter = _emitter;
    if (emitter == null) return;
    emitter.emit(
      TriggerEvent(
        sourcePortId: brightnessOutputPortId,
        timestamp: timestamp,
        sequence: _sequence++,
        primaryValue: TriggerLevelValue(value),
      ),
    );
  }

  @override
  void stop() {
    _flashTimer?.cancel();
    _flashTimer = null;
    _emitter = null;
    _gateActive = false;
    _isFlashing = false;
  }
}
