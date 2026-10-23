# Lazerus

> Local, cross-platform lighting control for macOS and iOS — starting with
> Bluetooth Low Energy.

Lazerus is an offline-first Flutter application for controlling multiple LED
controllers as individual devices and synchronized logical groups. Bluetooth
Low Energy (BLE) is the first supported transport; the architecture separates
transport from the device protocol so future USB, Wi-Fi, HTTP, MQTT, or other
transports can be added without rewriting lighting, scene, or UI logic. It is
designed to grow from a few LED strips into an extensible lighting-control
platform with reusable presets, scenes, software-driven animations, and visual
automation pipelines.

The project does not require user accounts, a backend, cloud services, or an
internet connection during normal use.

## Project status

This repository contains the specification, two Flutter-compatible Dart
packages, and an iOS/macOS Flutter application with device, group, and control
screens.
The authoritative product requirements are in
[`docs/TECHNICAL_SPECIFICATIONS.md`](docs/TECHNICAL_SPECIFICATIONS.md).

The app performs a general BLE scan, classifies only endpoints matched by an
installed protocol adapter, and connects to those candidates automatically. It
discovers GATT characteristics dynamically and surfaces connection/error state.
Users can manually disconnect and reconnect devices, create local custom
groups, add members manually, and choose automatic inclusion of newly found
devices with a matching protocol. Immutable `Common` groups are derived from
the shared protocol family.

The first Lotus Lamp X controls provide power, a saturated red-to-violet colour
palette, and brightness. Drag controls use a bounded 10 Hz replaceable-command
ticker and flush their final value on release; they never generate black or
white Lotus X colour commands. Two physical strips were reported by the user as automatically
connected and responding to app commands on 2026-10-23. This validates the
current local setup, not universal compatibility with every controller or
firmware. A BLE write receipt is never presented as proof that a light changed.

The **Devices** screen also supports selecting same-protocol controllers for
per-device hue calibration. A local curve maps the colour selected in Lazerus
to the command hue for that strip, with live preview while an anchor is moved.
Calibration is never assigned to a group: group commands are corrected per
member and group cards keep showing the intended member colours. Details and
limitations are in [`docs/COLOR_CALIBRATION.md`](docs/COLOR_CALIBRATION.md).

Identity bindings and custom groups are stored locally. A complete structured
device database, relinking UI, reconnection policy, the central command
scheduler, scenes, pipelines, and macOS menu-bar controls are still pending.

## Packages

| Package | Responsibility | Status |
| --- | --- | --- |
| [`packages/lazerus_core`](packages/lazerus_core) | Transport, discovery, protocol-adapter, session, capability, command, and result contracts. | Implemented and tested |
| [`packages/lazerus_proto_lotus_lamp_x`](packages/lazerus_proto_lotus_lamp_x) | BLE discovery signals, inferred ELK/Lotus Lamp X E1 codec, capability profile, and adapter/session implementation. | Implemented; hardware validation pending |
| [`apps/lazerus_app`](apps/lazerus_app) | iOS/macOS Flutter surface with automatic BLE connection, device management, per-device hue calibration, protocol/common and custom groups, and compact/detail controls. | Implemented; broader hardware validation pending |

Run the app on macOS:

```sh
cd apps/lazerus_app
flutter pub get
flutter run -d macos
```

Run checks from the package or app directory:

```sh
flutter test
dart analyze
```

## What Lazerus will do

- Discover nearby BLE lighting controllers and connect without relying solely
  on advertised service UUIDs.
- Save devices locally, restore their configuration, reconnect when appropriate,
  and support relinking when a platform Bluetooth identifier changes.
- Control power, color, brightness, color temperature, and native effects when
  the connected device actually supports them.
- Organize one or more devices into groups with uniform, sequential,
  alternating, wave, mirrored, or independently mapped behavior.
