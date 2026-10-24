import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/macros/presentation/macro_graph_definition.dart';
import 'package:lazerus_app/features/macros/presentation/macro_patcher_canvas.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  testWidgets('a click selects and a drag moves a node header', (tester) async {
    String? selectedNodeId;
    MacroNodeLayout? movedLayout;
    final node = MacroNode(
      id: 'node-1',
      kind: 'test.source',
      displayName: 'Test source',
      ports: <MacroPortDeclaration>[
        MacroPortDeclaration(
          id: 'node-1.out',
          direction: MacroPortDirection.output,
          type: MacroPortType.triggerLevel,
          displayIdentifier: 'test.out',
          displayName: 'Output',
        ),
      ],
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 900,
            height: 600,
            child: MacroPatcherCanvas(
              graph: MacroGraphDefinition(
                nodes: <MacroNode>[node],
                layouts: const <String, MacroNodeLayout>{
                  'node-1': MacroNodeLayout(position: Offset(100, 100)),
                },
              ),
              onSelectionChanged: (nodeId) => selectedNodeId = nodeId,
              onNodeMove: (_, layout) => movedLayout = layout,
            ),
          ),
        ),
      ),
    );

    final header = find.text('[1] Test source');
    await tester.tap(header);
    expect(selectedNodeId, 'node-1');

    await tester.drag(header, const Offset(48, 24));
    expect(movedLayout, isNotNull);
    expect(movedLayout!.position.dx, greaterThan(100));
    expect(movedLayout!.position.dy, greaterThan(100));
  });
}
