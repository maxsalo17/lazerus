# BLE Protocol Profiles

## Validation policy

This document tracks protocol claims by evidence, not by source-code presence.
A reference implementation can inform an adapter, but its commands become
supported Lazerus capabilities only after physical validation on the relevant
controller/firmware profile.

| Evidence level | Meaning | Ordinary UI behavior |
| --- | --- | --- |
| `verified` | Physically tested and recorded for the device/profile. | May present the capability. |
| `inferred` | Derived from a reference implementation or reverse engineering. | Do not present it in ordinary controls until it is validated for the active device profile. |
| `unsupported` | Absent, incompatible, or intentionally not implemented. | Do not present the capability. |

## Lotus Lamp X / ELK initial profile

**Adapter ID:** `lazerus.protocol.lotus_lamp_x`  
**Transport:** BLE only  
**Status:** adapter and codec implemented; basic command delivery reported on
two locally tested strips, with broader profile validation pending.

The profile is based on the public
[LotusLampX protocol module](https://github.com/l0lsec/LotusLampX/blob/main/cli/protocol.py).
It is a reference, not a hardware-compatibility guarantee.

### Discovery and GATT mapping

| Item | Value | Evidence |
| --- | --- | --- |
| Name hints | `ELK*`, `MELK*` | Inferred from LotusLampX and the available ELK controller name. |
| Service | `0000FFF0-0000-1000-8000-00805F9B34FB` | Confirmed GATT mapping in the project specification. |
| Write characteristic | `0000FFF3-0000-1000-8000-00805F9B34FB` | Confirmed GATT mapping in the project specification. |
| Notify characteristic | `0000FFF4-0000-1000-8000-00805F9B34FB` | Confirmed GATT mapping in the project specification. |
| Service advertisement | Optional; do not filter only by FFF0. | Specification requirement. |

The adapter ranks a matching name plus FFF0 service as a strong candidate, a
matching name without an advertised service as a candidate, and FFF0 alone as
an ambiguous candidate. It never identifies a device solely by its platform
Bluetooth identifier.

### Implemented codec claims

`lazerus_proto_lotus_lamp_x` can encode the plain nine-byte E1 format inferred
from LotusLampX for these operations:

| Operation | Core command | Adapter evidence | Lazerus validation |
| --- | --- | --- | --- |
| Power | `SetPower` | Inferred | Reported working on the current two-strip setup; detailed record pending |
| Saturated red-to-violet color | `SetColor` | Inferred | Reported working on the current two-strip setup; detailed record pending |
| Brightness (normalized 0–1) | `SetBrightness` | Inferred | Reported working on the current two-strip setup; detailed record pending |
| Jump, strobe, breathe, warning | `SetNativeEffect` | Inferred | Pending |

The adapter can also encode an `ApplyLightingState` as a deterministic sequence:
when powering on, color and brightness precede power-on; when powering off, only
the off frame is sent. A future scheduler will own inter-command priority,
coalescing, rate limiting, and retries.

### App transport integration

`apps/lazerus_app` now provides a generic BLE transport implementation. It
scans without requiring FFF0 to be advertised, lets the adapter classify
ELK/MELK candidates, automatically connects matched candidates, discovers GATT
services after connection, and routes adapter frames to FFF3 by the adapter's
declared channel. The transport also forwards FFF4 (and any other enabled GATT
notification) as raw data. When FFF4 advertises the standard GATT `read`
property, the adapter can also request one value after connection or from the
local Logs screen; it never attempts arbitrary GATT reads from UI code.

The adapter records every inbound packet in the local Logs screen. It recognizes
only E1-shaped packets matching the currently encoded power, RGB, or brightness
commands and displays a partial `best-effort` observation for those packets.
All other payloads remain raw hexadecimal data. Neither case confirms that a
controller accepted a prior command or describes a documented FFF4 state
protocol; hardware validation is still required.

For the active application session, the Lotus adapter merges every successfully
accepted power, color, or brightness command into a partial protocol-side
`lastKnownState`. A recognized inbound E1 packet updates the same snapshot.
The app separately retains the desired colour, so a per-device calibration does
not make device UI display the adjusted transport colour. Neither snapshot
claims a physical readback. The session snapshot is in memory only and is
discarded when its protocol session closes.

The application displays the matching reason, connection state,
capability evidence, GATT-write result, and basic power/RGB/brightness actions.
The current control screens expose basic power/RGB/brightness operations after
the reported successful two-strip local test. The generic adapter capability
remains `inferred` until a reproducible device/firmware-specific record is
captured, so this is not a compatibility promise for future matches. Automated
integration is covered by mock transport tests; it is not a replacement for
physical-protocol validation.

For the current Lotus X control surface, the ordinary colour picker deliberately
emits only fully saturated colours on the red-to-violet arc. It does not offer
white or black as direct `SetColor` values. Macro HSV routing is separate: a
zero HSV Value produces a black RGB `ApplyLightingState` frame, which the user
has reported fully turns off the locally tested strips. It is deliberately not
translated to `SetBrightness(0)`, because that command leaves those strips
minimally lit. Drag updates are sampled at most once per 100 ms with replacement
of stale pending values; this is a local UI safeguard, not the centralized
scheduler required by the full specification.

Before each Lotus transport write, the active protocol session suppresses a
packet if its final E1 bytes duplicate the last emitted packet for that command
kind. It also has the initial, per-session `ProtocolCommandDelta` profile of
at most `2 / 255` normalized brightness and at most two units in every RGB
channel. A command within that profile returns `deduplicated` without an FFF3
write; power and native-effect frames require exact equality. These thresholds
are conservative engineering defaults for packet reduction, **not measured
hardware response claims**; validate and tune them for controller/firmware
profiles before treating them as visual-quality guarantees.

The app can optionally apply a manual, per-device hue curve to that same
red-to-violet command arc. It is a local, best-effort correction for nonlinear
strips, applied before this adapter encodes E1 RGB bytes. It does not modify
the inferred codec, prove an emitted colour, or invert FFF4 observations. The
curve behaviour and storage are documented in
[`COLOR_CALIBRATION.md`](COLOR_CALIBRATION.md); calibration accuracy remains
hardware validation work.

### Explicitly not supported yet

- Encrypted framing for ELK variants.
- Active GATT probing or capability interrogation.
- Validated semantic decoding of FFF4 notifications or reads. The existing
  E1-shaped decode is diagnostics-only and explicitly best-effort.
- Controller state confirmation or protocol acknowledgements.
- Complete device persistence/relinking, reconnect policy, or centralized
  command scheduling. The app has only a narrow local identity binding and
  per-device manual-control drag coalescer behind repositories; it is not the
  planned Drift/SQLite device database.
- Effect-speed, warm/cold-white, timers, sensors, reset, and any destructive
  command. Microphone capture exists for Macros, but physical capture and
  microphone-to-light validation remain pending.
- Measured maximum update rate, multi-device synchronization, or reconnect
  behavior.

The codec deliberately omits commands such as factory reset even though a
reference may contain them. Such behavior requires its own product decision,
safety treatment, and physical validation.

## Hardware-validation record

The user reported that two physical strips automatically connected and received
commands through the Lazerus app on 2026-10-23. This is evidence for the
current local setup, but the device model, firmware, operating system, exact
commands, and sustained rate were not captured. It must not be generalized to
all Lotus/ELK variants. A successful write without response is not by itself
evidence that a controller executed a command.

For each validation session, add a row with controller model/name, platform,
firmware if available, transport settings, command, expected state, observed
state, result, sustained rate, and notes. Do not record a device's platform
identifier, user location, or unrelated nearby-device data.

| Date | Device/profile | Operation | Result | Rate/notes |
| --- | --- | --- | --- | --- |
| 2026-10-23 | Two locally tested strips; model/firmware not recorded | Auto-connect and app lighting commands | User reported both devices received commands | Exact command set and sustained rate pending |
| 2026-10-24 | Two locally tested strips; model/firmware not recorded | Macro HSV Value `0` → black RGB `ApplyLightingState` | User reported both strips fully turned off | `SetBrightness(0)` instead leaves minimum visible light; no rate or firmware record |
