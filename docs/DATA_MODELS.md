# Data models

## Device identity and state

Each discovered controller has an application-generated device ID. Platform BLE
identifiers are mutable endpoint locators, not the persisted primary identity.
The local device-identity binding also keeps an optional user-defined name.
That label is distinct from the controller's advertised Bluetooth name, survives
rediscovery, and never changes its application ID or BLE binding.
The app keeps these categories distinct:

- **desired state** — the colour, brightness and power requested by a device
  page or macro;
- **transport state** — command state accepted, queued or written by the
  protocol session;
- **observed state** — best-effort protocol data, if the controller supports
  it; and
- **configuration** — durable metadata, calibration profile and macro graph.

None of the latter three categories proves a physical strip's output.

## Per-device hue calibration

The current local calibration document is intentionally small:

```text
DeviceCalibrationConfiguration (schemaVersion: 1)
  profiles: HueCalibrationProfile[]
  assignments: { applicationDeviceId: profileId }

HueCalibrationProfile
  id, name, protocolId
  hueStartDegrees, hueEndDegrees
  anchors: [{ input: 0..1, output: 0..1 }]
```

Anchors include fixed `(0, 0)` and `(1, 1)` endpoints. Inputs are strictly
increasing, outputs are non-decreasing, yielding a deterministic monotonic
piecewise-linear map from desired hue to command hue. The profile maps only
the selected device's outgoing colour command; desired UI colour stays
unchanged.

The document is stored as versioned JSON in local settings under
`lazerus.device_hue_calibrations.v1`. Invalid, malformed or unsupported JSON
is safely replaced by a typed empty configuration. This is a deliberate narrow
exception to the planned database and is isolated behind
`DeviceCalibrationRepository`.

## Macro graph persistence

`MacroGraph` is a separate, versioned JSON schema. It stores immutable graph
nodes, typed port identity, edges, direct-device target bindings, node
parameters, editor positions and `resetOnStop`. Parameter maps contain only
recursively frozen JSON values. `resetOnStop` defaults to `true` when absent so
legacy macro files retain their prior restoration behavior.

The initial port vocabulary is:

```text
triggerMonoAudio | triggerArray | triggerGate | triggerLevel | triggerHsv
```

`TriggerMonoAudioValue` always has a positive `sampleRateHz`.
`TriggerArrayValue` deliberately has no audio metadata. `TriggerHsvValue`
validates hue `0..360` and saturation/value `0..1`. Pure graph validation
rejects unknown nodes, incompatible connections, missing ports, invalid direct
device bindings and unrestricted cycles.

Each macro occupies one URI-encoded `*.json` file under the application-support
`lazerus/macros` directory, behind `MacroFileStorage`. Malformed individual
files do not erase other definitions; storage errors remain observable. Audio
buffers, events, spectrum values, runtime state, BLE identifiers and controller
confirmation are transient and never persisted.

`MacroLightingIntent` and its delivery status are runtime-only. A macro runtime
publishes them through the app delivery boundary; it never writes directly to a
transport. The input-only `sink.lighting_target` node stores one direct device
ID and capability-neutral input names. Its incoming graph edges derive the
saved `MacroTargetBinding` records.

Legacy JSON may contain the removed `targetKind` field. It is ignored during
read; a subsequent explicit save writes the device-only model. A legacy target
that cannot resolve to a current device stays visible as an unresolved target
and never emits a command.

## EQ node parameters

The multiband EQ persists only an ordered band configuration: stable band ID,
frequency range, gate/level mode, threshold/hysteresis or dBFS normalisation
range, smoothing and output-buffer duration. Configured ports are regenerated
from those stable IDs. PCM frames, spectral data and filter state remain
runtime-only.

See [`MACRO_SYSTEM.md`](MACRO_SYSTEM.md) for the macro architecture and
runtime/delivery rules, and [`COLOR_CALIBRATION.md`](COLOR_CALIBRATION.md) for
the editor and preview behaviour.
