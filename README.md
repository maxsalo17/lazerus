# Lazerus

> Offline-first lighting control for macOS and iOS, beginning with Bluetooth
> Low Energy.

Lazerus is a Flutter application for discovering and controlling supported LED
controllers. BLE is the first transport, while transport selection remains
separate from device-protocol selection so USB, Wi-Fi, HTTP, MQTT and other
transports can be added without rewriting the lighting domain.

The app has no account, backend, cloud service or internet dependency during
ordinary use.

## Current product model

The application has three top-level areas:

- **Devices** — discovered compatible controllers, connection state, per-device
  calibration, and an individual device detail page with power, colour and
  brightness controls.
- **Macros** — saved typed patcher graphs that connect triggers and modifiers
  directly to device input nodes.
- **Logs** — local connection, protocol and command diagnostics.

Groups, Scenes and the separate Control screen have been intentionally removed.
There is no indirect macro target: a macro connects to a specific device node.
Manual control is available in that device's detail page; reactive control is
available in the Macro editor.

## Implemented behaviour

The app performs a general BLE scan, lets installed protocol adapters classify
endpoints, and automatically connects to unambiguous supported candidates. It
discovers GATT characteristics dynamically and exposes connection and error
state. A device can be disconnected and reconnected manually.

The first Lotus Lamp X profile provides power, a saturated red-to-violet colour
palette and brightness. Its normal device controls throttle drag updates with a
replaceable ticker. For macro-driven output, the delivery bridge accepts one
pending or in-flight write for a device and drops newer values until it settles;
this prevents a reactive animation from accumulating a delayed BLE queue.

Two physical strips were reported as automatically connected and responsive on
2026-10-23. That validates the local setup only; a transport write receipt does
not prove the controller applied a command or establish compatibility with a
different controller or firmware.

Per-device hue calibration is local and persistent. It maps the desired colour
to a device-specific command hue before protocol encoding. The UI keeps the
desired colour separate from the calibrated transport colour and from any
best-effort observed state.

## Macros

Macros are versioned, local JSON documents containing a typed directed graph,
node settings, direct-device target bindings and editor layout. The graph is
validated before run, is editable while running, and can be saved with
**Cmd+S**. **Reset on stop** is enabled by default and performs a best-effort
restoration of each device state the Macro changed; disabling it leaves the
last accepted Macro state active.

The current module library contains:

- microphone PCM mono input;
- multiband EQ with gate/level outputs, dBFS thresholds and bounded output
  buffering;
- HSV colour source, colour-plus-brightness and strobe modifiers; and
- input-only device nodes exposing only the capabilities currently supported
  by the selected device.

Macro implementations are isolated modules. Concrete trigger/modifier code
communicates solely through typed ports and is registered at one composition
root; the generic editor does not branch on node types. Details are in
[`docs/MACRO_SYSTEM.md`](docs/MACRO_SYSTEM.md).

## Packages

| Package | Responsibility | Status |
| --- | --- | --- |
| [`packages/lazerus_core`](packages/lazerus_core) | Transport, discovery, protocol-adapter, session, capability, command and macro contracts. | Implemented |
| [`packages/lazerus_proto_lotus_lamp_x`](packages/lazerus_proto_lotus_lamp_x) | BLE discovery signals, inferred Lotus Lamp X E1 codec, capability profile and adapter/session implementation. | Implemented; broader hardware validation pending |
| [`apps/lazerus_app`](apps/lazerus_app) | iOS/macOS Flutter app: device management, calibration, macros and diagnostics. | Implemented; broader hardware validation pending |

## Run and verify

Run the app on macOS:

```sh
cd apps/lazerus_app
flutter pub get
flutter run -d macos
```

Run focused checks in each relevant package:

```sh
flutter analyze
flutter test
```

## Architecture

```text
Flutter features and controllers
             │
             ▼
Macro runtime / device intent boundary
             │ common lighting commands
             ▼
Protocol adapter registry → selected transport → controller
```

Widgets do not write BLE data. A transport owns scanning, connection and I/O;
a protocol adapter recognizes compatible endpoints, declares capabilities and
encodes device-specific commands. Macro modules publish typed lighting intents
to the application delivery bridge instead of writing to a protocol session.

The four state categories remain separate:

- **Configuration** — persisted definitions and calibration profiles.
- **Desired** — requested lighting state.
- **Transport** — queued or written frames.
- **Observed** — best-effort device data when supported.

For the complete contract direction, see
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md). The hardware evidence record is
[`docs/BLE_PROTOCOLS.md`](docs/BLE_PROTOCOLS.md), and calibration behaviour is
[`docs/COLOR_CALIBRATION.md`](docs/COLOR_CALIBRATION.md).

## Documentation and product direction

[`docs/TECHNICAL_SPECIFICATIONS.md`](docs/TECHNICAL_SPECIFICATIONS.md) remains
the source document. Its original Group, Scene and separate-Control chapters
are explicitly superseded by the current direct-device/Macro product decision
recorded at the top of that document. They are retained there as historical
requirements context, not active implementation scope.

Protocol research references:

- [LotusLampX](https://github.com/l0lsec/LotusLampX)
- [LED_UNION](https://github.com/chameleonbr/LED_UNION)
- [Lotus Lantern for Windows PC](https://github.com/razibit/Lotus-Lantern-for-Windows-PC)

These are implementation references, not hardware-validation evidence.
