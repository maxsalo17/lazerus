# Spec: portable Macro templates

## Objective

Enable a user to export a saved Macro as a portable JSON template and import it
as a new Macro. Every `sink.lighting_target` device reference in the exported
template must be replaced by a template-local placeholder; neither application
device IDs nor user-defined device names may be exported. After import, the
graph remains visible. Unmapped placeholders are skipped at runtime, while
other mapped targets continue to run until the user selects a compatible device
for each placeholder on the patcher canvas.

Success means that one Macro can be moved to another Lazerus installation
without implicitly controlling a device there, while graph topology, node
configuration, ports, edges, editor positions and `resetOnStop` survive the
round trip.

## Tech stack

- Flutter/Dart application in `apps/lazerus_app`.
- Immutable, versioned `MacroGraph` contracts in `packages/lazerus_core`.
- Local JSON Macro persistence behind `MacroRepository`.
- Riverpod controllers and feature-first Macro UI.
- Import uses the platform file-selection UI for `.json` documents.
- On macOS, export opens the native Save As dialog with a suggested
  `<macro-name>.json` filename. The template is written only after the user
  chooses the destination; cancelling leaves the macro library unchanged. The
  export action is disabled on platforms without this Save As capability.

## Commands

```sh
cd apps/lazerus_app
flutter analyze
flutter test test/core/macros/templates/macro_template_transformer_test.dart
flutter test test/features/macros/application/macro_template_transfer_controller_test.dart
flutter test test/features/macros/application/macro_template_runtime_guard_test.dart
flutter test test/features/macros/presentation/macro_library_template_actions_test.dart
flutter test test/features/macros/presentation/node_modules/lighting_target_macro_editor_node_module_test.dart
flutter test
```

## Project structure

```text
apps/lazerus_app/lib/core/macros/templates/
  macro_template.dart             # Versioned template model and JSON codec
  macro_template_transformer.dart # Export sanitisation and import conversion
apps/lazerus_app/lib/features/macros/
  application/                    # Import/export orchestration
  presentation/                   # Library actions and placeholder repair UI
apps/lazerus_app/test/core/macros/templates/
apps/lazerus_app/test/features/macros/
docs/MACRO_TEMPLATES.md
```

## Template contract

`MacroTemplate` has its own `templateSchemaVersion` and contains a Macro graph
payload plus explicit placeholder metadata. Export generates a new template
placeholder ID for every lighting-target node and rewrites that node's
`targetId` and `displayName`. Its existing input parameters and ports remain
unchanged, so wires and bindings remain valid after a replacement target is
selected.

```dart
final template = MacroTemplate(
  name: macro.name,
  graph: sanitisedGraph,
  placeholders: <MacroTemplateDevicePlaceholder>[
    MacroTemplateDevicePlaceholder(
      id: 'template-device:1',
      nodeId: 'target-node',
      requiredParameters: <MacroTargetParameter>[
        MacroTargetParameter.brightness,
      ],
    ),
  ],
);
```

On import, Lazerus validates both template and graph schemas, gives the graph
a fresh Macro ID, retains the template name, and saves it as a new Macro. The
placeholder target IDs remain in the imported graph. At runtime, target
bindings for unresolved placeholders are excluded from the execution-only
graph; no command or device-resolution attempt is made for those targets.

Selecting a real device is a graph edit: the editor replaces only the selected
lighting-target node's `targetId` and display name, preserves its node ID and
ports, then re-derives bindings. The device picker lists only devices with a
loaded capability profile that supports every parameter represented by the
placeholder. It never guesses, silently maps, or changes a different target.

## Code style

Use immutable typed values, schema constants, `FormatException` for invalid
external JSON, and explicit names at boundary types. UI owns no persistence or
transport logic; it calls an application/controller boundary and checks
`mounted` after asynchronous work.

```dart
final imported = template.toMacroGraph(newMacroId: newId());
if (!mounted) return;
await ref.read(macroLibraryProvider.notifier).save(imported);
```

## Testing strategy

- Unit tests: JSON rejection, backward/future-version compatibility, device-ID
  sanitisation, fresh-ID import, and node replacement preserving wires.
- Controller/repository tests: import saves a distinct graph and reports parse
  or storage errors without changing the existing library.
- Widget tests: export/import controls, imported placeholder rendering, device
  picker filtering, explicit selection, and execution that skips unmapped
  placeholders.
- Run the full Flutter analyser and application test suite after focused tests.

## Boundaries

- Always: validate JSON and graph structure; preserve offline operation;
  retain unresolved placeholders visibly; re-check capabilities; add tests and
  documentation.
- The transfer boundary is implemented with the supported `file_selector`
  package. It remains user-mediated: the app neither writes to an arbitrary
  path nor reads a document without the platform picker.
- Never: export application/BLE device identifiers or user device names;
  auto-map a placeholder; emit a command for an unresolved placeholder; write
  raw GATT data.

## Success criteria

1. Export produces a versioned JSON template with no source-device identity or
   name.
2. Import creates a new saved Macro and preserves all non-device graph data.
3. Every imported lighting target is visibly a placeholder until explicitly
   mapped on the canvas.
4. The picker accepts only compatible, capability-known devices and retains
   wires/positions when mapping a placeholder.
5. Invalid, incompatible, or malformed templates leave the Macro library
   untouched and report a recoverable error.
6. Existing Macro JSON remains readable and unchanged by this feature.

## Import naming

An import retains the template name but always receives a newly generated Macro
ID. It is therefore distinct from the source Macro even when both exist on the
same installation.
