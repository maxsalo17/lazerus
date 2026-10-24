import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  group('trigger contracts', () {
    test('keeps generic arrays distinct from mono audio values', () {
      final generic = TriggerArrayValue(<double>[0.1, 0.2]);
      final audio = TriggerMonoAudioValue(
        values: <double>[0.1, -0.2],
        sampleRateHz: 48000,
      );

      expect(generic.portType, MacroPortType.triggerArray);
      expect(audio.portType, MacroPortType.triggerMonoAudio);
      expect(audio.sampleRateHz, 48000);
      expect(
        () => TriggerMonoAudioValue(values: <double>[], sampleRateHz: 0),
        throwsArgumentError,
      );
      expect(() => TriggerLevelValue(1.1), throwsArgumentError);
    });

    test('copies array values into immutable snapshots', () {
      final samples = <double>[0.1];
      final value = TriggerArrayValue(samples);
      samples[0] = 0.9;

      expect(value.values, <double>[0.1]);
      expect(() => value.values.add(0.2), throwsUnsupportedError);
    });
  });

  group('MacroGraph JSON', () {
    test('round trips a versioned graph without runtime values', () {
      final graph = _validGraph();
      final decoded =
          jsonDecode(jsonEncode(graph.toJson())) as Map<String, dynamic>;
      final restored = MacroGraph.fromJson(decoded);

      expect(restored.schemaVersion, currentMacroGraphSchemaVersion);
      expect(restored.id, graph.id);
      expect(restored.nodes.single.parameters, <String, Object?>{'gain': 0.5});
      expect(restored.targetBindings.single.targetId, 'device-1');
      expect(restored.editorPositions['node-1']?.x, 12);
    });

    test('rejects unknown enum values and future schema versions', () {
      expect(
        () => MacroGraph.fromJson(<String, Object?>{
          'schemaVersion': currentMacroGraphSchemaVersion + 1,
          'id': 'macro-1',
          'name': 'Macro',
          'nodes': <Object?>[],
          'edges': <Object?>[],
        }),
        throwsFormatException,
      );
      expect(
        () => MacroTargetBinding.fromJson(<String, Object?>{
          'id': 'binding-1',
          'sourcePortId': 'out',
          'targetKind': 'not-a-target',
          'targetId': 'device-1',
          'parameter': 'brightness',
        }),
        throwsFormatException,
      );
    });

    test('deeply freezes JSON parameters and rejects non-JSON values', () {
      final nestedValues = <Object?>[
        1.0,
        <String, Object?>{'mode': 'fast'},
      ];
      final node = MacroNode(
        id: 'node-1',
        kind: 'test.node',
        ports: const <MacroPortDeclaration>[],
        parameters: <String, Object?>{'nested': nestedValues},
      );
      nestedValues[0] = 0.0;
      (nestedValues[1] as Map<String, Object?>)['mode'] = 'slow';

      final frozen = node.parameters['nested'] as List<Object?>;
      expect(frozen.first, 1.0);
      expect((frozen[1] as Map<String, Object?>)['mode'], 'fast');
      expect(() => frozen.add(2), throwsUnsupportedError);
      expect(
        () => MacroNode(
          id: 'non-json',
          kind: 'test.node',
          ports: const <MacroPortDeclaration>[],
          parameters: <String, Object?>{'invalid': Object()},
        ),
        throwsArgumentError,
      );
    });

    test('scene macro references have value equality', () {
      final references = <SceneMacroReference>{
        SceneMacroReference(macroId: 'macro-1'),
        SceneMacroReference(macroId: 'macro-1'),
      };

      expect(references, hasLength(1));
      expect(
        SceneMacroReference.fromJson(<String, Object?>{'macroId': 'macro-1'}),
        SceneMacroReference(macroId: 'macro-1'),
      );
    });
  });

  group('MacroGraphValidator', () {
    test('accepts a typed output binding to brightness', () {
      final issues = const MacroGraphValidator(
        knownNodeKinds: <String>{'test.levelSource'},
      ).validate(_validGraph());

      expect(issues, isEmpty);
    });

    test('reports unavailable modules, type errors and invalid targets', () {
      final graph = MacroGraph(
        id: 'macro-invalid',
        name: 'Invalid',
        nodes: <MacroNode>[
          _node(
            id: 'source',
            kind: 'missing.module',
            ports: <MacroPortDeclaration>[
              _output('level', MacroPortType.triggerLevel),
            ],
          ),
          _node(
            id: 'destination',
            kind: 'known.destination',
            ports: <MacroPortDeclaration>[
              _input('array', MacroPortType.triggerArray),
            ],
          ),
        ],
        edges: <MacroEdge>[
          MacroEdge(id: 'edge-1', fromPortId: 'level', toPortId: 'array'),
        ],
        targetBindings: <MacroTargetBinding>[
          MacroTargetBinding(
            id: 'binding-1',
            sourcePortId: 'level',
            targetKind: MacroTargetKind.device,
            targetId: 'missing-device',
            parameter: MacroTargetParameter.brightness,
          ),
        ],
      );

      final issues = MacroGraphValidator(
        knownNodeKinds: const <String>{'known.destination'},
        targetValidator: _RejectingTargetValidator(),
      ).validate(graph);

      expect(
        issues.map((issue) => issue.code),
        containsAll(<MacroGraphValidationCode>[
          MacroGraphValidationCode.unknownNodeKind,
          MacroGraphValidationCode.incompatiblePortTypes,
          MacroGraphValidationCode.invalidTargetBinding,
        ]),
      );
    });

    test('reports missing ports and directed cycles', () {
      final graph = MacroGraph(
        id: 'macro-cycle',
        name: 'Cycle',
        nodes: <MacroNode>[
          _node(
            id: 'first',
            kind: 'node',
            ports: <MacroPortDeclaration>[
              _input('first-in', MacroPortType.triggerLevel),
              _output('first-out', MacroPortType.triggerLevel),
            ],
          ),
          _node(
            id: 'second',
            kind: 'node',
            ports: <MacroPortDeclaration>[
              _input('second-in', MacroPortType.triggerLevel),
              _output('second-out', MacroPortType.triggerLevel),
            ],
          ),
        ],
        edges: <MacroEdge>[
          MacroEdge(
            id: 'a-to-b',
            fromPortId: 'first-out',
            toPortId: 'second-in',
          ),
          MacroEdge(
            id: 'b-to-a',
            fromPortId: 'second-out',
            toPortId: 'first-in',
          ),
          MacroEdge(
            id: 'missing',
            fromPortId: 'no-such-port',
            toPortId: 'first-in',
          ),
        ],
      );

      final issues = const MacroGraphValidator().validate(graph);

      expect(
        issues.map((issue) => issue.code),
        contains(MacroGraphValidationCode.missingPort),
      );
      expect(
        issues.map((issue) => issue.code),
        contains(MacroGraphValidationCode.cycle),
      );
    });
  });
}

