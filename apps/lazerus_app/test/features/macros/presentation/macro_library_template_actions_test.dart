import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/persistence/macro_repository.dart';
import 'package:lazerus_app/core/macros/registry/macro_module_registry.dart';
import 'package:lazerus_app/core/macros/sinks/lighting_target_sink.dart';
import 'package:lazerus_app/core/macros/templates/macro_template_file_gateway.dart';
import 'package:lazerus_app/features/macros/application/macro_library_controller.dart';
import 'package:lazerus_app/features/macros/application/macro_template_transfer_controller.dart';
import 'package:lazerus_app/features/macros/presentation/macro_library_page.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  testWidgets('saves a Macro from its library action', (tester) async {
    final files = _FakeMacroTemplateFiles();
    final macro = _macro();
    final container = ProviderContainer(
      overrides: [
        macroRepositoryProvider.overrideWith(
          (ref) async => InMemoryMacroRepository(<MacroGraph>[macro]),
        ),
        macroTemplateFileGatewayProvider.overrideWithValue(files),
        macroModuleRegistryProvider.overrideWithValue(MacroModuleRegistry()),
      ],
    );
    addTearDown(container.dispose);

    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: MacroLibraryPage()),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(find.byKey(const Key('export-macro-macro-kitchen')));
    await tester.pump();
    await tester.pump();

    expect(files.document, isNotNull);
    expect(files.document, isNot(contains('device-kitchen')));
    expect(find.text('Macro template збережено.'), findsOneWidget);
  });
}

class _FakeMacroTemplateFiles implements MacroTemplateFileGateway {
  String? document;

  @override
  bool get supportsSaveAs => true;

  @override
  Future<String?> selectTemplateDocument() async => null;

  @override
  Future<bool> saveTemplateDocument({
    required String document,
    required String suggestedFileName,
  }) async {
    this.document = document;
    return true;
  }
}

MacroGraph _macro() {
  final configuration = LightingTargetNodeConfiguration(
    targetId: 'device-kitchen',
    parameters: const <MacroTargetParameter>[MacroTargetParameter.brightness],
  );
  return MacroGraph(
    id: 'macro-kitchen',
    name: 'Kitchen reactive lights',
    nodes: <MacroNode>[
      MacroNode(
        id: 'target',
        kind: lightingTargetSinkKind,
        displayName: 'Kitchen strip',
        ports: configuration.portsForNode('target'),
        parameters: configuration.toNodeParameters(),
      ),
    ],
    edges: const <MacroEdge>[],
  );
}
