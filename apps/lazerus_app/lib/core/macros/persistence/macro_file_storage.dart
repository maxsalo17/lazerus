import 'dart:io';

/// Narrow file-system boundary for persisted Macro documents.
///
/// The composition root chooses the application-support directory. This keeps
/// platform directory discovery out of the macro repository and permits a
/// deterministic in-memory implementation in tests.
abstract interface class MacroFileStorage {
  Future<Map<String, String>> readAll();

  Future<void> write({required String macroId, required String document});

  /// Removes one macro document. A missing document is already absent and is
  /// not an error.
  Future<void> delete(String macroId);
}

/// Stores one versioned JSON document per macro in [directory].
///
/// Macro IDs are URI-encoded before becoming filenames, so an ID cannot escape
/// the configured directory through a path separator.
class DirectoryMacroFileStorage implements MacroFileStorage {
  DirectoryMacroFileStorage(this.directory);

  static const _extension = '.json';

  final Directory directory;

  @override
  Future<Map<String, String>> readAll() async {
    if (!await directory.exists()) {
      return <String, String>{};
    }
    final documents = <String, String>{};
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith(_extension)) {
        continue;
      }
      final filename = entity.uri.pathSegments.last;
      final encodedId = filename.substring(
        0,
        filename.length - _extension.length,
      );
      final macroId = _decodeMacroId(encodedId);
      if (macroId == null) {
        continue;
      }
      documents[macroId] = await entity.readAsString();
    }
    return documents;
  }

  @override
  Future<void> write({
    required String macroId,
    required String document,
  }) async {
    await directory.create(recursive: true);
    final filename = '${Uri.encodeComponent(macroId)}$_extension';
    final output = File('${directory.path}${Platform.pathSeparator}$filename');
    final temporary = File('${output.path}.tmp');
    await temporary.writeAsString(document, flush: true);
    await temporary.rename(output.path);
  }

  @override
  Future<void> delete(String macroId) async {
    final filename = '${Uri.encodeComponent(macroId)}$_extension';
    final output = File('${directory.path}${Platform.pathSeparator}$filename');
    if (await output.exists()) {
      await output.delete();
    }
  }

  String? _decodeMacroId(String encodedId) {
    try {
      final macroId = Uri.decodeComponent(encodedId);
      return macroId.trim().isEmpty ? null : macroId;
    } on Object {
      return null;
    }
  }
}

/// Deterministic storage fake for repository and controller tests.
class InMemoryMacroFileStorage implements MacroFileStorage {
  InMemoryMacroFileStorage([
    Map<String, String> documents = const <String, String>{},
  ]) : _documents = Map<String, String>.from(documents);

  final Map<String, String> _documents;

  @override
  Future<Map<String, String>> readAll() async =>
      Map<String, String>.unmodifiable(_documents);

  @override
  Future<void> write({
    required String macroId,
    required String document,
  }) async {
    _documents[macroId] = document;
  }

  @override
  Future<void> delete(String macroId) async {
    _documents.remove(macroId);
  }
}
