# Lazerus Architecture

## Status and scope

This document records the architecture decision that Lazerus separates
**device transport** from **device protocol**. It expands the transport and
protocol-adapter direction in
[`TECHNICAL_SPECIFICATIONS.md`](TECHNICAL_SPECIFICATIONS.md).

BLE is the only transport planned for the first delivery, and ELK-series/Lotus
Lantern controllers are the first protocol family. USB, Wi-Fi, HTTP, MQTT, and
other transports are extension points only: this document defines contracts so
they can be added later without changing lighting-domain, macro, pipeline, or
UI code. It does not claim that any of those future transports are implemented
or available.

## Design goals

- Keep application intent independent of how a controller is reached.
- Select a device protocol from its observed endpoint and a supported transport,
  rather than from a hard-coded name or identifier.
- Let common controls work consistently across protocol families while exposing
  optional capabilities safely.
- Make discovery, connection recovery, scheduling, and diagnostics explicit.
- Preserve persistent BLE sessions, bounded queues, deterministic lighting
  arbitration, and truthful hardware-state reporting.

## Terms

| Term | Meaning | Examples |
| --- | --- | --- |
| **Transport** | Physical or network path that discovers endpoints, establishes a session, moves messages, and emits lifecycle events. | BLE, USB, Wi-Fi socket, HTTP, MQTT |
| **Endpoint** | A transport-visible candidate before its lighting protocol is known. | BLE advertisement, USB device, configured HTTP base URL, MQTT device topic |
| **Protocol** | Device-family contract that recognizes an endpoint, describes the device, and converts shared lighting operations to/from device messages. | ELK / Lotus Lantern |
| **Adapter** | Implementation of one protocol for one or more compatible transports. | `ElkProtocolAdapter` over BLE |
| **Device session** | A protocol-aware, connected controller instance used by the scheduler. | An ELK controller connected through CoreBluetooth |
| **Capability** | A declared and bounded behavior the current device/session can support. | RGB, brightness range, native-effect list, maximum update rate |

One protocol may support several transports, and one transport may carry many
protocols. For example, an ELK family adapter could eventually support both BLE
and a network bridge without changing the public lighting commands. Conversely,
a BLE driver must not assume that every BLE endpoint uses the ELK protocol.

## Layering

```text
Features and Flutter UI
          │ intent, view state, diagnostics
          ▼
Lighting domain: configuration, arbitration, macros, pipelines, animation
          │ DesiredLightingState / LightingCommand
          ▼
Device runtime and command scheduler
          │ capability-aware commands; per-device ordering and coalescing
          ▼
Protocol adapter registry ──────── transport registry
          │ encodes/decodes                  │ discovers/connects/sends
          └──────────── protocol-aware device session ────────────┘
                                      │
                                      ▼
                               Physical controller
```

The lighting domain never imports a BLE, USB, HTTP, MQTT, or device-family
library. Features do not communicate with a transport or adapter directly.
Only the device runtime invokes a selected protocol-aware session, and only a
transport driver invokes platform or network APIs.

### Per-device colour calibration

Per-device colour calibration is an application-domain command transformation,
not a BLE transport feature and not a protocol-adapter special case. A profile
maps a resolved desired `RgbColor` to a device's supported command hue after
arbitration but immediately before `LightingDeviceSession.execute`. The adapter
therefore continues to encode an ordinary `SetColor`, and a future adapter can
declare different calibration dimensions without changing transport contracts.

The runtime retains the desired colour for UI state, while the protocol-side/observed state can contain the corrected
transport colour. Neither is a confirmed physical output. Calibration editing
uses a temporary resolver override and goes through the ordinary replaceable
lighting-command ticker; widgets never send raw GATT data. The current
typed/profile JSON model and its intentional local-storage exception are in
[`COLOR_CALIBRATION.md`](COLOR_CALIBRATION.md).

## Shared contracts

The following interfaces are implemented by `packages/lazerus_core`. Names can
evolve with an intentional compatibility decision, but their responsibilities
and separation must be retained.

### Transport contract

```dart
enum TransportKind { ble, usb, wifi, http, mqtt }

abstract interface class DeviceTransport {
  TransportKind get kind;
  TransportCapabilities get capabilities;

  Stream<TransportDiscoveryEvent> discover(DiscoveryRequest request);
  Future<TransportSession> connect(
    TransportEndpoint endpoint,
    ConnectionOptions options,
  );
}

abstract interface class TransportSession {
  TransportEndpoint get endpoint;
  Stream<TransportSessionEvent> get events;
  Stream<TransportMessage> get incomingMessages;

  Future<TransportReceipt> send(TransportMessage message);
  Future<TransportMessage?> read(String channel);
  Future<void> disconnect();
}
```

