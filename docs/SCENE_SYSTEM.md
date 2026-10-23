# Spec: Scene control surfaces

## Objective

Introduce a user-configurable Scene as a composition of existing groups and
individual devices, including targets from different protocol families. A Scene
gives the user one compact control surface: custom controls appear first, then
the referenced groups and standalone devices appear as normal compact cards.

The first slice focuses on composition and manually operated custom controls.
It is not yet the full Scene runtime described in
[`TECHNICAL_SPECIFICATIONS.md`](TECHNICAL_SPECIFICATIONS.md): activation
priorities, stored output states, presets, pipelines, transitions, import/export
and deactivation policies remain later work. This scope preserves the required
arbitration order rather than introducing an undocumented competing writer.

## Delivery status

**Tasks 1, 2 and 3 are complete.** The app has immutable Scene composition
models, schema-versioned local JSON persistence, CRUD, live reference
resolution, a Scene library, Scene detail, and Settings/control-editor
workflows. The resolver keeps references whose group or device is currently
absent visible as `pending` or `unavailable`; it never mutates saved Scene JSON
to hide them.

Settings creates Scenes with stable empty slots, lets users select group/device
targets, create or edit a toggle, brightness slider or colour slider, and clear
an existing control while retaining its empty slot. The editor only offers a
parameter when every current target member reports support for it. It treats
RGB as the current common colour domain; RGBW/CCT need an explicit mapping.

Scene detail puts custom controls above its Groups and Devices sections. A
control expands all of its current bindings to one deduplicated set of
application device IDs, then sends the ordinary typed command through a narrow
Scene command boundary backed by `LightingControlsController`. The expansion
runs both when the gesture begins and immediately before a ticker emission, so
a changed connection, group membership, rediscovery/relink or capability cannot
become a stale transport target. Sliders use a replaceable 10 Hz ticker; a
release flushes the final value. Toggles send once.

Bindings that cannot participate remain visible on their control card, and
command failures are recorded in Logs. A transport write remains a request, not
proof that hardware applied the output.

### Terms

- **Scene target** — a reference to a group ID or an application device ID. A
  group remains dynamic: its current membership is resolved when rendering or
  dispatching, not copied into the Scene.
- **Custom control** — a user-created toggle, brightness slider, or colour
  slider placed in a stable Scene slot.
- **Binding** — a typed link from one custom control to one target parameter:
  `power`, `brightness`, or `color`. One control may have many bindings.
- **Resolved device set** — the unique application device IDs reached by all
  enabled bindings. It prevents a device that is both directly referenced and
  in a referenced group from receiving duplicate writes.

## Product behaviour

1. A Scene contains an ordered list of group references and standalone device
   references. It may mix protocol families.
2. Scene detail renders custom controls above **Groups** and **Devices**.
   Existing compact cards remain the source for per-target status and detailed
   controls.
3. Scene Settings shows stable empty or populated custom-control slots. Tapping
   an empty slot creates a control; tapping an existing slot edits or deletes
   it.
4. In the control editor, the user chooses a control type, an optional label,
   then one or more bindings from targets already in the Scene. The picker
   filters choices by the target's currently available capability.
5. A control value dispatches the ordinary typed lighting command through the
   existing lighting controller. Sliders reuse the app's replaceable 10 Hz
   ticker contract; toggles send one command. No widget talks to BLE directly.
6. At dispatch time capability and connection checks run again. Missing targets,
   unavailable capabilities, and failed commands are surfaced as Scene status
   rather than treated as successful control.

For a colour control, a binding is available only when the resolved target
supports the common colour capability and its colour domain can represent the
selected value. The current Lotus X domain is saturated red-to-violet. Future
RGBW/CCT adapters must expose an explicit compatible mapping; a generic Scene
control must not silently approximate a colour model.

Per-device colour calibration stays below Scenes: Scene controls express the
desired colour, then each device's calibration maps it before protocol
encoding.

