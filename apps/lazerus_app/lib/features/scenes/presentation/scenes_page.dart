import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../application/scenes_controller.dart';
import '../domain/lighting_scene.dart';
import 'scene_detail_page.dart';
import 'scene_macro_references.dart';
import 'scene_settings_page.dart';

class ScenesPage extends ConsumerWidget {
  const ScenesPage({
    super.key,
    this.macroReferencesEditor,
    this.macroReferenceResolver,
  });

  final SceneMacroReferencesEditor? macroReferencesEditor;
  final SceneMacroReferenceResolver? macroReferenceResolver;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(scenesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Scenes')),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-scene'),
        heroTag: 'create-scene',
        onPressed: state.isLoading
            ? null
            : () => unawaited(_createScene(context, ref)),
        icon: const Icon(Icons.add),
        label: const Text('Створити'),
      ),
      body: state.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const Text(
                  'Сцена поєднує групи та девайси. Натисніть Scene, щоб відкрити її контроли.',
                ),
                const SizedBox(height: 16),
                if (state.error case final error? when error.isNotEmpty)
                  _SceneError(message: error),
                if (state.scenes.isEmpty)
                  const _EmptyScenes()
                else
                  ...state.scenes.map(
                    (scene) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _SceneTile(
                        scene: scene,
                        macroReferencesEditor: macroReferencesEditor,
                        macroReferenceResolver: macroReferenceResolver,
                      ),
                    ),
                  ),
                const SizedBox(height: 72),
              ],
            ),
    );
  }

  Future<void> _createScene(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => const _CreateSceneDialog(),
    );
    if (!context.mounted || name == null) {
      return;
    }
    final slots = List<SceneControlSlot>.generate(
      3,
      (_) => SceneControlSlot(id: const Uuid().v4()),
      growable: false,
    );
    final scene = await ref
        .read(scenesProvider.notifier)
        .create(name: name, controlSlots: slots);
    if (!context.mounted || scene == null) {
      return;
    }
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => SceneSettingsPage(
          scene: scene,
          macroReferencesEditor: macroReferencesEditor,
          macroReferenceResolver: macroReferenceResolver,
        ),
      ),
    );
  }
}

class _SceneTile extends StatelessWidget {
  const _SceneTile({
    required this.scene,
    required this.macroReferencesEditor,
    required this.macroReferenceResolver,
  });

  final LightingScene scene;
  final SceneMacroReferencesEditor? macroReferencesEditor;
  final SceneMacroReferenceResolver? macroReferenceResolver;

  @override
  Widget build(BuildContext context) {
    final configuredControls = scene.controlSlots
        .where((slot) => slot.control != null)
        .length;
    return Card(
      child: ListTile(
        key: ValueKey<String>('scene-${scene.id}'),
        leading: const Icon(Icons.auto_awesome_motion_outlined),
        title: Text(scene.name),
        subtitle: Text(
          '${scene.targets.length} цілей · $configuredControls контролів',
        ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              tooltip: 'Scene Settings',
              onPressed: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(
                  builder: (_) => SceneSettingsPage(
                    scene: scene,
                    macroReferencesEditor: macroReferencesEditor,
                    macroReferenceResolver: macroReferenceResolver,
                  ),
                ),
              ),
              icon: const Icon(Icons.settings_outlined),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
        onTap: () => Navigator.of(context).push<void>(
          MaterialPageRoute<void>(
            builder: (_) => SceneDetailPage(
              sceneId: scene.id,
              macroReferencesEditor: macroReferencesEditor,
              macroReferenceResolver: macroReferenceResolver,
            ),
          ),
        ),
      ),
    );
  }
}

class _CreateSceneDialog extends StatefulWidget {
  const _CreateSceneDialog();

  @override
  State<_CreateSceneDialog> createState() => _CreateSceneDialogState();
}

class _CreateSceneDialogState extends State<_CreateSceneDialog> {
  final TextEditingController _nameController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Нова Scene'),
      content: TextField(
        key: const Key('scene-name-input'),
        controller: _nameController,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Назва'),
        textInputAction: TextInputAction.done,
        onSubmitted: (value) => Navigator.of(context).pop(value),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_nameController.text),
          child: const Text('Створити'),
        ),
      ],
    );
  }
}

class _EmptyScenes extends StatelessWidget {
  const _EmptyScenes();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          children: <Widget>[
            Icon(Icons.auto_awesome_motion_outlined, size: 42),
            SizedBox(height: 10),
            Text('Scenes ще немає.'),
            SizedBox(height: 4),
            Text('Створіть Scene, потім додайте цілі та власні контроли.'),
          ],
        ),
      ),
    );
  }
}

class _SceneError extends StatelessWidget {
  const _SceneError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Card(
        color: Theme.of(context).colorScheme.errorContainer,
        child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
      ),
    );
  }
}