`discover` has transport-appropriate semantics. For BLE it starts a scan; for
USB it enumerates attachable devices; for HTTP it may use configured hosts or
local discovery; for MQTT it may derive candidates from an allowed topic or a
configured broker. It must not imply that every future transport can discover
devices without configuration or permissions.

`TransportEndpoint` contains only transport-level identity and non-secret
metadata. It may include BLE advertisement fields, USB vendor/product details,
or a configured network address, but it is never the application's permanent
device ID. `TransportReceipt` reports delivery at the transport layer; it is
not proof of physical execution.

`TransportCapabilities` describes the path rather than the light: supported
discovery modes, connection persistence, background/restoration constraints,
message size, delivery acknowledgements, notification and declared-channel read
support, and applicable platform limits. The BLE implementation must expose
actual CoreBluetooth/iOS limitations rather than concealing them behind a
generic interface.

### Protocol-adapter contract

```dart
abstract interface class LightingProtocolAdapter {
  String get id;
  int get selectionPriority;
  Set<TransportKind> get supportedTransports;

  ProtocolDiscoverySpec discoverySpecFor(TransportKind transport);
  ProtocolMatch match(TransportEndpoint endpoint);
  Future<ProtocolProbeResult> probe(
    TransportSession session,
    ProtocolProbeOptions options,
  );

  Future<LightingDeviceSession> openSession(
    TransportSession transportSession,
    ProtocolProbeResult probe,
  );
}

abstract interface class LightingDeviceSession {
  String get protocolAdapterId;
  DeviceCapabilities get capabilities;
  ProtocolCommandDelta get commandDelta;
  Stream<DeviceObservation> get observations;
  DesiredLightingState? get lastKnownState;

  Future<CommandResult> execute(LightingCommand command);
  Future<void> requestCurrentState();
  Future<void> close();
}
```

Adapters **participate** in discovery instead of owning a scanner. Each adapter
declares a `ProtocolDiscoverySpec` with transport filters and a safe optional
probe. The discovery coordinator combines all registered specs into one scan or
enumeration for each active transport, then asks adapters to classify each
endpoint. This avoids competing CoreBluetooth scans and extends cleanly to
other transports.

`match` is fast and non-invasive: it uses the endpoint metadata available before
connection and returns a confidence, reason, and whether a probe is needed. A
probe is allowed only when it is documented as safe for an unknown device; it
must be minimal, time-bounded, cancellable, and diagnostic-visible. The adapter
returns `unsupported` or `unverified` rather than guessing a command format.

`ProtocolAdapterRegistry` filters adapters by transport, then sorts candidates
by match confidence, explicit adapter priority, and adapter ID. It reports an
equal confidence/priority as ambiguous even though the ID provides a stable
ordering for diagnostics. The application must not choose an ambiguous device
silently for normal control.

## Package implementation

The repository currently contains these Flutter-compatible Dart packages:

```text
packages/
  lazerus_core/                # shared contracts and adapter registry
  lazerus_proto_lotus_lamp_x/  # initial BLE/ELK protocol adapter and E1 codec
```

`lazerus_core` contains no Flutter widgets, BLE-plugin calls, or platform API
calls. It is the only dependency of protocol adapters. Its models make endpoint
metadata, transport receipts, capabilities, observations, and command outcomes
explicit. Transport implementations depend on the same package rather than on
a protocol package.

`lazerus_proto_lotus_lamp_x` consumes those contracts. It does not implement
`BleTransport`; it accepts an already-connected `TransportSession` and sends
encoded messages to the specified write channel. This preserves the boundary
between protocol framing and CoreBluetooth/plugin integration.

`openSession` maps the generic transport session to the protocol's service,
characteristics, endpoints, handshake, encryption, and codec behavior. The
adapter owns device-specific message encoding and notification decoding; the
transport never branches on a lighting protocol.

### Common lighting-command contract

