import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/sinks/lighting_target_sink.dart';
import 'package:lazerus_app/core/macros/templates/macro_template.dart';
import 'package:lazerus_app/core/macros/templates/macro_template_transformer.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  const transformer = MacroTemplateTransformer();

  test('exports target nodes as device-free placeholders', () {
    final macro = _macro();

    final template = transformer.export(macro);
    final document = jsonEncode(template.toJson());
    final target = LightingTargetNodeConfiguration.fromNode(
      template.graph.nodes.singleWhere(
        (node) => node.kind == lightingTargetSinkKind,
      ),
    );

    expect(document, isNot(contains('device-kitchen')));
    expect(document, isNot(contains('Kitchen strip')));
    expect(template.graph.id, 'template-macro');
    expect(template.placeholders, hasLength(1));
    expect(target.targetId, 'template-device:1');
    expect(template.graph.targetBindings.single.targetId, 'template-device:1');
  });

  test('imports with a fresh Macro ID and preserves graph topology', () {
    final template = transformer.export(_macro());

    final imported = transformer.importTemplate(
      MacroTemplate.fromJson(template.toJson()),
      newMacroId: 'imported-macro',
    );

    expect(imported.id, 'imported-macro');
    expect(imported.name, 'Kitchen reactive lights');
    expect(imported.edges, hasLength(1));
    expect(
      imported.editorPositions.keys,
      containsAll(<String>['source', 'target']),
    );
    expect(imported.editorPositions['target']!.x, 300);
    expect(imported.editorPositions['target']!.y, 30);
  });

  test('replaces a placeholder without changing its node or port IDs', () {
    final imported = transformer.importTemplate(
      transformer.export(_macro()),
      newMacroId: 'imported-macro',
    );
    final placeholder = imported.nodes.singleWhere(
      (node) => node.kind == lightingTargetSinkKind,
    );

    final replacement = transformer.replacePlaceholderNode(
      node: placeholder,
      appDeviceId: 'device-bedroom',
      deviceName: 'Bedroom strip',
    );

    expect(replacement.id, placeholder.id);
    expect(
      replacement.ports.map((port) => port.id),
      orderedEquals(placeholder.ports.map((port) => port.id)),
    );
    expect(
      LightingTargetNodeConfiguration.fromNode(replacement).targetId,
      'device-bedroom',
    );
  });

  test('creates an execution graph that skips unresolved placeholders', () {
    final imported = transformer.importTemplate(
      transformer.export(_macro()),
      newMacroId: 'imported-macro',
    );
    final realDeviceBinding = MacroTargetBinding(
      id: 'mapped-device-binding',
      sourcePortId: imported.targetBindings.single.sourcePortId,
      targetId: 'device-living-room',
      parameter: imported.targetBindings.single.parameter,
    );

    final execution = transformer.executionGraph(
      imported.copyWith(
        targetBindings: <MacroTargetBinding>[
          ...imported.targetBindings,
          realDeviceBinding,
        ],
      ),
    );

    expect(imported.targetBindings, hasLength(1));
    expect(
      execution.targetBindings,
      orderedEquals(<MacroTargetBinding>[realDeviceBinding]),
    );
    expect(execution.nodes, orderedEquals(imported.nodes));
    expect(execution.edges, orderedEquals(imported.edges));
  });

  test('rejects imported templates with a direct device target', () {
    final template = transformer.export(_macro());
    final placeholder = template.graph.nodes.singleWhere(
      (node) => node.kind == lightingTargetSinkKind,
    );
    final directTarget = MacroNode(
      id: placeholder.id,
      kind: placeholder.kind,
      displayName: 'Kitchen strip',
      ports: placeholder.ports,
      parameters: LightingTargetNodeConfiguration(
        targetId: 'device-kitchen',
        parameters: const <MacroTargetParameter>[
          MacroTargetParameter.brightness,
        ],
      ).toNodeParameters(),
    );
    final invalid = MacroTemplate(
      name: template.name,
      graph: template.graph.copyWith(
        nodes: <MacroNode>[
          for (final node in template.graph.nodes)
            if (node.id == directTarget.id) directTarget else node,
        ],
      ),
      placeholders: template.placeholders,
    );

    expect(
      () => transformer.importTemplate(invalid, newMacroId: 'imported-macro'),
      throwsFormatException,
    );
  });

  test('rejects a template from a newer schema', () {
    final json = transformer.export(_macro()).toJson()
      ..['templateSchemaVersion'] = currentMacroTemplateSchemaVersion + 1;

    expect(() => MacroTemplate.fromJson(json), throwsFormatException);
  });
}

MacroGraph _macro() {
  final source = MacroNode(
    id: 'source',
    kind: 'test.source',
    displayName: 'Source',
    ports: <MacroPortDeclaration>[
      MacroPortDeclaration(
        id: 'source.level',
        direction: MacroPortDirection.output,
        type: MacroPortType.triggerLevel,
        displayIdentifier: 'source.level',
      ),
    ],
  );
  final targetConfiguration = LightingTargetNodeConfiguration(
    targetId: 'device-kitchen',
    parameters: const <MacroTargetParameter>[MacroTargetParameter.brightness],
  );
  final target = MacroNode(
    id: 'target',
    kind: lightingTargetSinkKind,
    displayName: 'Kitchen strip',
    ports: targetConfiguration.portsForNode('target'),
    parameters: targetConfiguration.toNodeParameters(),
  );
  return MacroGraph(
    id: 'macro-kitchen',
    name: 'Kitchen reactive lights',
    nodes: <MacroNode>[source, target],
    edges: <MacroEdge>[
      MacroEdge(
        id: 'edge-1',
        fromPortId: 'source.level',
        toPortId: 'target.brightness',
      ),
    ],
    targetBindings: <MacroTargetBinding>[
      MacroTargetBinding(
        id: 'target-edge-edge-1',
        sourcePortId: 'source.level',
        targetId: 'device-kitchen',
        parameter: MacroTargetParameter.brightness,
      ),
    ],
    editorPositions: <String, MacroEditorPosition>{
      'source': MacroEditorPosition(x: 20, y: 30),
      'target': MacroEditorPosition(x: 300, y: 30),
    },
  );
}