MacroGraph _validGraph() => MacroGraph(
  id: 'macro-1',
  name: 'Brightness macro',
  nodes: <MacroNode>[
    _node(
      id: 'node-1',
      kind: 'test.levelSource',
      parameters: <String, Object?>{'gain': 0.5},
      ports: <MacroPortDeclaration>[
        _output('level-out', MacroPortType.triggerLevel),
      ],
    ),
  ],
  edges: const <MacroEdge>[],
  targetBindings: <MacroTargetBinding>[
    MacroTargetBinding(
      id: 'binding-1',
      sourcePortId: 'level-out',
      targetKind: MacroTargetKind.device,
      targetId: 'device-1',
      parameter: MacroTargetParameter.brightness,
    ),
  ],
  editorPositions: <String, MacroEditorPosition>{
    'node-1': MacroEditorPosition(x: 12, y: 24),
  },
);

MacroNode _node({
  required String id,
  required String kind,
  required Iterable<MacroPortDeclaration> ports,
  Map<String, Object?> parameters = const <String, Object?>{},
}) => MacroNode(id: id, kind: kind, ports: ports, parameters: parameters);

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

final class _RejectingTargetValidator implements MacroTargetValidator {
  @override
  String? validate(MacroTargetBinding binding) => 'Target is not available.';
}
