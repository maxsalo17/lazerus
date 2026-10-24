# Data models

## Current calibration persistence

The first persisted calibration model is intentionally small and local:

```text
DeviceCalibrationConfiguration (schemaVersion: 1)
  profiles: HueCalibrationProfile[]
  assignments: { applicationDeviceId: profileId }

HueCalibrationProfile
  id, name, protocolId
  hueStartDegrees, hueEndDegrees
  anchors: [{ input: 0..1, output: 0..1 }]
```

Anchors have fixed `(0, 0)` and `(1, 1)` endpoints, strictly increasing input,
and non-decreasing output. This produces a deterministic monotonic
piecewise-linear desired-hue to command-hue mapping. Device IDs are application
UUIDs; no BLE identifier is stored in the calibration document.

The complete document is a JSON string under
`lazerus.device_hue_calibrations.v1` in local `SharedPreferences`. Unknown,
malformed, or unsupported-version JSON is discarded safely. The repository
returns a typed empty configuration rather than passing untyped JSON into UI or
BLE code.

This is a user-approved exception to the future Drift/SQLite configuration
store described by the technical specification. It is versioned and isolated
behind `DeviceCalibrationRepository`, so a future migration can preserve the
domain/profile contract and assignment semantics.

## State separation

For a calibrated colour command, the app retains:

- desired `RgbColor`: selected by the user and rendered on device/group cards;
- transport `RgbColor`: the profile-mapped value handed to the protocol adapter;
- observed state: best-effort protocol data, if any.

The latter two are not confirmation of a strip's physical output. See
[`COLOR_CALIBRATION.md`](COLOR_CALIBRATION.md) for editing and preview rules.

## Scene model foundation

The delivered Scene foundation persists a `SceneConfiguration` root at schema
version `2` as a local JSON value. Version `1` documents migrate by supplying
an empty macro-reference list. Each `Scene` has ordered group/device references,
ordered custom-control slots and typed `SceneMacroReference` values. A control
binds one typed parameter (`power`, `brightness`, or `color`) to one or more
references; its type fixes the parameter it may bind. The model rejects
duplicate targets, slots, bindings and macro IDs, and retains an unresolved ID
rather than removing a reference.

The model stores IDs and user layout only; it does not snapshot group
membership, platform BLE identifiers, raw protocol frames, current control
values, or controller-confirmed state. Scene Settings edits this composition;
Scene Detail resolves the references at command time into a transient,
deduplicated device target. That runtime target and dispatch status are never
persisted as confirmed device state.

See [`SCENE_SYSTEM.md`](SCENE_SYSTEM.md) for the contract, capability rules and
three-step implementation plan.

## Scene Macro graph foundation

`MacroGraph` is a separate, versioned schema (`1`) for reusable macro
definitions. It owns immutable nodes, typed ports, graph edges, target bindings
and editor positions. Node parameter maps are recursively frozen and limited to
JSON values; transient trigger events, microphone buffers, device state and BLE
identifiers are not persisted.

The initial port vocabulary is `triggerMonoAudio`, `triggerArray`,
`triggerGate`, `triggerLevel` and `triggerHsv`. `TriggerMonoAudioValue` always
has a positive `sampleRateHz`; generic `TriggerArrayValue` deliberately has no
audio metadata; `TriggerHsvValue` validates hue `0..360` and saturation/value
`0..1`. Pure validation rejects incompatible connections, missing ports,
unavailable node kinds, invalid bindings and unrestricted cycles.

Each macro is an independently stored, URI-encoded `*.json` file behind
`MacroFileStorage`. A malformed individual document does not erase any Scene
reference, while filesystem I/O failures remain visible to the caller. This is
the user-directed local-file exception to the future Drift/SQLite store; the
file directory is supplied at the application composition root. The current
app writes these documents under its application-support `lazerus/macros`
directory; deleting a macro definition intentionally leaves any Scene
reference repairable. See [`SCENE_MACROS.md`](SCENE_MACROS.md) for module
boundaries and editor/runtime behavior.

`MacroLightingIntent` and delivery-status records are runtime-only values. A
macro runtime publishes these typed intents through the app delivery boundary;
it never persists transient events or writes directly to a transport. An
input-only `sink.lighting_target` node persists the selected target kind/ID and
capability-neutral input parameters; its incoming graph edges derive the saved
`MacroTargetBinding` records used by the runtime.

The initial Multiband EQ stores only an ordered `bands` configuration in its
macro node parameters: stable band ID, frequency range, gate/level mode,
threshold/hysteresis or normalisation range, smoothing and output interval.
The configured ports are regenerated from those stable IDs. PCM microphone
frames, spectral magnitudes and filter state remain transient runtime data.
