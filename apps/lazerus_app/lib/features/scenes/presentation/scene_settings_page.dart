import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:uuid/uuid.dart';

import '../application/scene_target_options.dart';
import '../application/scenes_controller.dart';
import '../domain/lighting_scene.dart';
import 'scene_control_editor_page.dart';
import 'scene_macro_references.dart';

class SceneSettingsPage extends ConsumerStatefulWidget {
  const SceneSettingsPage({
    super.key,
    required this.scene,
    this.macroReferencesEditor,
    this.macroReferenceResolver,
  });

  final LightingScene scene;

  /// Optional host integration for selecting or editing macro definitions.
  final SceneMacroReferencesEditor? macroReferencesEditor;

  /// Optional host integration for detecting persisted missing macro ids.
  final SceneMacroReferenceResolver? macroReferenceResolver;

  @override
  ConsumerState<SceneSettingsPage> createState() => _SceneSettingsPageState();
}

class _SceneSettingsPageState extends ConsumerState<SceneSettingsPage> {
  late LightingScene _scene;
  late TextEditingController _nameController;
  var _saving = false;
  String? _localError;

  @override
  void initState() {
    super.initState();
    _scene = widget.scene;
    _nameController = TextEditingController(text: _scene.name);
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scenesState = ref.watch(scenesProvider);
    final availableOptions = ref.watch(sceneTargetOptionsProvider);
    final sceneOptions = optionsForSceneTargets(
      availableOptions: availableOptions,
      references: _scene.targets,
    );
    final stateError = scenesState.error;
    final canEdit = !_saving && !scenesState.isLoading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Scene Settings'),
        actions: <Widget>[
          TextButton(
            key: const Key('save-scene-name'),
            onPressed: canEdit ? _saveName : null,
            child: const Text('Зберегти'),
          ),
          IconButton(
            key: const Key('delete-scene'),
            tooltip: 'Видалити Scene',
            onPressed: canEdit ? _deleteScene : null,
            icon: const Icon(Icons.delete_outline),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: <Widget>[
            if (scenesState.isLoading) const LinearProgressIndicator(),
            TextField(
              key: const Key('scene-settings-name'),
              controller: _nameController,
              enabled: canEdit,
              decoration: const InputDecoration(
                labelText: 'Назва Scene',
                border: OutlineInputBorder(),
              ),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => _saveName(),
            ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Цілі',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('edit-scene-targets'),
                  onPressed: canEdit
                      ? () => _editTargets(availableOptions)
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Змінити'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Групи залишаються динамічними: їхній склад не копіюється в Scene.',
            ),
            const SizedBox(height: 8),
            if (sceneOptions.isEmpty)
              const _EmptyTargetList()
            else
              ...sceneOptions.map(
                (option) => _SceneTargetTile(
                  option: option,
                  enabled: canEdit,
                  onRemove: () => _removeTarget(option.reference),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Custom controls',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('add-scene-slot'),
                  onPressed: canEdit ? _addSlot : null,
                  icon: const Icon(Icons.add),
                  label: const Text('Слот'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            const Text(
              'Натисніть порожній слот, щоб додати контрол. Існуючий контрол можна відредагувати або очистити.',
            ),
            const SizedBox(height: 8),
            if (_scene.controlSlots.isEmpty)
              const _EmptySlotList()
            else
              ..._scene.controlSlots.map(
                (slot) => _SceneControlSlotTile(
                  slot: slot,
                  enabled: canEdit,
                  onOpen: () => _openEditor(slot, sceneOptions),
                  onClear: slot.control == null ? null : () => _clearSlot(slot),
                ),
              ),
            const SizedBox(height: 24),
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    'Macros',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  key: const Key('edit-scene-macros'),
                  onPressed: canEdit && widget.macroReferencesEditor != null
                      ? _editMacroReferences
                      : null,
                  icon: const Icon(Icons.edit_outlined),
                  label: const Text('Керувати'),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.macroReferencesEditor == null
                  ? 'Підключіть macro picker у host page, щоб додавати або замінювати macros.'
                  : 'Macros зберігаються як посилання. Недоступне посилання можна видалити або замінити.',
            ),
            const SizedBox(height: 8),
            if (_scene.macroReferences.isEmpty)
              const _EmptyMacroReferenceList()
            else
              ..._scene.macroReferences.map(
                (reference) => _SceneMacroReferenceTile(
                  reference: reference,
                  enabled: canEdit,
                  resolver: widget.macroReferenceResolver,
                  onRemove: () => _removeMacroReference(reference),
                ),
              ),
            if (_localError != null ||
                (stateError != null && stateError.isNotEmpty)) ...<Widget>[
              const SizedBox(height: 16),
              _SettingsError(message: _localError ?? stateError!),
            ],
            const SizedBox(height: 28),
            Text(
              'Bindings зберігають лише application device ID або group ID. Відсутня ціль не видаляється автоматично.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveName() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _localError = 'Вкажіть назву Scene.');
      return;
    }
    await _persist(_scene.copyWith(name: name));
  }

  Future<void> _editTargets(List<SceneTargetOption> availableOptions) async {
    final allOptions = <SceneTargetOption>[
      ...optionsForSceneTargets(
        availableOptions: availableOptions,
        references: _scene.targets,
      ),
      ...availableOptions.where(
        (candidate) => !_scene.targets.contains(candidate.reference),
      ),
    ];
    final targets = await showDialog<List<SceneTargetReference>>(
      context: context,
      builder: (dialogContext) => _SceneTargetPicker(
        options: allOptions,
        initialTargets: _scene.targets,
      ),
    );
    if (!mounted || targets == null) {
      return;
    }
    final removed = _scene.targets
        .where((target) => !targets.contains(target))
        .toSet();
    final hasBoundControl = _scene.controlSlots.any(
      (slot) =>
          slot.control?.bindings.any(
            (binding) => removed.contains(binding.target),
          ) ??
          false,
    );
    if (hasBoundControl) {
      setState(() {
        _localError =
            'Спочатку приберіть або змініть bindings контролу для цілі, яку хочете видалити.';
      });
      return;
    }
    await _persist(_scene.copyWith(targets: targets));
  }

  Future<void> _removeTarget(SceneTargetReference reference) async {
    final bound = _scene.controlSlots.any(
      (slot) =>
          slot.control?.bindings.any(
            (binding) => binding.target == reference,
          ) ??
          false,
    );
    if (bound) {
      setState(() {
        _localError =
            'Спочатку очистіть або відредагуйте контрол, який використовує цю ціль.';
      });
      return;
    }
    await _persist(
      _scene.copyWith(
        targets: _scene.targets
            .where((target) => target != reference)
            .toList(growable: false),
      ),
    );
  }

  Future<void> _addSlot() async {
    await _persist(
      _scene.copyWith(
        controlSlots: <SceneControlSlot>[
          ..._scene.controlSlots,
          SceneControlSlot(id: const Uuid().v4()),
        ],
      ),
    );
  }

  Future<void> _editMacroReferences() async {
    final editor = widget.macroReferencesEditor;
    if (editor == null) {
      return;
    }
    final references = await editor(context, _scene.macroReferences);
    if (!mounted || references == null) {
      return;
    }
    await _persistMacroReferences(references);
  }

  Future<void> _removeMacroReference(SceneMacroReference reference) {
    return _persistMacroReferences(
      _scene.macroReferences
          .where((candidate) => candidate != reference)
          .toList(growable: false),
    );
  }

  Future<void> _persistMacroReferences(
    Iterable<SceneMacroReference> references,
  ) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _localError = null;
    });
    final nextReferences = List<SceneMacroReference>.from(references);
    final saved = await ref
        .read(scenesProvider.notifier)
        .updateMacroReferences(_scene.id, nextReferences);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (saved) {
        _scene = _scene.copyWith(macroReferences: nextReferences);
      } else {
        _localError =
            ref.read(scenesProvider).error ??
            'Не вдалося зберегти macros Scene.';
      }
    });
  }

