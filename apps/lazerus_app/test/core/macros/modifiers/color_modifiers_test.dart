import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/modifiers/color/color_modifier.dart';
import 'package:lazerus_app/core/macros/modifiers/color_brightness_combine/color_brightness_combine_modifier.dart';
import 'package:lazerus_app/core/macros/registry/macro_module_registry.dart';
import 'package:lazerus_app/core/macros/sinks/lighting_target_sink.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test('color source emits its configured typed HSV value', () {
    final factory = ColorModifierFactory();
    final node = MacroNode(
      id: 'color',
      kind: colorModifierKind,
      ports: ColorModifierFactory.portsForNode('color'),
      parameters: ColorModifierConfiguration(hue: 32).toNodeParameters(),
    );
    final emitter = _CapturingEmitter();

    factory.create(node).start(emitter);

    expect(emitter.events, hasLength(1));
    final value = emitter.events.single.primaryValue as TriggerHsvValue;
    expect(value.hue, 32);
    expect(value.saturation, 1);
    expect(value.value, 1);
  });

  test('color and level inputs compose a typed HSV output', () {
    final factory = ColorBrightnessCombineModifierFactory();
    final node = MacroNode(
      id: 'combine',
      kind: colorBrightnessCombineModifierKind,
      ports: ColorBrightnessCombineModifierFactory.portsForNode('combine'),
    );
    final instance = factory.create(node);
    final emitter = _CapturingEmitter();
    instance.start(emitter);

    instance.onInput(
      'combine.color',
      TriggerEvent(
        sourcePortId: 'source.color',
        timestamp: const Duration(milliseconds: 1),
        sequence: 1,
        primaryValue: TriggerHsvValue(hue: 280, saturation: 0.8, value: 1),
      ),
    );
    instance.onInput(
      'combine.brightness',
      TriggerEvent(
        sourcePortId: 'source.level',
        timestamp: const Duration(milliseconds: 2),
        sequence: 2,
        primaryValue: TriggerLevelValue(0.35),
      ),
    );

    final value = emitter.events.single.primaryValue as TriggerHsvValue;
    expect(value.hue, 280);
    expect(value.saturation, 0.8);
    expect(value.value, 0.35);
  });

  test('registry resolves the input-only target sink contract', () {
    final configuration = LightingTargetNodeConfiguration(
      targetKind: MacroTargetKind.device,
      targetId: 'device-1',
      parameters: <MacroTargetParameter>[
        MacroTargetParameter.brightness,
        MacroTargetParameter.color,
      ],
    );
    final node = MacroNode(
      id: 'target',
      kind: lightingTargetSinkKind,
      ports: configuration.portsForNode('target'),
      parameters: configuration.toNodeParameters(),
    );

    final ports = createMacroModuleRegistry().portsFor(node)!;

    expect(ports, hasLength(2));
    expect(
      ports.every((port) => port.direction == MacroPortDirection.input),
      isTrue,
    );
    expect(
      ports.map((port) => port.type),
      orderedEquals(<MacroPortType>[
        MacroPortType.triggerLevel,
        MacroPortType.triggerHsv,
      ]),
    );
  });
}

final class _CapturingEmitter implements MacroRuntimeEventEmitter {
  final List<TriggerEvent> events = <TriggerEvent>[];

  @override
  void emit(TriggerEvent event) => events.add(event);
}
