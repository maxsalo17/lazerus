import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/persistence/macro_repository.dart';
import 'package:lazerus_app/core/macros/sinks/lighting_target_sink.dart';
import 'package:lazerus_app/core/macros/templates/macro_template_file_gateway.dart';
import 'package:lazerus_app/core/macros/templates/macro_template_transformer.dart';
import 'package:lazerus_app/features/macros/application/macro_library_controller.dart';
import 'package:lazerus_app/features/macros/application/macro_template_transfer_controller.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  late _FakeMacroTemplateFiles files;
  late InMemoryMacroRepository repository;
  late ProviderContainer container;

  setUp(() {
    files = _FakeMacroTemplateFiles();
    repository = InMemoryMacroRepository();
    container = ProviderContainer(
      overrides: [
        macroRepositoryProvider.overrideWith((ref) async => repository),
        macroTemplateFileGatewayProvider.overrideWithValue(files),
      ],
    );
    container.read(macroLibraryProvider);
  });

  tearDown(() => container.dispose());

  test('exports a Macro through the user-selected Save As boundary', () async {
    final controller = container.read(macroTemplateTransferProvider.notifier);

    final outcome = await controller.exportMacro(_macro());

    expect(outcome, MacroTemplateTransferOutcome.completed);
    expect(files.exportedDocument, isNotNull);
    expect(files.exportedName, endsWith('.json'));
    expect(files.exportedDocument, isNot(contains('device-kitchen')));
  });

  test('imports a template as a new saved Macro with placeholders', () async {
    const transformer = MacroTemplateTransformer();
    files.importDocument = jsonEncode(transformer.export(_macro()).toJson());
    await _settle();
    final controller = container.read(macroTemplateTransferProvider.notifier);

    final result = await controller.importMacro();

    expect(result.outcome, MacroTemplateTransferOutcome.completed);
    expect(result.macro, isNotNull);
    expect(result.macro!.id, isNot('macro-kitchen'));
    final saved = await repository.load();
    expect(saved, hasLength(1));
    expect(
      LightingTargetNodeConfiguration.fromNode(
        saved.single.nodes.singleWhere(
          (node) => node.kind == lightingTargetSinkKind,
        ),
      ).targetId,
      'template-device:1',
    );
  });

  test('treats a cancelled Save As dialog as a cancelled export', () async {
    files.saveSucceeds = false;
    final controller = container.read(macroTemplateTransferProvider.notifier);

    final outcome = await controller.exportMacro(_macro());

    expect(outcome, MacroTemplateTransferOutcome.cancelled);
    expect(files.exportedDocument, isNull);
    expect(container.read(macroTemplateTransferProvider).error, isNull);
  });

  test('does not offer export when Save As is unsupported', () async {
    files.canSaveAs = false;
    final controller = container.read(macroTemplateTransferProvider.notifier);

    final outcome = await controller.exportMacro(_macro());

    expect(outcome, MacroTemplateTransferOutcome.failed);
    expect(files.exportedDocument, isNull);
    expect(
      container.read(macroTemplateTransferProvider).error,
      contains('лише на macOS'),
    );
  });

  test(
    'does not mutate the library when an imported document is invalid',
    () async {
      files.importDocument = '{not-json';
      await _settle();
      final controller = container.read(macroTemplateTransferProvider.notifier);

      final result = await controller.importMacro();

      expect(result.outcome, MacroTemplateTransferOutcome.failed);
      expect(await repository.load(), isEmpty);
      expect(
        container.read(macroTemplateTransferProvider).error,
        startsWith('Не вдалося імпортувати'),
      );
    },
  );
}

class _FakeMacroTemplateFiles implements MacroTemplateFileGateway {
  String? importDocument;
  String? exportedDocument;
  String? exportedName;
  bool saveSucceeds = true;
  bool canSaveAs = true;

  @override
  bool get supportsSaveAs => canSaveAs;

  @override
  Future<String?> selectTemplateDocument() async => importDocument;

  @override
  Future<bool> saveTemplateDocument({
    required String document,
    required String suggestedFileName,
  }) async {
    if (!saveSucceeds) return false;
    exportedDocument = document;
    exportedName = suggestedFileName;
    return true;
  }
}

MacroGraph _macro() {
  final source = MacroNode(
    id: 'source',
    kind: 'test.source',
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
  );
}

Future<void> _settle() async {
  for (var index = 0; index < 4; index++) {
    await Future<void>.delayed(Duration.zero);
  }
}