  Future<void> _openEditor(
    SceneControlSlot slot,
    List<SceneTargetOption> targetOptions,
  ) async {
    final control = await Navigator.of(context).push<SceneCustomControl>(
      MaterialPageRoute<SceneCustomControl>(
        builder: (_) => SceneControlEditorPage(
          scene: _scene,
          slot: slot,
          targetOptions: targetOptions,
        ),
      ),
    );
    if (!mounted || control == null) {
      return;
    }
    await _persist(
      _scene.copyWith(
        controlSlots: _scene.controlSlots
            .map(
              (current) => current.id == slot.id
                  ? current.copyWith(control: control)
                  : current,
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _clearSlot(SceneControlSlot slot) async {
    await _persist(
      _scene.copyWith(
        controlSlots: _scene.controlSlots
            .map(
              (current) => current.id == slot.id
                  ? current.copyWith(clearControl: true)
                  : current,
            )
            .toList(growable: false),
      ),
    );
  }

  Future<void> _deleteScene() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Видалити «${_scene.name}»?'),
        content: const Text('Групи та девайси не буде видалено.'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Скасувати'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Видалити'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) {
      return;
    }
    setState(() => _saving = true);
    final deleted = await ref.read(scenesProvider.notifier).delete(_scene.id);
    if (!mounted) {
      return;
    }
    if (deleted) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _saving = false);
  }

  Future<void> _persist(LightingScene next) async {
    if (_saving) {
      return;
    }
    setState(() {
      _saving = true;
      _localError = null;
    });
    final saved = await ref.read(scenesProvider.notifier).update(next);
    if (!mounted) {
      return;
    }
    setState(() {
      _saving = false;
      if (saved) {
        _scene = next;
        _nameController.value = TextEditingValue(
          text: next.name,
          selection: TextSelection.collapsed(offset: next.name.length),
        );
      } else {
        _localError =
            ref.read(scenesProvider).error ?? 'Не вдалося зберегти Scene.';
      }
    });
  }
}

class _EmptyMacroReferenceList extends StatelessWidget {
  const _EmptyMacroReferenceList();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('До Scene не додано macros.'),
      ),
    );
  }
}

