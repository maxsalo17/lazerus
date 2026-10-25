import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/persistence/macro_repository.dart';
import 'package:lazerus_app/core/macros/sinks/lighting_target_sink.dart';
import 'package:lazerus_app/features/macros/application/macro_library_controller.dart';
import 'package:lazerus_app/features/macros/application/macro_runtime_session_controller.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'an unresolved template target is skipped while the Macro starts',
    () async {
      final placeholder = _placeholderMacro();
      final container = ProviderContainer(
        overrides: [
          macroRepositoryProvider.overrideWith(
            (ref) async => InMemoryMacroRepository(<MacroGraph>[placeholder]),
          ),
        ],
      );
      addTearDown(container.dispose);
      container.read(macroLibraryProvider);
      await _settle();

      final controller = container.read(macroRuntimeSessionsProvider.notifier);
      final started = await controller.start(placeholder.id);

      expect(started, isTrue);
      final status = container
          .read(macroRuntimeSessionsProvider)
          .sessions[placeholder.id];
      expect(status?.lifecycle, MacroRuntimeSessionLifecycle.running);
      expect(status?.validationIssues, isEmpty);
      expect(
        container
            .read(macroLibraryProvider)
            .byId(placeholder.id)
            ?.targetBindings,
        hasLength(1),
      );
      await controller.stop(placeholder.id);
    },
  );
}

MacroGraph _placeholderMacro() {
  final configuration = LightingTargetNodeConfiguration(
    targetId: 'template-device:1',
    parameters: const <MacroTargetParameter>[MacroTargetParameter.brightness],
  );
  return MacroGraph(
    id: 'imported-template',
    name: 'Imported template',
    nodes: <MacroNode>[
      MacroNode(
        id: 'target',
        kind: lightingTargetSinkKind,
        displayName: 'Device placeholder 1',
        ports: configuration.portsForNode('target'),
        parameters: configuration.toNodeParameters(),
      ),
    ],
    edges: const <MacroEdge>[],
    targetBindings: <MacroTargetBinding>[
      MacroTargetBinding(
        id: 'placeholder-binding',
        sourcePortId: 'unavailable.output',
        targetId: 'template-device:1',
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