```dart
sealed class LightingCommand {}

final class SetPower extends LightingCommand {
  SetPower(this.enabled);
  final bool enabled;
}

final class SetColor extends LightingCommand {
  SetColor(this.color);
  final RgbColor color;
}

final class SetBrightness extends LightingCommand {
  SetBrightness(this.value);
  final double value;
}

final class SetNativeEffect extends LightingCommand {
  SetNativeEffect(this.effect);
  final DeviceEffect effect;
}

final class ApplyLightingState extends LightingCommand {
  ApplyLightingState(this.state);
  final DesiredLightingState state;
}
```

The first stable common operations are power, RGB color, brightness, and an
atomic-at-domain-level desired state. Color temperature, RGBW, CCT, segments,
addressable-pixel commands, effect speed, device-specific effects, or protocol
diagnostics belong in typed optional capabilities and command extensions. A
session must reject an unsupported command with a structured result; it must
never silently approximate a command unless the user-selected behavior and its
mapping are explicit.

`CommandResult` distinguishes at least these outcomes:

- rejected before sending because the capability, state, or connection is
  invalid;
- accepted/queued by the scheduler;
- deduplicated locally by the selected protocol because a final encoded packet
  is unchanged or its domain value falls within the profile's declared delta;
- sent at the transport layer;
- acknowledged by a transport or protocol when that acknowledgement exists;
- observed by the device when a reliable observation exists; and
- failed, timed out, superseded, or dropped according to scheduler policy.

Neither a BLE write without response nor a future MQTT/HTTP delivery receipt is
represented as a confirmed physical lighting state.

### Protocol write deltas and packet deduplication

Each `LightingDeviceSession` exposes an immutable `ProtocolCommandDelta`. It
defines only its own brightness and RGB threshold in shared domain units. The
protocol session applies that threshold after application-level calibration and
before transport I/O, then also compares final encoded packets byte-for-byte.
The byte comparison is mandatory: a codec may quantize two distinct domain
values into one identical frame. Power and native-effect operations stay exact
and are suppressed only if their encoded command is identical.

`deduplicated` means no transport message was written. It is a successful
local scheduling decision, distinct from `transmitted`, a hardware observation,
and an error. The application can retain its requested desired state while a
session retains the last state it actually emitted. Delta values are
profile-specific tuning inputs, never evidence of a controller's measured
physical response.

## Capability model

Capabilities have three layers:

1. **Common lighting capabilities** are stable domain concepts shared across
   adapters: power, brightness and its range, RGB/RGBW/CCT color models,
   color-temperature range, native effects and speed, segments, addressable
   pixels, notifications, and maximum sustainable update rate.
2. **Protocol-specific capabilities** are typed, namespaced extensions for
   behavior that has no portable equivalent. They include protocol constraints,
   encryption/handshake requirements, vendor modes, or special channel layouts.
   They must not leak into generic controls.
3. **Transport capabilities** describe the connection path and platform limits,
   not a lighting feature. For example: BLE write-without-response support,
   iOS restoration availability, USB attach notifications, HTTP request
   semantics, or MQTT subscription reliability.

`DeviceCapabilities` is produced after the adapter has matched and, where
needed, safely probed a connected endpoint. The UI renders only common controls
whose capabilities are present. Advanced adapter-specific controls live behind
an explicit protocol-aware surface and cannot affect unrelated device types.

Capabilities may change after reconnecting, firmware changes, or a new probe.
The runtime must refresh the profile, revalidate scheduled work, and make
unsupported saved macro/preset/pipeline operations visible and repairable.

## Discovery, selection, and connection flow

1. The `DeviceDiscoveryCoordinator` obtains discovery specs from registered
   protocol adapters for each enabled transport.
2. The `TransportRegistry` runs at most the appropriate shared discovery
   operation per transport and emits raw `TransportEndpoint` events.
3. The coordinator passes each endpoint to compatible adapters' `match`
   methods and presents known, ambiguous, and unknown candidates distinctly.
4. On a user request or controlled reconnection, the selected transport opens a
   `TransportSession`. The chosen adapter may perform its safe probe.
5. If the probe succeeds, the adapter opens a `LightingDeviceSession`, exposes
   capabilities, and the runtime assigns the saved or new application device
   identity.
6. The scheduler uses this session for all serialized, capability-aware writes
   until disconnect. Recovery repeats matching/relinking as needed.

No adapter wins merely because it has a familiar Bluetooth name. Use explicit
match confidence and stable adapter priority only to resolve an otherwise valid
tie. If identity remains ambiguous, let the user choose a diagnostic candidate
without exposing arbitrary write controls.

