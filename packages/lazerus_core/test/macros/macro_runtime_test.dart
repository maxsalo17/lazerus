import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'routes typed events and emits a transport-free lighting intent',
    () async {
      final sourceFactory = _SourceFactory();
      final inputFactory = _InputFactory();
      final registry = MacroModuleRegistry()
        ..register(sourceFactory)
        ..register(inputFactory);
      final runtime = MacroRuntime(
        graph: MacroGraph(
          id: 'macro',
          name: 'Level route',
          nodes: <MacroNode>[
            MacroNode(
              id: 'source',
              kind: sourceFactory.kind,
              ports: sourceFactory.ports,
            ),
            MacroNode(
              id: 'input',
              kind: inputFactory.kind,
              ports: inputFactory.ports,
            ),
          ],
          edges: <MacroEdge>[
            MacroEdge(id: 'edge', fromPortId: 'out', toPortId: 'in'),
          ],
          targetBindings: <MacroTargetBinding>[
            MacroTargetBinding(
              id: 'brightness',
              sourcePortId: 'out',
              targetKind: MacroTargetKind.device,
              targetId: 'device',
              parameter: MacroTargetParameter.brightness,
            ),
          ],
        ),
        registry: registry,
      );
      final intents = <MacroLightingIntent>[];
      final events = <TriggerEvent>[];
      final subscription = runtime.lightingIntents.listen(intents.add);
      final eventSubscription = runtime.events.listen(events.add);

      expect(runtime.validate(), isEmpty);
      runtime.prepare();
      runtime.start();
      sourceFactory.instance!.emit(
        TriggerEvent(
          sourcePortId: 'out',
          timestamp: const Duration(milliseconds: 10),
          sequence: 1,
          primaryValue: TriggerLevelValue(0.6),
        ),
      );

      expect(inputFactory.instance!.lastInputPortId, 'in');
      expect(intents.single.value, isA<TriggerLevelValue>());
      expect((intents.single.value as TriggerLevelValue).value, 0.6);
      expect(intents.single.targetId, 'device');
      expect(events, hasLength(1));
      expect(events.single.sourcePortId, 'out');
      expect(events.single.primaryValue, isA<TriggerLevelValue>());

      runtime.stop();
      await subscription.cancel();
      await eventSubscription.cancel();
      await runtime.dispose();
    },
  );

  test('moves an incompatible registered graph to error lifecycle', () async {
    final registry = MacroModuleRegistry()..register(_SourceFactory());
    final runtime = MacroRuntime(
      graph: MacroGraph(
        id: 'invalid',
        name: 'Invalid',
        nodes: <MacroNode>[
          MacroNode(
            id: 'source',
            kind: 'test.source',
            ports: <MacroPortDeclaration>[
              _output('out', MacroPortType.triggerGate),
            ],
          ),
        ],
        edges: const <MacroEdge>[],
      ),
      registry: registry,
    );

    final issues = runtime.validate();

    expect(runtime.lifecycle, MacroRuntimeLifecycle.error);
    expect(
      issues.map((issue) => issue.code),
      contains(MacroGraphValidationCode.nodePortsDoNotMatchContract),
    );
    await runtime.dispose();
  });

  test('accepts a changed human-readable port label', () async {
    final registry = MacroModuleRegistry()..register(_SourceFactory());
    final runtime = MacroRuntime(
      graph: MacroGraph(
        id: 'legacy-label',
        name: 'Legacy label',
        nodes: <MacroNode>[
          MacroNode(
            id: 'source',
            kind: 'test.source',
            ports: <MacroPortDeclaration>[
              MacroPortDeclaration(
                id: 'out',
                direction: MacroPortDirection.output,
                type: MacroPortType.triggerLevel,
                displayIdentifier: 'out',
                displayName: 'Old localized label',
              ),
            ],
          ),
        ],
        edges: const <MacroEdge>[],
      ),
      registry: registry,
    );

    expect(runtime.validate(), isEmpty);
    await runtime.dispose();
  });

  test(
    'validates a configured node against its dynamic port contract',
    () async {
      final factory = _EqualizerFactory();
      final registry = MacroModuleRegistry()..register(factory);
      final node = MacroNode(
        id: 'equalizer',
        kind: factory.kind,
        parameters: const <String, Object?>{'bandCount': 2},
        ports: <MacroPortDeclaration>[
          _output('band-1', MacroPortType.triggerLevel),
          _output('band-2', MacroPortType.triggerLevel),
        ],
      );

      expect(
        registry.portsFor(node)!.map((port) => port.id),
        orderedEquals(<String>['band-1', 'band-2']),
      );
      final runtime = MacroRuntime(
        graph: MacroGraph(
          id: 'equalizer-macro',
          name: 'Equalizer',
          nodes: <MacroNode>[node],
          edges: const <MacroEdge>[],
        ),
        registry: registry,
      );
      expect(runtime.validate(), isEmpty);

      final invalidRuntime = MacroRuntime(
        graph: MacroGraph(
          id: 'invalid-equalizer-macro',
          name: 'Equalizer',
          nodes: <MacroNode>[
            MacroNode(
              id: 'equalizer',
              kind: factory.kind,
              parameters: const <String, Object?>{'bandCount': 2},
              ports: <MacroPortDeclaration>[
                _output('band-1', MacroPortType.triggerLevel),
              ],
            ),
          ],
          edges: const <MacroEdge>[],
        ),
        registry: registry,
      );

      expect(
        invalidRuntime.validate().map((issue) => issue.code),
        contains(MacroGraphValidationCode.nodePortsDoNotMatchContract),
      );
      await runtime.dispose();
      await invalidRuntime.dispose();
    },
  );
}