class _SceneMacroReferenceTile extends StatefulWidget {
  const _SceneMacroReferenceTile({
    required this.reference,
    required this.enabled,
    required this.resolver,
    required this.onRemove,
  });

  final SceneMacroReference reference;
  final bool enabled;
  final SceneMacroReferenceResolver? resolver;
  final VoidCallback onRemove;

  @override
  State<_SceneMacroReferenceTile> createState() =>
      _SceneMacroReferenceTileState();
}

class _SceneMacroReferenceTileState extends State<_SceneMacroReferenceTile> {
  late Future<SceneMacroReferenceResolution> _resolution;

  @override
  void initState() {
    super.initState();
    _resolution = _resolve();
  }

  @override
  void didUpdateWidget(covariant _SceneMacroReferenceTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.reference.macroId != widget.reference.macroId ||
        oldWidget.resolver != widget.resolver) {
      _resolution = _resolve();
    }
  }

  Future<SceneMacroReferenceResolution> _resolve() {
    final resolver = widget.resolver;
    if (resolver == null) {
      return Future<SceneMacroReferenceResolution>.value(
        unknownSceneMacroReference,
      );
    }
    return Future<SceneMacroReferenceResolution>.sync(
      () => resolver(widget.reference),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<SceneMacroReferenceResolution>(
      future: _resolution,
      initialData: unknownSceneMacroReference,
      builder: (context, snapshot) {
        final value = snapshot.data ?? unknownSceneMacroReference;
        final status = snapshot.hasError
            ? SceneMacroReferenceStatus.unknown
            : value.status;
        final detail = snapshot.hasError
            ? 'Не вдалося перевірити macro: ${snapshot.error}'
            : value.detail;
        final color = switch (status) {
          SceneMacroReferenceStatus.available => Theme.of(
            context,
          ).colorScheme.primary,
          SceneMacroReferenceStatus.missing => Theme.of(
            context,
          ).colorScheme.error,
          SceneMacroReferenceStatus.unknown => Theme.of(
            context,
          ).colorScheme.outline,
        };
        final statusLabel = switch (status) {
          SceneMacroReferenceStatus.available => 'Доступний',
          SceneMacroReferenceStatus.missing => 'Відсутній',
          SceneMacroReferenceStatus.unknown => 'Не перевірено',
        };
        return Card(
          child: ListTile(
            key: ValueKey<String>('scene-macro-${widget.reference.macroId}'),
            leading: Icon(Icons.account_tree_outlined, color: color),
            title: Text(
              value.label?.trim().isNotEmpty == true
                  ? value.label!
                  : widget.reference.macroId,
            ),
            subtitle: Text(
              detail == null || detail.isEmpty
                  ? '$statusLabel · ID: ${widget.reference.macroId}'
                  : '$statusLabel · $detail\nID: ${widget.reference.macroId}',
            ),
            isThreeLine: detail != null && detail.isNotEmpty,
            trailing: IconButton(
              key: Key('remove-scene-macro-${widget.reference.macroId}'),
              tooltip: 'Прибрати macro зі Scene',
              onPressed: widget.enabled ? widget.onRemove : null,
              icon: const Icon(Icons.remove_circle_outline),
            ),
          ),
        );
      },
    );
  }
}

class _SceneTargetTile extends StatelessWidget {
  const _SceneTargetTile({
    required this.option,
    required this.enabled,
    required this.onRemove,
  });

