import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';

import '../application/macro_library_controller.dart';
import '../application/macro_runtime_session_controller.dart';
import 'macro_editor_page.dart';

/// Library of locally saved Macro graph definitions.
class MacroLibraryPage extends ConsumerWidget {
  const MacroLibraryPage({super.key});

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
                  'Macros зберігаються локально як графи. Запуск показує стан runtime та transport write, а не фізичне підтвердження стрічки.',
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
        content: const Text('Цей macro і його runtime буде зупинено.'),
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
          Text('Створіть граф і прив’яжіть його outputs до девайсів.'),
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
