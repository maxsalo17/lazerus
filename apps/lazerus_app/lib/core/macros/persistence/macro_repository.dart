import 'dart:convert';

import 'package:lazerus_core/lazerus_core.dart';

import 'macro_file_storage.dart';

/// Persists reusable Scene Macro graphs independently from Scene documents.
///
/// A Scene keeps only a [SceneMacroReference]; removing or corrupting a macro
/// file therefore cannot silently rewrite the Scene that selected it.
abstract interface class MacroRepository {
  Future<List<MacroGraph>> load();

  Future<void> save(MacroGraph macro);

  /// Deletes only the macro definition. Scene references are intentionally
  /// retained by their separate repository and become repairable missing
  /// references instead of being silently rewritten.
  Future<void> delete(String macroId);
}

class FileMacroRepository implements MacroRepository {
  FileMacroRepository(this._storage);

  final MacroFileStorage _storage;

  @override
  Future<List<MacroGraph>> load() async {
    final documents = await _storage.readAll();
    final macros = <MacroGraph>[];
    for (final entry in documents.entries) {
      final macro = _decode(entry.value);
      if (macro != null && macro.id == entry.key) {
        macros.add(macro);
      }
    }
    macros.sort((left, right) => left.id.compareTo(right.id));
    return List<MacroGraph>.unmodifiable(macros);
  }

  @override
  Future<void> save(MacroGraph macro) {
    return _storage.write(
      macroId: macro.id,
      document: jsonEncode(macro.toJson()),
    );
  }

  @override
  Future<void> delete(String macroId) => _storage.delete(macroId);

  static MacroGraph? _decode(String document) {
    try {
      final decoded = jsonDecode(document);
      if (decoded is! Map<Object?, Object?>) {
        return null;
      }
      return MacroGraph.fromJson(Map<String, Object?>.from(decoded));
    } on Object {
      return null;
    }
  }
}

/// Lightweight macro repository fake. It preserves the same replacement and
/// load ordering behavior as [FileMacroRepository] without file I/O.
class InMemoryMacroRepository implements MacroRepository {
  InMemoryMacroRepository([Iterable<MacroGraph> macros = const <MacroGraph>[]])
    : _macros = <String, MacroGraph>{
        for (final macro in macros) macro.id: macro,
      };

  final Map<String, MacroGraph> _macros;

  @override
  Future<List<MacroGraph>> load() async {
    final macros = _macros.values.toList()
      ..sort((left, right) => left.id.compareTo(right.id));
    return List<MacroGraph>.unmodifiable(macros);
  }

  @override
  Future<void> save(MacroGraph macro) async {
    _macros[macro.id] = macro;
  }

  @override
  Future<void> delete(String macroId) async {
    _macros.remove(macroId);
  }
}
