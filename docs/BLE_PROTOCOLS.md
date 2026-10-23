# BLE Protocol Profiles

## Validation policy

This document tracks protocol claims by evidence, not by source-code presence.
A reference implementation can inform an adapter, but its commands become
supported Lazerus capabilities only after physical validation on the relevant
controller/firmware profile.

| Evidence level | Meaning | Ordinary UI behavior |
| --- | --- | --- |
| `verified` | Physically tested and recorded for the device/profile. | May present the capability. |
| `inferred` | Derived from a reference implementation or reverse engineering. | Hide from normal controls; permit only an explicit diagnostic opt-in. |
| `unsupported` | Absent, incompatible, or intentionally not implemented. | Do not present the capability. |

## Lotus Lamp X / ELK initial profile

**Adapter ID:** `lazerus.protocol.lotus_lamp_x`  
**Transport:** BLE only  
**Status:** adapter and codec implemented; Lazerus hardware validation pending.

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
| Power | `SetPower` | Inferred | Pending |
| RGB color | `SetColor` | Inferred | Pending |
| Brightness (normalized 0–1) | `SetBrightness` | Inferred | Pending |
| Jump, strobe, breathe, warning | `SetNativeEffect` | Inferred | Pending |

The adapter can also encode an `ApplyLightingState` as a deterministic sequence:
when powering on, color and brightness precede power-on; when powering off, only
the off frame is sent. A future scheduler will own inter-command priority,
coalescing, rate limiting, and retries.

### Explicitly not supported yet

- Encrypted framing for ELK variants.
- Active GATT probing or capability interrogation.
- Semantic decoding of FFF4 notifications.
- Controller state confirmation or protocol acknowledgements.
- Effect-speed, warm/cold-white, scenes, microphone, timers, sensors, reset,
  and any destructive command.
- Measured maximum update rate, multi-device synchronization, or reconnect
  behavior.

The codec deliberately omits commands such as factory reset even though a
reference may contain them. Such behavior requires its own product decision,
safety treatment, and physical validation.

## Hardware-validation record

No Lazerus protocol-frame validation has been recorded yet. The existing
integration evidence is limited to discovery and successful connection of an
`ELK-BLEDDM` controller on macOS. A successful write without response is not
evidence that the controller executed a command.

For each validation session, add a row with controller model/name, platform,
firmware if available, transport settings, command, expected state, observed
state, result, sustained rate, and notes. Do not record a device's platform
identifier, user location, or unrelated nearby-device data.

| Date | Device/profile | Operation | Result | Rate/notes |
| --- | --- | --- | --- | --- |
| — | — | — | Pending physical validation | — |
