import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lazerus_core/lazerus_core.dart';

/// Availability supplied by the host that owns the macro repository.
///
/// Scene persistence deliberately stores only [SceneMacroReference] values.
/// This keeps a deleted or unreadable macro reference visible for repair,
/// rather than silently removing it from a Scene.
enum SceneMacroReferenceStatus { available, missing, unknown }

class SceneMacroReferenceResolution {
  const SceneMacroReferenceResolution({
    required this.status,
    this.label,
    this.detail,
  });

  final SceneMacroReferenceStatus status;

  /// A human-readable macro name, when the host can resolve one.
  final String? label;

  /// Optional explanation, especially useful for a missing reference.
  final String? detail;
}

/// Resolves a saved reference without coupling Scene UI to a macro repository.
typedef SceneMacroReferenceResolver =
    FutureOr<SceneMacroReferenceResolution> Function(
      SceneMacroReference reference,
    );

/// Opens host-owned macro selection or editing UI and returns the complete,
/// replacement list of references. Return `null` when the user cancels.
typedef SceneMacroReferencesEditor =
    Future<Iterable<SceneMacroReference>?> Function(
      BuildContext context,
      List<SceneMacroReference> initialReferences,
    );

const SceneMacroReferenceResolution unknownSceneMacroReference =
    SceneMacroReferenceResolution(status: SceneMacroReferenceStatus.unknown);
