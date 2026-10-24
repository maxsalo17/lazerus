import 'package:lazerus_core/lazerus_core.dart';

/// Combines an HSV colour with a normalized level as the HSV Value component.
///
/// This is purposefully not a lighting brightness command. It produces a
/// colour signal which may be fanned out to any compatible module or target.
const String colorBrightnessCombineModifierKind =
    'modifier.color_brightness_combine';

final class ColorBrightnessCombineModifierFactory
    implements
        MacroModuleFactory,
        MacroNodePortContractProvider,
        MacroModifierDefinition {
  static const String colorInputSuffix = 'color';
  static const String brightnessInputSuffix = 'brightness';
  static const String outputPortSuffix = 'combined_color';

  @override
  String get kind => colorBrightnessCombineModifierKind;

  @override
  String get displayName => 'Color + brightness';

  @override
  List<MacroPortDeclaration> get ports => <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: colorInputSuffix,
      direction: MacroPortDirection.input,
      type: MacroPortType.triggerHsv,
      displayIdentifier: 'combine.color',
      displayName: 'Color',
    ),
    MacroPortDeclaration(
      id: brightnessInputSuffix,
      direction: MacroPortDirection.input,
      type: MacroPortType.triggerLevel,
      displayIdentifier: 'combine.brightness',
      displayName: 'HSV value',
    ),
    MacroPortDeclaration(
      id: outputPortSuffix,
      direction: MacroPortDirection.output,
      type: MacroPortType.triggerHsv,
      displayIdentifier: 'combine.color',
      displayName: 'Combined color',
    ),
  ];

  String colorInputPortId(MacroNode node) => '${node.id}.$colorInputSuffix';
  String brightnessInputPortId(MacroNode node) =>
      '${node.id}.$brightnessInputSuffix';
  String outputPortId(MacroNode node) => '${node.id}.$outputPortSuffix';

  @override
  List<MacroPortDeclaration> portsFor(MacroNode node) => _portsForNode(node.id);

  static List<MacroPortDeclaration> portsForNode(String nodeId) =>
      _portsForNode(nodeId);

  static List<MacroPortDeclaration> _portsForNode(String nodeId) =>
      <MacroPortDeclaration>[
        MacroPortDeclaration(
          id: '$nodeId.$colorInputSuffix',
          direction: MacroPortDirection.input,
          type: MacroPortType.triggerHsv,
          displayIdentifier: 'combine.color',
          displayName: 'Color',
        ),
        MacroPortDeclaration(
          id: '$nodeId.$brightnessInputSuffix',
          direction: MacroPortDirection.input,
          type: MacroPortType.triggerLevel,
          displayIdentifier: 'combine.brightness',
          displayName: 'HSV value',
        ),
        MacroPortDeclaration(
          id: '$nodeId.$outputPortSuffix',
          direction: MacroPortDirection.output,
          type: MacroPortType.triggerHsv,
          displayIdentifier: 'combine.color',
          displayName: 'Combined color',
        ),
      ];

  @override
  MacroModuleInstance create(MacroNode node) => _ColorBrightnessCombineInstance(
    colorInputPortId: colorInputPortId(node),
    brightnessInputPortId: brightnessInputPortId(node),
    outputPortId: outputPortId(node),
  );
}

final class _ColorBrightnessCombineInstance implements MacroModuleInstance {
  _ColorBrightnessCombineInstance({
    required this.colorInputPortId,
    required this.brightnessInputPortId,
    required this.outputPortId,
  });

  final String colorInputPortId;
  final String brightnessInputPortId;
  final String outputPortId;
  MacroRuntimeEventEmitter? _emitter;
  TriggerHsvValue? _color;
  double? _brightness;
  var _sequence = 0;

  @override
  void start(MacroRuntimeEventEmitter emitter) => _emitter = emitter;

  @override
  void onInput(String inputPortId, TriggerEvent event) {
    if (inputPortId == colorInputPortId &&
        event.primaryValue is TriggerHsvValue) {
      _color = event.primaryValue as TriggerHsvValue;
    } else if (inputPortId == brightnessInputPortId &&
        event.primaryValue is TriggerLevelValue) {
      _brightness = (event.primaryValue as TriggerLevelValue).value;
    } else {
      return;
    }
    final color = _color;
    final brightness = _brightness;
    final emitter = _emitter;
    if (color == null || brightness == null || emitter == null) return;
    emitter.emit(
      TriggerEvent(
        sourcePortId: outputPortId,
        timestamp: event.timestamp,
        sequence: _sequence++,
        primaryValue: TriggerHsvValue(
          hue: color.hue,
          saturation: color.saturation,
          value: brightness,
        ),
      ),
    );
  }

  @override
  void stop() {
    _emitter = null;
    _color = null;
    _brightness = null;
  }
}