- Apply reusable built-in and custom presets.
- Coordinate multi-device scenes with priorities, transitions, and explicit
  conflict handling.
- Run deterministic, app-driven animations without tying their calculations to
  BLE writes or Flutter widgets.
- Build, validate, save, import, export, and execute typed node-based lighting
  pipelines.
- Offer persistent macOS menu-bar quick controls and a touch-friendly iOS UI.
- Store all user data locally and provide portable, versioned JSON imports and
  backups.

## Platform scope

| Platform | Intended experience |
| --- | --- |
| macOS | Full Flutter desktop application, persistent menu-bar controls, long-lived eligible BLE connections, and continued operation after the main window is closed. |
| iOS | Native Flutter mobile application with device control, local configuration, lifecycle-aware BLE handling, and responsive touch UI. |

On iOS, app-streamed animations cannot be guaranteed while the application is
suspended or force-quit. Controller-native effects may continue independently,
but that behavior is device-specific. The product must communicate this
distinction clearly rather than promising unsupported background execution.

## Hardware, transport, and protocol approach

The first protocol family targeted is the ELK-series controller used by Lotus
Lantern applications. An `ELK-BLEDDM` controller has been discovered and
connected on macOS; its GATT service and write/notify characteristics are known.
That connection proves only the basic GATT mapping—not full compatibility with
every reverse-engineered command.

Each hardware family is isolated behind a protocol-adapter interface responsible
for recognition, capability declaration, command encoding, constraints, optional
notification decoding, and unsupported-operation handling. A transport driver
owns physical discovery, connection, and I/O; a protocol adapter tells that
transport how to identify and operate a compatible controller. Core lighting,
scene, animation, and UI logic must never depend on a particular controller
name, UUID, MAC address, protocol variant, or transport implementation.