## Identity and persistence

Persist a `LightingDevice` with an application-generated UUID. It references:

```text
LightingDevice
 ├── appDeviceId                 # stable local identity
 ├── user metadata               # name, room, icon, preferences
 ├── protocolBinding             # adapter ID + versioned profile/metadata
 ├── transportBindings[]         # mutable endpoint locators per transport
 ├── capabilitySnapshot          # last known, refreshable
 ├── desired/default state
 └── presets, macros, and pipeline references
```

A transport binding is a rediscovery hint, not proof of universal identity.
For example, a CoreBluetooth identifier is valid only in its platform context;
an HTTP URL may be reconfigured; an MQTT topic can be remapped. Relinking must
be explicit, preserve references to the local application ID, and not silently
merge two physical devices.

Protocol definitions, capability snapshots, device/profile data, macros,
presets, and pipelines require versioned persistence and migrations. An import
may restore an adapter profile but must force relinking when its transport
binding cannot be trusted on the target platform.

## Runtime and scheduler responsibilities

The lighting engine, macro runtime, and pipeline runtime produce
`DesiredLightingState` values. The arbitration service resolves exactly one
winning source per device using the documented priority order. The selected
device session validates and encodes commands; the scheduler—not the adapter or
UI—owns these cross-protocol concerns:

- per-device ordering and write serialization;
- frame coalescing and duplicate elimination;
- rate limits based on both device and transport capabilities;
- priority and critical-operation ordering;
- connection-aware recovery and retry policy;
- bounded queues and stale replaceable-frame eviction; and
- transport, protocol, and scheduler diagnostics.

The implemented Macro output follows this same boundary. A macro
produces a typed lighting intent, never a direct transport write. For reactive
macro updates, each device accepts exactly one pending or in-flight write;
newer values are dropped until that write settles, rather than replacing it or
forming a backlog. A command reported as `transmitted` reaches only the
transport boundary, not a physical delivery claim. Concrete microphone/EQ/colour
modules, Macro library, patcher editor and explicit start/stop UI are
implemented. A macro binds directly to discovered device nodes; it has no
indirect target composition or separate activation surface.

The adapter may declare command constraints or a device-specific safe update
rate. It must not create an independent unbounded command queue. A scheduler
may use a common logical timestamp for multi-device frames, but it must never
claim atomic delivery across BLE or any other independent transport path.

## Current implementation boundary

The current implementation includes:

- shared transport/protocol/session/capability contracts and deterministic
  adapter selection;
- `LotusLampXProtocolAdapter` with BLE name/service discovery hints;
- plain E1 encoding for power, RGB color, brightness, and four native-effect
  IDs inferred from the public LotusLampX reference; and
- transport-session writes for the locally exercised basic profile, while
  broader Lotus/ELK capability claims remain `inferred`;
- `apps/lazerus_app`, an iOS/macOS Flutter application using Riverpod;
- `BluetoothLowEnergyTransport`, which waits for the native BLE adapter to
  reach `poweredOn` before the initial general scan, then owns connection,
  GATT discovery, characteristic selection by requested channel, bounded
  characteristic-write fragmentation, and transport receipts; and
- a device controller that combines adapter discovery signals, lists only
  unambiguous supported candidates, connects them automatically, and renders
  transport/protocol status plus guarded power, RGB, and brightness controls.
- a local application-device identity binding that keeps platform BLE IDs as
  mutable locators rather than persistent controller identifiers; and
- direct device controls on the device detail page plus macro device nodes for
  reactive control.

The app resolves GATT UUIDs at runtime. A platform BLE identifier remains only
an in-memory endpoint locator; it is not a saved Lazerus device identity.
`BluetoothLowEnergyTransport` enables declared GATT notifications and forwards
their raw payloads. It can read a declared GATT channel only when that
characteristic exposes the GATT `read` property. The Lotus adapter records raw
FFF4 data and recognizes E1-shaped power/RGB/brightness packets as
best-effort observations for the local Logs screen; no protocol currently
interprets those payloads as a confirmed lighting state.

Each active protocol session also keeps a partial `lastKnownState`: successful
transport writes merge into it, as do recognized protocol observations. The
app surface mirrors that local state per device. It is explicitly separate from
confirmed hardware state and is not yet stored in the planned device database.