  final SceneTargetOption option;
  final bool enabled;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      key: Key(
        'scene-target-${option.reference.type.name}-${option.reference.targetId}',
      ),
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        option.reference.type == SceneTargetType.group
            ? Icons.group_outlined
            : Icons.devices_outlined,
      ),
      title: Text(option.name),
      subtitle: Text('${option.kindLabel} · ${option.availabilityLabel}'),
      trailing: IconButton(
        tooltip: 'Прибрати ціль',
        onPressed: enabled ? onRemove : null,
        icon: const Icon(Icons.close),
      ),
    );
  }
}

class _SceneControlSlotTile extends StatelessWidget {
  const _SceneControlSlotTile({
    required this.slot,
    required this.enabled,
    required this.onOpen,
    required this.onClear,
  });

  final SceneControlSlot slot;
  final bool enabled;
  final VoidCallback onOpen;
  final VoidCallback? onClear;

  @override
  Widget build(BuildContext context) {
    final control = slot.control;
    final isEmpty = control == null;
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        key: ValueKey<String>('scene-control-slot-${slot.id}'),
        leading: Icon(
          isEmpty ? Icons.add_circle_outline : _iconFor(control.type),
        ),
        title: Text(isEmpty ? 'Порожній слот' : _titleFor(control)),
        subtitle: Text(
          isEmpty
              ? 'Натисніть, щоб додати контрол'
              : '${control.bindings.length} ${_bindingWord(control.bindings.length)}',
        ),
        trailing: isEmpty
            ? const Icon(Icons.chevron_right)
            : IconButton(
                key: Key('delete-scene-control-${slot.id}'),
                tooltip: 'Очистити слот',
                onPressed: enabled ? onClear : null,
                icon: const Icon(Icons.delete_outline),
              ),
        enabled: enabled,
        onTap: enabled ? onOpen : null,
      ),
    );
  }

  static IconData _iconFor(SceneControlType type) => switch (type) {
    SceneControlType.toggle => Icons.power_settings_new,
    SceneControlType.brightnessSlider => Icons.brightness_6_outlined,
    SceneControlType.colorSlider => Icons.palette_outlined,
  };

  static String _titleFor(SceneCustomControl control) =>
      control.label ??
      switch (control.type) {
        SceneControlType.toggle => 'Живлення',
        SceneControlType.brightnessSlider => 'Яскравість',
        SceneControlType.colorSlider => 'Колір',
      };

  static String _bindingWord(int count) => switch (count) {
    1 => 'binding',
    _ => 'bindings',
  };
}

class _SceneTargetPicker extends StatefulWidget {
  const _SceneTargetPicker({
    required this.options,
    required this.initialTargets,
  });

  final List<SceneTargetOption> options;
  final List<SceneTargetReference> initialTargets;

  @override
  State<_SceneTargetPicker> createState() => _SceneTargetPickerState();
}

class _SceneTargetPickerState extends State<_SceneTargetPicker> {
  late Set<SceneTargetReference> _selected;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialTargets.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Цілі Scene'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (widget.options.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: Text('Поки що немає знайдених груп або девайсів.'),
                )
              else
                ...widget.options.map((option) {
                  final selected = _selected.contains(option.reference);
                  return CheckboxListTile(
                    key: Key(
                      'select-scene-target-${option.reference.type.name}-${option.reference.targetId}',
                    ),
                    contentPadding: EdgeInsets.zero,
                    value: selected,
                    title: Text(option.name),
                    subtitle: Text(
                      '${option.kindLabel} · ${option.availabilityLabel}',
                    ),
                    onChanged: (value) {
                      setState(() {
                        if (value ?? false) {
                          _selected.add(option.reference);
                        } else {
                          _selected.remove(option.reference);
                        }
                      });
                    },
                  );
                }),
            ],
          ),
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Скасувати'),
        ),
        FilledButton(
          onPressed: () {
            final ordered = <SceneTargetReference>[
              ...widget.initialTargets.where(_selected.contains),
              ...widget.options
                  .map((option) => option.reference)
                  .where(
                    (reference) =>
                        _selected.contains(reference) &&
                        !widget.initialTargets.contains(reference),
                  ),
            ];
            Navigator.of(context).pop(ordered);
          },
          child: const Text('Готово'),
        ),
      ],
    );
  }
}

class _EmptyTargetList extends StatelessWidget {
  const _EmptyTargetList();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('Додайте хоча б одну групу або девайс.'),
      ),
    );
  }
}

class _EmptySlotList extends StatelessWidget {
  const _EmptySlotList();

  @override
  Widget build(BuildContext context) {
    return const Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Text('Додайте слот, щоб створити перший custom контрол.'),
      ),
    );
  }
}

class _SettingsError extends StatelessWidget {
  const _SettingsError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      color: Theme.of(context).colorScheme.errorContainer,
      child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
    );
  }
}
