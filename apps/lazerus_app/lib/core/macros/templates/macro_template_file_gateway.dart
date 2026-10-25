import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:file_selector/file_selector.dart';

/// Native user-mediated import/export boundary for Macro-template documents.
///
/// The application never chooses a destination itself. Import opens a system
/// picker; export opens the platform Save As dialog and writes only to the
/// location explicitly chosen there.
abstract interface class MacroTemplateFileGateway {
  /// Whether this platform provides the Save As flow required for export.
  bool get supportsSaveAs;

  Future<String?> selectTemplateDocument();

  /// Returns false when the user cancels the Save As dialog.
  Future<bool> saveTemplateDocument({
    required String document,
    required String suggestedFileName,
  });
}

class SystemMacroTemplateFileGateway implements MacroTemplateFileGateway {
  const SystemMacroTemplateFileGateway();

  static const _templateType = XTypeGroup(
    label: 'Lazerus Macro template',
    extensions: <String>['json'],
    mimeTypes: <String>['application/json'],
    uniformTypeIdentifiers: <String>['public.json'],
  );

  @override
  bool get supportsSaveAs => Platform.isMacOS;

  @override
  Future<String?> selectTemplateDocument() async {
    final selected = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[_templateType],
      confirmButtonText: 'Імпортувати',
    );
    return selected?.readAsString();
  }

  @override
  Future<bool> saveTemplateDocument({
    required String document,
    required String suggestedFileName,
  }) async {
    final fileName = suggestedFileName.endsWith('.json')
        ? suggestedFileName
        : '$suggestedFileName.json';
    final saveLocation = await getSaveLocation(
      acceptedTypeGroups: const <XTypeGroup>[_templateType],
      suggestedName: fileName,
      confirmButtonText: 'Зберегти',
      canCreateDirectories: true,
    );
    if (saveLocation == null) return false;
    final file = XFile.fromData(
      Uint8List.fromList(utf8.encode(document)),
      mimeType: 'application/json',
      name: fileName,
    );
    await file.saveTo(saveLocation.path);
    return true;
  }
}