The initial local device profile has been exercised successfully by the user on
two physical strips. The app therefore exposes basic power, color, and
brightness controls for the currently discovered profile. The generic adapter
still labels its wider Lotus/ELK capability claims as inferred until a
controller model, firmware, exact commands, and repeatable results are
recorded. `transmitted` and `acknowledged` mean only that the transport accepted
the frame or received a GATT response; neither means that the controller changed
its output.

The narrow device-identity binding map currently uses a versioned local
settings store behind its repository. This keeps the app functional offline,
but it is not the final structured device database required by the
specification. Migrate it to the planned Drift/SQLite database together with
device metadata, relinking, migrations and referential-integrity handling
before claiming complete device persistence.

It does **not** yet implement active GATT probing, encrypted framing, validated
notification decoding, a centralized scheduler, a complete structured device
database/relink flow, reconnection policy, pipeline execution, or macOS
menu-bar controls. The macOS runner hides the main window on close and reopens
it when activated, but it does not yet offer the required background menu-bar
controls. Basic controls are available for the locally exercised profile; that
does not validate the generic adapter's wider inferred claims.

### App discovery and control flow

```text
Debug page starts a bounded general BLE scan
             │
             ▼
BluetoothLowEnergyTransport emits transport endpoints
             │
             ▼
ProtocolAdapterRegistry selects an unambiguous adapter candidate
             │
             ▼
DebugDevicesController connects and opens a protocol session
             │
             ├── status/capability view state ──► Flutter UI
             │
             └── control intent ──────────────► common LightingCommand
                                                    │
                                                    ▼
                                           selected protocol codec + BLE write
```

The UI has no direct BLE-plugin import. It issues common commands to the
feature controller, which checks selected-session capabilities and prevents
overlapping commands per device before invoking the protocol session. Future user-facing controls
must move through the scheduler boundary before they are allowed to stream or
compete with other sources.

## Module placement

When source code is scaffolded, use these boundaries:

```text
lib/core/
  transports/          # DeviceTransport, BLE driver, sessions, discovery
  protocols/           # adapter registry, contracts, elk implementation
  lighting/            # shared commands, states, capabilities, arbitration
  macros/              # typed macro graph contracts, validation and runtime
  persistence/         # device bindings, migrations, repositories
  diagnostics/         # transport/protocol/scheduler metrics
```

Protocol and transport implementations depend on shared domain contracts, not
on Flutter feature packages. `features/devices` consumes repository and runtime
interfaces only. Native Swift/AppKit/CoreBluetooth code remains an
implementation detail of `BleTransport` and must not introduce a second device
manager.

Concrete macro triggers and modifiers are separate modules registered in the
application composition root. They communicate only through validated typed
ports and must not import one another. The Macro system and the initial
audio/EQ flow are documented in [`MACRO_SYSTEM.md`](MACRO_SYSTEM.md).

The `sink.lighting_target` module is an input-only graph representation of a
device. Its incoming edges derive the portable runtime target binding;
it performs no I/O. `triggerHsv` remains a macro value until the app delivery
bridge converts it to the shared RGB state, after which normal calibration and
protocol encoding apply. This keeps colour modifiers, target nodes and Lotus X
independent of one another. The bridge owns the runtime-only pre-macro desired
state snapshot: the editor has no transport access, and Stop performs a bounded
best-effort restoration only for devices that macro writes actually changed.

The initial microphone module is a narrow PCM16 mono-stream adapter with
explicit permission/session state. The pure Dart Normalization modifier can
transform this stream before the Multiband EQ, either keeping a normalized
`TriggerMonoAudioValue` stream or deriving a `triggerLevel` control value from
its transient rolling dBFS history. Microphone bytes, PCM history and derived
gains never become macro JSON; neither the Normalization modifier nor the EQ
imports the microphone implementation. They are registered together only by
the app composition root.

## Verification requirements

Unit tests must cover adapter matching, confidence tie-breaking, capability
gating, command validation/encoding, transport-independent scheduler behavior,
and persistence/relinking migrations. Mock transport tests must cover discovery,
connection, disconnect, recovery, notifications, missing endpoints, delivery
receipts, and stale-frame dropping.

Hardware validation is required for every protocol/transport combination before
it is marked supported. Record the controller model, firmware information when
available, operations tested, result, sustained update rate, and known limits in
`docs/BLE_PROTOCOLS.md` for BLE work (or a future transport-specific protocol
document). Do not promote a reference implementation's inferred commands to a
supported capability without this evidence.