final class _EqualizerFactory
    implements MacroModuleFactory, MacroNodePortContractProvider {
  @override
  String get kind => 'test.equalizer';

  @override
  List<MacroPortDeclaration> get ports => const <MacroPortDeclaration>[];

  @override
  List<MacroPortDeclaration> portsFor(MacroNode node) {
    final bandCount = node.parameters['bandCount'] as int;
    return <MacroPortDeclaration>[
      for (var band = 1; band <= bandCount; band++)
        _output('band-$band', MacroPortType.triggerLevel),
    ];
  }

  @override
  MacroModuleInstance create(MacroNode node) => _InputInstance();
}

final class _SourceFactory implements MacroModuleFactory {
  _SourceInstance? instance;

  @override
  String get kind => 'test.source';

  @override
  List<MacroPortDeclaration> get ports => <MacroPortDeclaration>[
    _output('out', MacroPortType.triggerLevel),
  ];

  @override
  MacroModuleInstance create(MacroNode node) => instance = _SourceInstance();
}

final class _InputFactory implements MacroModuleFactory {
  _InputInstance? instance;

  @override
  String get kind => 'test.input';

  @override
  List<MacroPortDeclaration> get ports => <MacroPortDeclaration>[
    _input('in', MacroPortType.triggerLevel),
  ];

  @override
  MacroModuleInstance create(MacroNode node) => instance = _InputInstance();
}

final class _SourceInstance implements MacroModuleInstance {
  MacroRuntimeEventEmitter? _emitter;

  @override
  void onInput(String inputPortId, TriggerEvent event) {}

  @override
  void start(MacroRuntimeEventEmitter emitter) => _emitter = emitter;

  @override
  void stop() => _emitter = null;

  void emit(TriggerEvent event) => _emitter!.emit(event);
}

final class _InputInstance implements MacroModuleInstance {
  String? lastInputPortId;

  @override
  void onInput(String inputPortId, TriggerEvent event) {
    lastInputPortId = inputPortId;
  }

  @override
  void start(MacroRuntimeEventEmitter emitter) {}

  @override
  void stop() {}
}

MacroPortDeclaration _input(String id, MacroPortType type) =>
    MacroPortDeclaration(
      id: id,
      direction: MacroPortDirection.input,
      type: type,
      displayIdentifier: id,
    );

MacroPortDeclaration _output(String id, MacroPortType type) =>
    MacroPortDeclaration(
      id: id,
      direction: MacroPortDirection.output,
      type: type,
      displayIdentifier: id,
    );
