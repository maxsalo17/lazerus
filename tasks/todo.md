# Todo: per-device hue calibration

- [x] Define calibration model, mapper, JSON schema, and repository tests.
- [x] Wire profile resolver and preview override into command execution.
- [x] Build selection flow and calibration curve editor.
- [x] Document behaviour, persistence exception, and hardware validation gap.
- [x] Format, analyze, test, and build the affected Flutter targets.

## Scene control surfaces

- [x] Task 1: Typed Scene composition and local persistence
  - Acceptance: `Scene`, target references, stable control slots and typed
    bindings are versioned JSON values; a reference can point to a group or an
    application device ID; broken references remain detectable.
  - Verify: domain/repository tests plus `flutter test`.
  - Files: `features/scenes/domain/*`, `features/scenes/data/*`,
    `features/scenes/application/scenes_controller.dart`, focused tests.

- [x] Task 2: Scene Settings and custom-control editor
  - Acceptance: users can create/edit/delete a toggle, brightness slider or
    colour slider from empty/populated slots, assign several compatible
    group/device parameter bindings, and save the Scene locally.
  - Verify: widget tests for empty-slot, edit and delete flows; `flutter
    analyze` and `flutter test`.
  - Files: `features/scenes/presentation/scene_settings_page.dart`,
    `scene_control_editor_page.dart`, `scenes_page.dart`, app navigation and
    focused widget tests.

- [x] Task 3: Scene detail and runtime command binding
  - Acceptance: Scene detail shows custom controls above Groups and Devices;
    a control resolves/deduplicates real target devices, rechecks capabilities,
    reports unavailable bindings, and reuses ticker-based slider dispatch.
  - Verify: controller/widget tests, `flutter test`, `flutter analyze`, and
    `flutter build macos --debug`.
  - Files: `features/scenes/presentation/scene_detail_page.dart`, scene-control
    widgets/controller, lighting-control integration, diagnostics tests.

## Scene macros and trigger graph

- [x] Task 1: Macro contracts, validation and local JSON persistence
  - Acceptance: versioned macro graphs use typed ports and immutable values;
    `triggerMonoAudio` requires samples plus a non-null sample rate, while
    generic `triggerArray` has no audio metadata. Saved Scene macro references
    remain repairable when a macro is removed or unavailable.
  - Verify: core/app contract, JSON round-trip, graph-validation and
    file-persistence tests; `flutter analyze`, `flutter test`, and macOS debug
    build.
  - Files: `lazerus_core` macro contracts, macro repository, Scene reference
    models and focused tests.

- [x] Task 2: Macro runtime, registry and latest-wins lighting intent boundary
  - Acceptance: independently registered triggers/modifiers communicate only by
    typed ports; runtime validates and executes an acyclic graph; per-device
    pending macro updates are bounded and newer values supersede stale values.
    A transmitted write is not reported as a physically delivered command.
  - Verify: focused contract tests for typed runtime routing/registered-port
    conformance and per-device pending-value replacement; `flutter analyze`,
    `flutter test`, and macOS debug build.
  - Files: macro runtime/registry, trigger and modifier interfaces, lighting
    intent scheduler and diagnostics.

- [x] Task 3: Microphone and Multiband EQ trigger implementations
  - Acceptance: microphone produces `triggerMonoAudio`; Multiband EQ receives
    it without importing the microphone module, has configurable bands and
    threshold/range modes, and emits stable per-band gate/level ports.
  - Verify: focused contract tests for PCM-to-mono conversion, EQ typed ports
    and dynamic port-contract conformance; `flutter analyze`, `flutter test`,
    and macOS debug build. Real microphone/device/latency checks remain manual.
  - Files: independent microphone and multiband-EQ trigger modules, platform
    audio boundary and tests.

- [x] Task 4: Scene macro workflow and patcher editor
  - Acceptance: users save/select macros in Scenes, route node ports and bind
    outputs to device/group parameters; a desktop X/Y canvas supports
    drag-to-connect, while a touch-safe iOS presentation remains functional.
    The EQ displays a live spectrum and band configuration without making raw
    audio persistence claims.
  - Verify: controller/widget integration, broken-reference, binding and
    drag-to-connect tests; `flutter analyze`, `flutter test`, and macOS build.
  - Files: Scene macro pages/controllers, patcher canvas/widgets and
    diagnostics UI.
