import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lazerus_core/lazerus_core.dart';
import 'package:uuid/uuid.dart';

import '../../../core/macros/templates/macro_template.dart';
import '../../../core/macros/templates/macro_template_file_gateway.dart';
import '../../../core/macros/templates/macro_template_transformer.dart';
import 'macro_library_controller.dart';

final macroTemplateFileGatewayProvider = Provider<MacroTemplateFileGateway>(
  (ref) => const SystemMacroTemplateFileGateway(),
);

final macroTemplateTransferProvider =
    NotifierProvider<
      MacroTemplateTransferController,
      MacroTemplateTransferState
    >(MacroTemplateTransferController.new);

enum MacroTemplateTransferOutcome { completed, cancelled, failed }

final class MacroTemplateImportResult {
  const MacroTemplateImportResult({required this.outcome, this.macro});

  final MacroTemplateTransferOutcome outcome;
  final MacroGraph? macro;
}

final class MacroTemplateTransferState {
  const MacroTemplateTransferState({
    this.isImporting = false,
    this.isExporting = false,
    this.error,
  });

  final bool isImporting;
  final bool isExporting;
  final String? error;

  bool get isBusy => isImporting || isExporting;

  MacroTemplateTransferState copyWith({
    bool? isImporting,
    bool? isExporting,
    String? error,
  }) => MacroTemplateTransferState(
    isImporting: isImporting ?? this.isImporting,
    isExporting: isExporting ?? this.isExporting,
    error: error,
  );
}

/// Coordinates validated, user-mediated Macro-template exchange.
///
/// It owns no widgets and does not mutate a source Macro. Import saves only a
/// freshly identified graph; invalid or cancelled documents leave the macro
/// library unchanged.
final class MacroTemplateTransferController
    extends Notifier<MacroTemplateTransferState> {
  static const _transformer = MacroTemplateTransformer();

  late final MacroTemplateFileGateway _files;
  var _disposed = false;

  @override
  MacroTemplateTransferState build() {
    _files = ref.watch(macroTemplateFileGatewayProvider);
    ref.onDispose(() => _disposed = true);
    return const MacroTemplateTransferState();
  }

  Future<MacroTemplateTransferOutcome> exportMacro(MacroGraph macro) async {
    if (state.isBusy) return MacroTemplateTransferOutcome.failed;
    if (!_files.supportsSaveAs) {
      _setState(
        const MacroTemplateTransferState(
          error: 'Save As для Macro template доступний лише на macOS.',
        ),
      );
      return MacroTemplateTransferOutcome.failed;
    }
    _setState(const MacroTemplateTransferState(isExporting: true));
    try {
      final template = _transformer.export(macro);
      final document = jsonEncode(template.toJson());
      final saved = await _files.saveTemplateDocument(
        document: document,
        suggestedFileName: _suggestedFileName(template.name),
      );
      _setState(const MacroTemplateTransferState());
      return saved
          ? MacroTemplateTransferOutcome.completed
          : MacroTemplateTransferOutcome.cancelled;
    } on Object catch (error) {
      _setState(
        MacroTemplateTransferState(
          error: 'Не вдалося експортувати Macro template: $error',
        ),
      );
      return MacroTemplateTransferOutcome.failed;
    }
  }

  Future<MacroTemplateImportResult> importMacro() async {
    if (state.isBusy) {
      return const MacroTemplateImportResult(
        outcome: MacroTemplateTransferOutcome.failed,
      );
    }
    _setState(const MacroTemplateTransferState(isImporting: true));
    try {
      final document = await _files.selectTemplateDocument();
      if (document == null) {
        _setState(const MacroTemplateTransferState());
        return const MacroTemplateImportResult(
          outcome: MacroTemplateTransferOutcome.cancelled,
        );
      }
      final template = MacroTemplate.fromJson(_decodeDocument(document));
      final imported = _transformer.importTemplate(
        template,
        newMacroId: const Uuid().v4(),
      );
      final saved = await ref
          .read(macroLibraryProvider.notifier)
          .save(imported);
      if (!saved) {
        throw StateError(
          ref.read(macroLibraryProvider).error ??
              'The macro library rejected the imported template.',
        );
      }
      _setState(const MacroTemplateTransferState());
      return MacroTemplateImportResult(
        outcome: MacroTemplateTransferOutcome.completed,
        macro: imported,
      );
    } on Object catch (error) {
      _setState(
        MacroTemplateTransferState(
          error: 'Не вдалося імпортувати Macro template: $error',
        ),
      );
      return const MacroTemplateImportResult(
        outcome: MacroTemplateTransferOutcome.failed,
      );
    }
  }

  void _setState(MacroTemplateTransferState next) {
    if (!_disposed) state = next;
  }

  Map<String, Object?> _decodeDocument(String document) {
    final decoded = jsonDecode(document);
    if (decoded is! Map) {
      throw const FormatException(
        'A Macro template must contain a JSON object.',
      );
    }
    final json = <String, Object?>{};
    for (final entry in decoded.entries) {
      if (entry.key is! String) {
        throw const FormatException('A Macro template has a non-string key.');
      }
      json[entry.key as String] = entry.value;
    }
    return json;
  }

  String _suggestedFileName(String name) {
    final normalized = name
        .trim()
        .replaceAll(RegExp(r'[^A-Za-z0-9_-]+'), '-')
        .replaceAll(RegExp(r'-+'), '-')
        .replaceAll(RegExp(r'^-|-$'), '');
    return '${normalized.isEmpty ? 'lazerus-macro' : normalized}.json';
  }
}
