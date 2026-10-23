import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/features/groups/application/group_targets.dart';
import 'package:lazerus_app/features/scenes/application/scene_target_options.dart';
import 'package:lazerus_app/features/scenes/application/scenes_controller.dart';
import 'package:lazerus_app/features/scenes/data/scene_repository.dart';
import 'package:lazerus_app/features/scenes/domain/lighting_scene.dart';
import 'package:lazerus_app/features/scenes/presentation/scene_settings_page.dart';

void main() {
  testWidgets('adds, edits and clears a control from a stable empty slot', (
    tester,
  ) async {
    final reference = SceneTargetReference(
      type: SceneTargetType.device,
      targetId: 'device-a',
    );
    final scene = LightingScene(
      id: 'scene-1',
      name: 'Evening',
      targets: <SceneTargetReference>[reference],
      controlSlots: <SceneControlSlot>[SceneControlSlot(id: 'slot-1')],
    );
    final option = SceneTargetOption(
      reference: reference,
      name: 'Desk strip',
      target: LightingTarget(
        id: 'device-a',
        name: 'Desk strip',
        kind: LightingTargetKind.device,
        memberDeviceIds: const <String>{'device-a'},
      ),
      supportedParameters: const <SceneParameter>{
        SceneParameter.power,
        SceneParameter.brightness,
      },
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          sceneRepositoryProvider.overrideWithValue(
            InMemorySceneRepository(
              SceneConfiguration(scenes: <LightingScene>[scene]),
            ),
          ),
          sceneTargetOptionsProvider.overrideWithValue(<SceneTargetOption>[
            option,
          ]),
        ],
        child: MaterialApp(home: SceneSettingsPage(scene: scene)),
      ),
    );
    await tester.pump();
    await tester.pump();

    await tester.tap(
      find.byKey(const ValueKey<String>('scene-control-slot-slot-1')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Новий контрол'), findsOneWidget);

    await tester.tap(
      find.byKey(
        const ValueKey<String>('scene-control-binding-device-device-a'),
      ),
    );
    await tester.tap(find.byKey(const Key('save-scene-control')));
    await tester.pumpAndSettle();
    expect(find.text('Живлення'), findsOneWidget);

    await tester.tap(
      find.byKey(const ValueKey<String>('scene-control-slot-slot-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('scene-control-type')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Слайдер яскравості').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('save-scene-control')));
    await tester.pumpAndSettle();
    expect(find.text('Яскравість'), findsOneWidget);

    await tester.tap(find.byKey(const Key('delete-scene-control-slot-1')));
    await tester.pumpAndSettle();
    expect(find.text('Порожній слот'), findsOneWidget);
  });
}
