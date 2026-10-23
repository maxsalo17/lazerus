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
version `1` as a local JSON value. Each `Scene` has ordered group/device
references and ordered custom-control slots. A control binds one typed parameter
(`power`, `brightness`, or `color`) to one or more references; its type fixes
the parameter it may bind. The model rejects duplicate targets, slots and
bindings, and retains an unresolved ID rather than removing a reference.

The model stores IDs and user layout only; it does not snapshot group
membership, platform BLE identifiers, raw protocol frames, current control
values, or controller-confirmed state. Scene Settings edits this composition;
Scene Detail resolves the references at command time into a transient,
deduplicated device target. That runtime target and dispatch status are never
persisted as confirmed device state.

See [`SCENE_SYSTEM.md`](SCENE_SYSTEM.md) for the contract, capability rules and
three-step implementation plan.
