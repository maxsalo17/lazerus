# Testing

## Automated checks

Run the checks for the current Flutter application from its directory:

```sh
cd apps/lazerus_app
flutter analyze
flutter test
flutter build macos --debug
```

`flutter test` uses fake transports, including a fake native BLE manager. It
verifies that the first scan waits for the native adapter's `poweredOn` state,
that a supported Lotus Lamp X candidate is automatically connected, command
delivery remains gated when the diagnostic safeguard is explicitly disabled,
Common groups derive
membership from protocol, custom auto-membership combines protocol and manual
members, a five-pixel horizontal-drag popup is anchored to its control, vertical
movement does not alter its value, and the drag is measured from the initial
value. It also checks the Lotus red-to-violet palette and the replaceable-command ticker:
stale pending values are dropped while a write is in flight and the final value
is flushed when the finger lifts. It also verifies that an E1-shaped inbound
Lotus packet is recorded as a best-effort observed value in the local Logs
state; it does not claim a controller-confirmed value. Group-control state is
derived from per-device local values, including the ordered list of member
colours used for the group gradient.

Calibration tests cover monotonic curve interpolation, supported-hue mapping,
neutral-colour preservation, versioned JSON validation, profile assignment,
copy-on-save isolation for unselected devices, temporary editor preview, and
the command boundary: the Lotus E1 frame receives the corrected colour while
the app's requested/group state retains the desired colour.

Scene-foundation tests cover versioned composition JSON, ordered stable slots,
typed binding validation, fresh-repository persistence, Scene CRUD, and live
reference resolution. Scene Settings widget tests cover adding a control to an
empty slot, changing its type and clearing it again, while application tests
ensure a group binding is offered only when every current member supports that
parameter. Scene runtime tests cover device-set deduplication, unavailable
binding reporting, final-value slider dispatch, and connection/capability
rechecks at ticker emission. The Scene Detail widget test verifies that custom
controls precede Groups and Devices and that a multi-binding toggle sends one
deduplicated target.

The package-level contract and codec tests remain executable independently:

```sh
cd packages/lazerus_core && flutter test && dart analyze
cd ../lazerus_proto_lotus_lamp_x && flutter test && dart analyze
```

## Hardware validation still required

Automated tests do not validate every actual BLE controller. Two strips were
reported as auto-connected and responding to app commands on 2026-10-23; the
model, firmware, command-by-command outcomes, and rate were not captured.
Before presenting an expanded Lotus Lamp X capability as ordinary product
functionality, test it on the specific controller/firmware profile and record
the command, observed result, write mode, disconnect behavior, and sustained rate in
[`BLE_PROTOCOLS.md`](BLE_PROTOCOLS.md).

In particular, validate the FFF3 write behavior, whether FFF4 notifications or
GATT reads represent state, each power/color/brightness command (including the supported
red-to-violet palette), the sustainable 10 Hz drag-control rate, reconnect
behavior, and the behavior after app backgrounding or a macOS window close. A
transport-level write receipt alone is not evidence that the controller applied
a change.

Per-device calibration also requires physical validation: record desired hue,
curve output hue, visible strip colour, firmware, and ambient conditions for
each controller model. The editor is manual assistance, not a measured colour
calibration or a compatibility claim.