The detailed contract model, discovery and selection sequence, capability
layers, persistence model, and extension path are documented in
[`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md).
The initial BLE profile and validation record are in
[`docs/BLE_PROTOCOLS.md`](docs/BLE_PROTOCOLS.md).

The current Flutter app also has a local, in-memory **Logs** screen for BLE
connection/command errors and inbound packets. Lotus E1-shaped FFF4 data may
be displayed as a best-effort observation when a supported packet is seen; it
is not a controller-confirmed state and must not be used as a compatibility or
execution claim.

While the app is running, protocol sessions merge accepted lighting commands
and recognized observations into local per-device state. Group and individual
cards share this state; group colour indicators render the known member colours
as a gradient. The command boundary keeps a calibrated transport colour
separate from the desired UI colour. Session state is not yet durable device
configuration; calibration profiles and their assignments are the narrow local
JSON-backed exception described below.

Protocol references for validation and research include:

- [LotusLampX](https://github.com/l0lsec/LotusLampX)
- [LED_UNION](https://github.com/chameleonbr/LED_UNION)
- [Lotus Lantern for Windows PC](https://github.com/razibit/Lotus-Lantern-for-Windows-PC)

These are reference implementations, not a substitute for testing on physical
hardware. Commands are considered supported only after the applicable controller
has been validated.

## Core architecture

```text
Flutter UI and feature controllers
              │
              ▼
Domain models, repositories, and state arbitration
              │
     ┌────────┴─────────┐
     ▼                  ▼
Animation/pipeline   BLE command scheduler
evaluation           (per-device serialized writes)
     │                  │
     └──── desired ─────┘
              │
              ▼
Protocol adapter registry → selected transport → LED controller
```

The architecture follows Clean Architecture and feature-first organization. It
uses strongly typed domain models, dependency injection, repositories, reactive
state management, and narrow platform boundaries.

Four states are intentionally separate:

- **Configuration state** — persisted user settings and definitions.
- **Desired state** — the lighting state selected by arbitration and animation.
- **Transport state** — commands queued or written to BLE.
- **Observed state** — device-reported state, when a controller supports it.

A successful write without response is transport success, not proof that a
physical controller applied the command.

## Lighting behavior and reliability

All software-driven devices share a monotonic logical clock, so their frames are
calculated from the same timestamp. BLE writes remain independent and are not
atomic across multiple devices; synchronization quality must be measured rather
than assumed.

The command scheduler keeps a serialized queue per device and handles frame
coalescing, duplicate elimination, rate limiting, prioritization, recovery, and
diagnostic metrics. New replaceable animation states supersede old unsent ones,
which prevents stale-frame backlogs. Initial experimental update targets are 10,
20, and 30 Hz; actual rates depend on hardware measurements.

When more than one source addresses a device, the desired state is resolved
deterministically in this order:

1. Manual temporary override
2. Active high-priority scene
3. Active pipeline
4. Active group mode
5. Device default

The system retains the winning source so the interface can explain a device's
current behavior. Native controller effects and app-streamed animations are
mutually exclusive for a given device.

## Data and privacy

All configuration lives on the device. The planned storage layer is a structured
local database (SQLite via Drift is the proposed option) with typed models,
schema migrations, transactions, referential integrity, and reactive access.
For the current, deliberately narrow per-device hue-calibration slice, the
user selected a versioned JSON document in the local settings store instead of
introducing SQLite. It is behind a repository and can be migrated later; see
[`docs/COLOR_CALIBRATION.md`](docs/COLOR_CALIBRATION.md).

Persisted data includes devices, capability profiles, groups and membership,
presets, scenes, pipelines, node configurations, preferences, overrides,
favorites, and connection/default-startup settings. Deleting or losing a device
must leave references detectable and repairable rather than silently corrupting
other saved configuration.

Imports and exports use versioned JSON packages. Hardware identifiers are not
portable between macOS and iOS, so imported configurations must allow devices to
be rediscovered and relinked.

## Delivery roadmap

1. **Foundation and BLE** — Flutter bootstrap, BLE abstraction, ELK adapter,
   discovery, persistent connections, controls, and diagnostics.
2. **Device management and persistence** — local database, saved devices,
   reconnection, capabilities, and settings.
3. **Groups and presets** — group controls, arbitration, built-in/custom
   presets, and favorites.
4. **Animation engine** — timeline, effects, scheduling, coalescing, rate
   limiting, synchronization, and metrics.
5. **Scenes** — assignments, transitions, activation/deactivation policy, and
   persistence.
6. **Pipeline engine** — typed graph models, validation, runtime, node library,
   persistence, and diagnostics.
7. **Visual pipeline editor** — canvas, node editing, undo/redo, preview, and
   import/export.
8. **macOS integration** — menu bar, close-to-background behavior, quick
   controls, launch at login, and lifecycle tests.
9. **Optimization and release** — stress/performance testing, error handling,
   backups, end-to-end checks, packaging, and documentation.

## Quality standards

Critical domain logic must have automated coverage, including color and
brightness calculations, animation evaluation, graph validation/execution,
arbitration, scheduling, protocol encoding, serialization, and database
migrations. BLE behavior must also be tested through mocked transports for
connection recovery, write ordering, missing characteristics, and dropped
frames.

Real-device validation remains mandatory for protocol compatibility, sustainable
write rate, connection stability, multiple-device behavior, and synchronization
accuracy. Do not describe hardware-dependent work as complete until it is
validated or explicitly recorded as pending.

## Planned documentation

As the implementation is added, these companion documents will be maintained:

- `docs/ARCHITECTURE.md`
- `docs/BLE_PROTOCOLS.md`
- `docs/DATA_MODELS.md`
- `docs/PIPELINE_ENGINE.md`
- `docs/SCENE_SYSTEM.md`
- `docs/PERFORMANCE.md`
- `docs/TESTING.md`
- `docs/ROADMAP.md`

See [`AGENTS.md`](AGENTS.md) for contributor and coding-agent implementation
rules.
