import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/macros/persistence/macro_repository.dart';
import '../../../core/macros/persistence/macro_file_storage.dart';

/// Persistence boundary for the reusable macro library.
///
/// Macro definitions are stored in the application-support directory, outside
/// the app bundle and independent of Scene documents. Tests can override this
/// provider with an [InMemoryMacroRepository].
final macroRepositoryProvider = FutureProvider<MacroRepository>((ref) async {
  final applicationSupportDirectory = await getApplicationSupportDirectory();
  final macroDirectory = Directory(
    '${applicationSupportDirectory.path}${Platform.pathSeparator}lazerus'
    '${Platform.pathSeparator}macros',
  );
  return FileMacroRepository(DirectoryMacroFileStorage(macroDirectory));
});

final macroLibraryProvider =
    NotifierProvider<MacroLibraryController, MacroLibraryState>(
      MacroLibraryController.new,
    );

/// The persisted macro definitions currently available to Scenes and editors.
///
/// An invalid graph remains in this collection: missing modules and stale
/// references are repairable saved configuration, not a reason to delete user
/// data during loading.
final class MacroLibraryState {
  const MacroLibraryState({
    this.isLoading = true,
    this.macros = const <MacroGraph>[],
    this.error,
  });

  final bool isLoading;
  final List<MacroGraph> macros;
  final String? error;

  MacroGraph? byId(String macroId) {
    for (final macro in macros) {
      if (macro.id == macroId) return macro;
    }
    return null;
  }

  MacroLibraryState copyWith({
    bool? isLoading,
    List<MacroGraph>? macros,
    String? error,
  }) => MacroLibraryState(
    isLoading: isLoading ?? this.isLoading,
    macros: macros ?? this.macros,
    error: error,
  );
}

/// Riverpod-managed CRUD access to persisted reusable macro graphs.
///
/// Save and delete do not inspect runtime validity. A graph can legitimately
/// be saved while a module is unavailable, then repaired after an app update;
/// [MacroRuntimeSessionController.start] performs validation immediately
/// before execution.
final class MacroLibraryController extends Notifier<MacroLibraryState> {
  MacroRepository? _repository;
  var _disposed = false;

  @override
  MacroLibraryState build() {
    ref.onDispose(() => _disposed = true);
    unawaited(_load());
    return const MacroLibraryState();
  }

  Future<bool> save(MacroGraph definition) async {
    if (state.isLoading) {
      _setError('Macros are still loading. Try again shortly.');
      return false;
    }
    final previous = state.macros;
    final next = <MacroGraph>[
      for (final macro in previous)
        if (macro.id != definition.id) macro,
      definition,
    ]..sort((left, right) => left.id.compareTo(right.id));
    state = MacroLibraryState(
      isLoading: false,
      macros: List<MacroGraph>.unmodifiable(next),
    );
    try {
      await _getRepository().then((repository) => repository.save(definition));
      return true;
    } on Object catch (error) {
      if (!_disposed) {
        state = MacroLibraryState(
          isLoading: false,
          macros: previous,
          error: 'Could not save macro: $error',
        );
      }
      return false;
    }
  }

  Future<bool> delete(String macroId) async {
    if (state.isLoading) {
      _setError('Macros are still loading. Try again shortly.');
      return false;
    }
    if (state.byId(macroId) == null) {
      _setError('The macro no longer exists.');
      return false;
    }
    final previous = state.macros;
    final next = previous
        .where((macro) => macro.id != macroId)
        .toList(growable: false);
    state = MacroLibraryState(
      isLoading: false,
      macros: List<MacroGraph>.unmodifiable(next),
    );
    try {
      await _getRepository().then((repository) => repository.delete(macroId));
      return true;
    } on Object catch (error) {
      if (!_disposed) {
        state = MacroLibraryState(
          isLoading: false,
          macros: previous,
          error: 'Could not delete macro: $error',
        );
      }
      return false;
    }
  }

  Future<void> reload() => _load();

  Future<void> _load() async {
    try {
      final macros = await _getRepository().then(
        (repository) => repository.load(),
      );
      if (!_disposed) {
        state = MacroLibraryState(isLoading: false, macros: macros);
      }
    } on Object catch (error) {
      if (!_disposed) {
        state = MacroLibraryState(
          isLoading: false,
          error: 'Could not load macros: $error',
        );
      }
    }
  }

  void _setError(String error) {
    if (!_disposed) state = state.copyWith(error: error);
  }

  Future<MacroRepository> _getRepository() async {
    final current = _repository;
    if (current != null) return current;
    final repository = await ref.read(macroRepositoryProvider.future);
    _repository = repository;
    return repository;
  }
}
