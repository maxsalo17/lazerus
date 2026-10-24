# Lazerus app

The iOS/macOS Flutter application for Lazerus. It discovers supported BLE
lighting controllers, connects to matched candidates automatically, and offers
device management, groups, compact controls, and detailed control screens.

## Current controls

The app currently registers the Lotus Lamp X / ELK BLE adapter. After the user
starts a scan, it scans generally (some controllers do not advertise FFF0),
matches endpoints through the adapter registry, discovers GATT after
connection, and routes adapter messages to the requested characteristic. The
initial scan waits briefly for the native BLE adapter to report `poweredOn`, so
it does not silently run before CoreBluetooth is ready.

Power, red-to-violet saturated colour presets, and brightness have been reported
working on two physical strips with the current local setup. The hold controls
show a control-relative gradient palette, use horizontal relative motion from
the starting value, and sample replaceable drag commands at most once every
100 ms; the final value is sent when the finger lifts. White and black are not
sent as Lotus X colour commands. The generic Lotus profile still includes
inferred behavior and is not a compatibility promise for every controller or
firmware. A displayed `transmitted` or `acknowledged` result means only that
the BLE transport accepted the write; it is not evidence that the light changed.

Custom groups, local app-device identities, and user-defined device names are
stored on-device. A user-defined name is separate from the controller's
advertised BLE name, so it survives rediscovery without changing the transport
binding. A Common
group is derived for each discovered protocol family, cannot be edited, and
always includes all matching devices. A custom group can keep explicit members
and optionally include newly discovered devices with one chosen protocol.

During the active app session, every protocol keeps a partial local state from
accepted commands and recognized notifications. Device cards and group cards
derive from that same state, so changing a device updates its groups and a
successful group command updates every member card. A group colour marker is a
gradient through the known colours of its members; its brightness is the mean
of known member brightnesses. This is UI bookkeeping, not persisted state or
hardware confirmation.

The app has no structured device database, relinking UI, reconnect policy,
central scheduler, scenes, or pipelines yet.

## Logs and diagnostic reads

The **Logs** tab keeps up to 400 local, in-memory BLE diagnostic events. It
shows connection and command errors, raw inbound packets, and a button to ask
each connected protocol session for its current state. For Lotus Lamp X this
reads FFF4 only when the device actually exposes it as readable; otherwise the
log says that it is waiting for notifications. E1-shaped power, RGB, and
brightness packets are shown as `best-effort` observations, while unknown
payloads remain hexadecimal. These entries are not persisted and do not prove
that a controller applied a command.

## Requirements

- Flutter 3.41 / Dart 3.11 or compatible.
- macOS 12 or later for the current desktop build.
- iOS 15 or later for the current mobile build.
- Bluetooth permission granted to the app.

## Run and verify

```sh
flutter pub get
flutter run -d macos
flutter analyze
flutter test
flutter build macos --debug
flutter build ios --debug --no-codesign
```

An iOS device build made with `--no-codesign` must be signed before deployment.
Record all real-device protocol checks in
[`../../docs/BLE_PROTOCOLS.md`](../../docs/BLE_PROTOCOLS.md).

## Boundaries

- `lib/core/bluetooth` owns the BLE-plugin integration and implements
  `DeviceTransport`.
- `lib/features/debug` owns diagnostic UI state and calls only the core
  transport/protocol contracts.
- `lib/features/diagnostics` renders local transport/protocol observations; it
  does not invoke GATT APIs directly.
- `packages/lazerus_proto_lotus_lamp_x` owns ELK/Lotus protocol matching and
  framing; no Flutter widget or BLE SDK contains brand-specific branches.
