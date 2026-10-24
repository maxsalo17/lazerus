import 'package:lazerus_core/lazerus_core.dart';

/// A manually selected HSV colour source for a Scene Macro graph.
///
/// It is deliberately a source modifier: its compact editor control owns the
/// persisted HSV value and it has no upstream dependency. Other modules only
/// see the typed [TriggerHsvValue] emitted on its output port.
const String colorModifierKind = 'modifier.color';

final class ColorModifierConfiguration {
  ColorModifierConfiguration({
    this.hue = 0,
    this.saturation = 1,
    this.value = 1,
  }) {
    // Reuse the contract validation rather than duplicating domain ranges.
    TriggerHsvValue(hue: hue, saturation: saturation, value: value);
  }

  final double hue;
  final double saturation;
  final double value;

  Map<String, Object?> toNodeParameters() => <String, Object?>{
    'hue': hue,
    'saturation': saturation,
    'value': value,
  };

  factory ColorModifierConfiguration.fromNodeParameters(
    Map<String, Object?> parameters,
  ) => ColorModifierConfiguration(
    hue: _number(parameters, 'hue', defaultValue: 0),
    saturation: _number(parameters, 'saturation', defaultValue: 1),
    value: _number(parameters, 'value', defaultValue: 1),
  );

  TriggerHsvValue toValue() =>
      TriggerHsvValue(hue: hue, saturation: saturation, value: value);
}

final class ColorModifierFactory
    implements
        MacroModuleFactory,
        MacroNodePortContractProvider,
        MacroModifierDefinition {
  static const String outputPortSuffix = 'color';

  @override
  String get kind => colorModifierKind;

  @override
  String get displayName => 'Color';

  @override
  List<MacroPortDeclaration> get ports => <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: outputPortSuffix,
      direction: MacroPortDirection.output,
      type: MacroPortType.triggerHsv,
      displayIdentifier: 'color.hsv',
      displayName: 'HSV color',
    ),
  ];

  String outputPortId(MacroNode node) => '${node.id}.$outputPortSuffix';

  @override
  List<MacroPortDeclaration> portsFor(MacroNode node) => _portsForNode(node.id);

  static List<MacroPortDeclaration> portsForNode(String nodeId) =>
      _portsForNode(nodeId);

  static List<MacroPortDeclaration> _portsForNode(String nodeId) =>
      <MacroPortDeclaration>[
        MacroPortDeclaration(
          id: '$nodeId.$outputPortSuffix',
          direction: MacroPortDirection.output,
          type: MacroPortType.triggerHsv,
          displayIdentifier: 'color.hsv',
          displayName: 'HSV color',
        ),
      ];

  @override
  MacroModuleInstance create(MacroNode node) => _ColorModifierInstance(
    outputPortId: outputPortId(node),
    configuration: ColorModifierConfiguration.fromNodeParameters(
      node.parameters,
    ),
  );
}

final class _ColorModifierInstance implements MacroModuleInstance {
  _ColorModifierInstance({
    required this.outputPortId,
    required this.configuration,
  });

  final String outputPortId;
  final ColorModifierConfiguration configuration;
  var _started = false;

  @override
  void start(MacroRuntimeEventEmitter emitter) {
    if (_started) return;
    _started = true;
    emitter.emit(
      TriggerEvent(
        sourcePortId: outputPortId,
        timestamp: Duration.zero,
        sequence: 0,
        primaryValue: configuration.toValue(),
      ),
    );
  }

  @override
  void onInput(String inputPortId, TriggerEvent event) {}

  @override
  void stop() => _started = false;
}

double _number(
  Map<String, Object?> parameters,
  String key, {
  required double defaultValue,
}) {
  final raw = parameters[key] ?? defaultValue;
  if (raw is num) return raw.toDouble();
  throw FormatException('"$key" must be a number.');
}
