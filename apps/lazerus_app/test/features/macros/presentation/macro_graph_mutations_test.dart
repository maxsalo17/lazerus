import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/modifiers/normalization/normalization_modifier.dart';
import 'package:lazerus_app/features/macros/presentation/macro_graph_mutations.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'removes only replaced-node connections made incompatible by port type',
    () {
      final factory = NormalizationModifierFactory();
      final pcmNode = _normalizationNode(factory, NormalizationOutputMode.pcm);
      final valueNode = _normalizationNode(
        factory,
        NormalizationOutputMode.value,
      );
      final graph = MacroGraph(
        id: 'macro',
        name: 'Macro',
        nodes: <MacroNode>[
          pcmNode,
          _audioSink(),
          _unrelatedSource(),
          _gateSink(),
        ],
        edges: <MacroEdge>[
          MacroEdge(
            id: 'normalization-to-audio',
            fromPortId: factory.normalizedOutputPortId(pcmNode),
            toPortId: 'audio-sink.input',
          ),
          MacroEdge(
            id: 'unrelated',
            fromPortId: 'unrelated-source.output',
            toPortId: 'gate-sink.input',
          ),
        ],
      );

      final updated = replaceMacroGraphNode(graph, valueNode);

      expect(updated.nodes.first.ports.last.type, MacroPortType.triggerLevel);
      expect(updated.edges.map((edge) => edge.id), <String>['unrelated']);
    },
  );

  test('keeps a connection when an output type remains compatible', () {
    final factory = NormalizationModifierFactory();
    final pcmNode = _normalizationNode(factory, NormalizationOutputMode.pcm);
    final updatedPcmNode = _normalizationNode(
      factory,
      NormalizationOutputMode.pcm,
      duration: const Duration(seconds: 8),
    );
    final graph = MacroGraph(
      id: 'macro',
      name: 'Macro',
      nodes: <MacroNode>[pcmNode, _audioSink()],
      edges: <MacroEdge>[
        MacroEdge(
          id: 'normalization-to-audio',
          fromPortId: factory.normalizedOutputPortId(pcmNode),
          toPortId: 'audio-sink.input',
        ),
      ],
    );

    final updated = replaceMacroGraphNode(graph, updatedPcmNode);

    expect(updated.edges, hasLength(1));
  });
}

MacroNode _normalizationNode(
  NormalizationModifierFactory factory,
  NormalizationOutputMode mode, {
  Duration duration = const Duration(seconds: 5),
}) {
  final configuration = NormalizationModifierConfiguration(
    outputMode: mode,
    windowDuration: duration,
  );
  final unconfigured = MacroNode(
    id: 'normalization',
    kind: normalizationModifierKind,
    ports: const <MacroPortDeclaration>[],
    parameters: configuration.toNodeParameters(),
  );
  return unconfigured.copyWith(ports: factory.portsFor(unconfigured));
}

MacroNode _audioSink() => MacroNode(
  id: 'audio-sink',
  kind: 'test.audio-sink',
  ports: <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: 'audio-sink.input',
      direction: MacroPortDirection.input,
      type: MacroPortType.triggerMonoAudio,
      displayIdentifier: 'test.audio-sink.input',
    ),
  ],
);

MacroNode _unrelatedSource() => MacroNode(
  id: 'unrelated-source',
  kind: 'test.source',
  ports: <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: 'unrelated-source.output',
      direction: MacroPortDirection.output,
      type: MacroPortType.triggerGate,
      displayIdentifier: 'test.source.output',
    ),
  ],
);

MacroNode _gateSink() => MacroNode(
  id: 'gate-sink',
  kind: 'test.gate-sink',
  ports: <MacroPortDeclaration>[
    MacroPortDeclaration(
      id: 'gate-sink.input',
      direction: MacroPortDirection.input,
      type: MacroPortType.triggerGate,
      displayIdentifier: 'test.gate-sink.input',
    ),
  ],
);