## Tech stack and commands

The implementation stays in Flutter/Dart, Riverpod, `lazerus_core`, and the
existing app-local versioned JSON repository pattern (`SharedPreferences`). No
new dependency or SQLite database is required for this slice.

```sh
cd apps/lazerus_app
flutter analyze
flutter test
flutter build macos --debug
```

## Project structure

```text
apps/lazerus_app/lib/features/scenes/
  domain/          # immutable Scene, target reference, control and binding models
  data/            # versioned local JSON repository
  application/     # CRUD, validation, target/capability resolution
  presentation/    # Scene library, Settings and control-editor pages

apps/lazerus_app/test/features/scenes/
  domain/ data/ application/ presentation/
```

`features/scenes` may depend on public group, control and debug-device
contracts. It must not depend on BLE SDKs or a protocol package. Group and
device IDs remain references; Scene persistence must retain broken references
so a rediscovered device or recreated group can be repaired.

## Code style

Scene contracts use immutable typed values. Bindings identify intent without
storing protocol frames or copying mutable device membership:

```dart
final class SceneControlBinding {
  const SceneControlBinding({
    required this.target,
    required this.parameter,
  });

  final SceneTargetReference target;
  final SceneParameter parameter;
}
```

The delivered Settings flow resolves a Scene's group and device references
against current app state without changing saved data. It filters new bindings
using current common capabilities, but does not communicate with BLE. The
delivered runtime controller rechecks capabilities and connection state at
dispatch time, deduplicates compatible live device IDs, and delegates through
`LightingControlsController`; presentation widgets only render controller state
and issue typed requests.

## Testing strategy

- The Task 1 tests cover JSON schema validation, stable slot ordering, invalid
  bindings, a fresh-repository persistence round trip, controller CRUD and
  available/unavailable reference reporting.
- The Task 2 tests cover all-member capability filtering plus the widget flow
  for adding a control to an empty slot, editing it and clearing it back to the
  same empty slot.
- Task 3 application tests cover duplicate-device deduplication, unavailable
  connection/capability reporting, final-value slider coalescing and a live
  connection recheck before ticker dispatch.
- Task 2 and Task 3 widget tests cover Scene Settings empty/add/edit/delete
  flows and Scene detail order: custom controls, Groups, Devices. The Scene
  detail test also verifies a multi-binding toggle dispatches one target set.
- Run the commands above. Real-device validation is still required for each
  cross-protocol control combination and must not claim atomic BLE delivery.

## Boundaries

- **Always:** use application UUIDs and saved group IDs; derive live group
  membership; deduplicate resolved device IDs; revalidate capabilities at
  dispatch; retain unresolvable references visibly; keep desired, transport and
  observed state distinct.
- **Ask first:** adding a new control type, a cross-colour-domain mapping,
  automatic Scene activation/deactivation, persistence migration away from
  local JSON, or a change to global arbitration priority.
- **Never:** persist BLE identifiers as Scene identity, embed raw protocol
  commands in Scene models, send BLE commands from widgets, silently drop a
  target that a user believes was controlled, or claim a write was applied by
  hardware.

## Success criteria

1. Users can create and persist a Scene that references both groups and direct
   devices across protocol families.
2. Users can create, edit and delete a slotted custom toggle, brightness slider
   or colour slider, each with multiple valid bindings.
3. Scene detail has custom controls above separate Groups and Devices sections.
4. Binding dispatch is capability-aware, deduplicated per actual device and
   uses the existing command/ticker boundary.
5. Unavailable references or capabilities remain visible and repairable.

## Open questions for the later full Scene runtime

- Should a manually controlled Scene become an active arbitration source, or
  should activation be a separate user action with an explicit deactivation
  policy?
- What layout capacity and ordering controls should replace the initial stable
  slot list once users need more controls?
- Which colour-domain mappings, if any, are acceptable between RGB, RGBW and
  CCT protocol families?
