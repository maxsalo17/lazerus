import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../application/macro_library_controller.dart';
import '../application/macro_runtime_session_controller.dart';
import 'macro_editor_page.dart';

/// Reusable library of locally saved Scene Macro graph definitions.
///
/// Definitions live independently of Scenes. Deleting a definition never
/// rewrites a Scene: a selected Scene retains a visible, repairable reference.
class MacroLibraryPage extends ConsumerWidget {
  const MacroLibraryPage({super.key});

  /// Opens selection mode for a Scene Settings host.
  static Future<Iterable<SceneMacroReference>?> selectForScene(
    BuildContext context,
    List<SceneMacroReference> initialReferences,
  ) => Navigator.of(context).push<Iterable<SceneMacroReference>>(
    MaterialPageRoute<Iterable<SceneMacroReference>>(
      builder: (_) =>
          _MacroScenePickerPage(initialReferences: initialReferences),
    ),
  );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final library = ref.watch(macroLibraryProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Macros'),
        actions: <Widget>[
          IconButton(
            key: const Key('reload-macro-library'),
            tooltip: 'Оновити бібліотеку',
            onPressed: library.isLoading
                ? null
                : () => unawaited(
                    ref.read(macroLibraryProvider.notifier).reload(),
                  ),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const Key('create-macro'),
        heroTag: 'create-macro',
        onPressed: library.isLoading ? null : () => _openEditor(context),
        icon: const Icon(Icons.add),
        label: const Text('Створити macro'),
      ),
      body: library.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                const Text(
                  'Macros зберігаються локально як графи. Запуск показує лише стан runtime та transport write — не фізичне підтвердження стрічки.',
                ),
                const SizedBox(height: 16),
                if (library.error case final error? when error.isNotEmpty)
                  _MacroLibraryError(message: error),
                if (library.macros.isEmpty)
                  const _EmptyMacroLibrary()
                else
                  ...library.macros.map(
                    (macro) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _MacroTile(
                        macro: macro,
                        onOpen: () => _openEditor(context, macro: macro),
                        onDelete: () => _deleteMacro(context, ref, macro),
                      ),
                    ),
                  ),
                const SizedBox(height: 72),
              ],
            ),
    );
  }

  Future<void> _openEditor(BuildContext context, {MacroGraph? macro}) async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => MacroEditorPage(macro: macro)),
    );
  }

  Future<void> _deleteMacro(
    BuildContext context,
    WidgetRef ref,
    MacroGraph macro,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Видалити «${macro.name}»?'),
        content: const Text(
          'Scene не буде змінено: у ній залишиться посилання, яке можна буде відновити або прибрати вручну.',
        ),
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
    if (!context.mounted || confirmed != true) return;
    await ref.read(macroRuntimeSessionsProvider.notifier).stop(macro.id);
    await ref.read(macroLibraryProvider.notifier).delete(macro.id);
  }
}

class _MacroTile extends ConsumerWidget {
  const _MacroTile({
    required this.macro,
    required this.onOpen,
    required this.onDelete,
  });

  final MacroGraph macro;
  final VoidCallback onOpen;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(macroRuntimeSessionsProvider).statusFor(macro.id);
    final running = status?.lifecycle == MacroRuntimeSessionLifecycle.running;
    return Card(
      child: ListTile(
        key: ValueKey<String>('macro-${macro.id}'),
        leading: Icon(
          running ? Icons.graphic_eq : Icons.account_tree_outlined,
          color: running ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(macro.name),
        subtitle: Text(
          '${macro.nodes.length} вузли · ${macro.targetBindings.length} bindings'
          '${running ? ' · працює' : ''}',
        ),
        onTap: onOpen,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            IconButton(
              key: Key('delete-macro-${macro.id}'),
              tooltip: 'Видалити macro',
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}

class _MacroScenePickerPage extends ConsumerStatefulWidget {
  const _MacroScenePickerPage({required this.initialReferences});

  final List<SceneMacroReference> initialReferences;

  @override
  ConsumerState<_MacroScenePickerPage> createState() =>
      _MacroScenePickerPageState();
}

class _MacroScenePickerPageState extends ConsumerState<_MacroScenePickerPage> {
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _selectedIds = widget.initialReferences.map((item) => item.macroId).toSet();
  }

  @override
  Widget build(BuildContext context) {
    final library = ref.watch(macroLibraryProvider);
    final availableIds = library.macros.map((macro) => macro.id).toSet();
    final missing = _selectedIds.difference(availableIds);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Додати macros до Scene'),
        actions: <Widget>[
          TextButton(
            key: const Key('apply-scene-macro-selection'),
            onPressed: library.isLoading
                ? null
                : () => Navigator.of(context).pop(
                    _selectedIds
                        .map((id) => SceneMacroReference(macroId: id))
                        .toList(growable: false),
                  ),
            child: const Text('Готово'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        heroTag: 'create-macro-for-scene',
        onPressed: library.isLoading ? null : _createMacro,
        icon: const Icon(Icons.add),
        label: const Text('Новий macro'),
      ),
      body: library.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: <Widget>[
                if (missing.isNotEmpty) ...<Widget>[
                  const _MacroLibraryError(
                    message:
                        'Деякі раніше вибрані macros зараз відсутні. Вони залишаться у Scene, поки ви не приберете їх тут.',
                  ),
                  ...missing.map(
                    (id) => CheckboxListTile(
                      key: Key('scene-macro-missing-$id'),
                      value: true,
                      onChanged: (_) => setState(() => _selectedIds.remove(id)),
                      title: Text(id),
                      subtitle: const Text('Відсутній macro'),
                    ),
                  ),
                ],
                if (library.macros.isEmpty)
                  const _EmptyMacroLibrary()
                else
                  ...library.macros.map(
                    (macro) => CheckboxListTile(
                      key: Key('scene-macro-picker-${macro.id}'),
                      value: _selectedIds.contains(macro.id),
                      onChanged: (selected) => setState(() {
                        if (selected ?? false) {
                          _selectedIds.add(macro.id);
                        } else {
                          _selectedIds.remove(macro.id);
                        }
                      }),
                      title: Text(macro.name),
                      subtitle: Text(
                        '${macro.nodes.length} вузли · ${macro.targetBindings.length} bindings',
                      ),
                      secondary: IconButton(
                        tooltip: 'Відкрити editor',
                        onPressed: () => Navigator.of(context).push<void>(
                          MaterialPageRoute<void>(
                            builder: (_) => MacroEditorPage(macro: macro),
                          ),
                        ),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                    ),
                  ),
                const SizedBox(height: 72),
              ],
            ),
    );
  }

  Future<void> _createMacro() async {
    await Navigator.of(context).push<void>(
      MaterialPageRoute<void>(builder: (_) => const MacroEditorPage()),
    );
  }
}

class _EmptyMacroLibrary extends StatelessWidget {
  const _EmptyMacroLibrary();

  @override
  Widget build(BuildContext context) => const Card(
    child: Padding(
      padding: EdgeInsets.all(16),
      child: Column(
        children: <Widget>[
          Icon(Icons.account_tree_outlined, size: 42),
          SizedBox(height: 10),
          Text('Macros ще немає.'),
          SizedBox(height: 4),
          Text('Створіть граф і прив’яжіть його outputs до девайсів або груп.'),
        ],
      ),
    ),
  );
}

class _MacroLibraryError extends StatelessWidget {
  const _MacroLibraryError({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Card(
    color: Theme.of(context).colorScheme.errorContainer,
    child: Padding(padding: const EdgeInsets.all(12), child: Text(message)),
  );
}
