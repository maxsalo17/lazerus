# Testing

## Automated checks

Run application checks from the app directory:

```sh
cd apps/lazerus_app
flutter analyze
flutter test
flutter build macos --debug
```

Run package checks independently:

```sh
cd packages/lazerus_core
flutter test
dart analyze

cd ../lazerus_proto_lotus_lamp_x
flutter test
dart analyze
```

Tests are intentionally contract-focused. They cover transport/protocol
contracts, codec encoding, device lifecycle and command ordering, calibration
mapping and JSON validation, macro graph serialization/validation, dynamic
module-port conformance, typed runtime routing and the in-flight-first macro
delivery policy. The last rule verifies that a value arriving while a device
write is unsettled is dropped and a later value is accepted only after the
write settles.

Presentation gestures, microphone capture latency and visible LED response are
not represented by an artificial broad widget-test matrix. They require manual
or hardware validation.

## Hardware validation still required

Two strips were reported as auto-connected and responsive to basic commands on
2026-10-23. The model, firmware, command-by-command result and sustained rate
were not captured. Before expanding an ordinary capability claim, record the
following in [`BLE_PROTOCOLS.md`](BLE_PROTOCOLS.md):

- controller model and firmware;
- exact protocol command and write mode;
- observed output and disconnect/reconnect behaviour; and
- sustainable device update rate.

In particular, validate FFF3 writes, whether FFF4 notifications or reads expose
meaningful state, all power/colour/brightness commands, the red-to-violet
palette, reconnect behaviour, app lifecycle handling and macro
microphone-to-light latency. A transport receipt alone never proves a physical
controller applied a command.

Per-device calibration also needs physical validation: capture desired hue,
mapped command hue, visible strip colour, firmware and ambient conditions. The
editor is a manual aid, not a colour-accuracy claim.
