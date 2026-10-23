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
