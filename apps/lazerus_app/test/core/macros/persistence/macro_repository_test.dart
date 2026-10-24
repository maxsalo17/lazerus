import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lazerus_app/core/macros/persistence/macro_file_storage.dart';
import 'package:lazerus_app/core/macros/persistence/macro_repository.dart';
import 'package:lazerus_core/lazerus_core.dart';

void main() {
  test(
    'writes and reloads a URI-encoded macro file without path traversal',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lazerus_macro_repository_test_',
      );
      addTearDown(() async {
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      });
      final storage = DirectoryMacroFileStorage(directory);

      await storage.write(macroId: 'macro/with/slashes', document: 'first');
      await storage.write(macroId: 'macro/with/slashes', document: 'updated');
      await File(
        '${directory.path}${Platform.pathSeparator}%.json',
      ).writeAsString('invalid filename');

      expect(await storage.readAll(), <String, String>{
        'macro/with/slashes': 'updated',
      });
    },
  );

  test(
    'persists each versioned macro graph as its own JSON document',
    () async {
      final storage = InMemoryMacroFileStorage();
      final repository = FileMacroRepository(storage);
      final macro = _macro(id: 'macro-b', name: 'Bass');

      await repository.save(macro);

      final stored = await storage.readAll();
      final document = jsonDecode(stored['macro-b']!);
      final reloaded = await repository.load();

      expect(document, isA<Map<Object?, Object?>>());
      expect(
        (document as Map<Object?, Object?>)['schemaVersion'],
        currentMacroGraphSchemaVersion,
      );
      expect(reloaded, hasLength(1));
      expect(reloaded.single.id, macro.id);
      expect(reloaded.single.name, macro.name);
    },
  );

  test(
    'skips corrupt, incompatible and mismatched macro files on load',
    () async {
      final valid = _macro(id: 'valid', name: 'Valid');
      final mismatched = _macro(id: 'inside-id', name: 'Mismatched');
      final storage = InMemoryMacroFileStorage(<String, String>{
        'valid': jsonEncode(valid.toJson()),
        'broken': '{',
        'future': jsonEncode(<String, Object?>{
          ...valid.toJson(),
          'id': 'future',
          'schemaVersion': currentMacroGraphSchemaVersion + 1,
        }),
        'filename-id': jsonEncode(mismatched.toJson()),
      });

      final loaded = await FileMacroRepository(storage).load();

      expect(loaded.map((macro) => macro.id), orderedEquals(<String>['valid']));
    },
  );

  test(
    'reports a file boundary failure instead of hiding the macro library',
    () {
      expect(
        FileMacroRepository(_FailingMacroFileStorage()).load,
        throwsA(isA<FileSystemException>()),
      );
    },
  );

  test(
    'in-memory repository replaces a graph with the same stable id',
    () async {
      final repository = InMemoryMacroRepository(<MacroGraph>[
        _macro(id: 'macro', name: 'Original'),
      ]);

      await repository.save(_macro(id: 'macro', name: 'Updated'));

      final loaded = await repository.load();
      expect(loaded.single.name, 'Updated');
    },
  );
}

MacroGraph _macro({required String id, required String name}) => MacroGraph(
  id: id,
  name: name,
  nodes: const <MacroNode>[],
  edges: const <MacroEdge>[],
);

class _FailingMacroFileStorage implements MacroFileStorage {
  @override
  Future<Map<String, String>> readAll() async {
    throw const FileSystemException('Read failure');
  }

  @override
  Future<void> write({
    required String macroId,
    required String document,
  }) async {}

  @override
  Future<void> delete(String macroId) async {}
}
