# Per-device hue calibration

## Objective

Provide a local, persistent correction for controllers whose emitted colour is
not linear with the colour selected in Lazerus. The first implementation
targets the Lotus Lamp X saturated hue range (red through violet). A
calibration is assigned to devices. Each outgoing device command is corrected
independently before its protocol adapter encodes the command.

## Product behaviour

- On **Devices**, a person selects one or more devices with checkboxes. Once a
  device is selected, only devices with the same protocol adapter can be added
  to that batch.
- **Calibrate** opens one editor for that batch. The dropdown contains the
  calibration profiles currently assigned to any selected device and a
  `New calibration` option.
- Selecting an existing profile creates an editable copy when it is saved. The
  new or edited profile is then assigned to the selected devices only; devices
  outside the batch keep their prior profile unchanged.
- A profile is a monotonic, piecewise-linear mapping from the desired hue
  position (X) to the hue command sent to the controller (Y). `0 → 0` and
  `1 → 1` are fixed endpoints. Intermediate anchors may be added by double
  tapping the curve and moved vertically. Monotonic output prevents a hue
  range from folding back on itself.
- Dragging an anchor previews that anchor's desired hue continuously using the
  existing replaceable-command ticker. Preview command writes are not hardware
  confirmation. Closing the editor without saving removes its temporary
  mapping.
- UI state continues to show desired colours. The calibration mapping produces
  a distinct transport colour immediately before protocol encoding. Observed
  protocol data remains transport/observed data; it is not inverted or
  presented as proof of physical output.

## Contract and storage

`HueCalibrationProfile` is a typed, protocol-scoped value with an ID, display
name, hue bounds, and normalized anchors. Its pure mapper preserves saturation
and value and remaps only a supported hue. The current Lotus profile bounds
are 0°–285°; neutral colours are left unchanged.

`DeviceCalibrationConfiguration` contains profiles plus an assignment from an
application device UUID to a profile ID. It is persisted atomically as the
versioned JSON document `lazerus.device_hue_calibrations.v1` using
`SharedPreferences`, the app's local settings store on macOS and iOS. Invalid
or unsupported JSON is ignored safely rather than crashing the app.

The technical specification proposes SQLite/Drift for the eventual complete
configuration database. The user has deliberately chosen JSON local storage
for this narrowly scoped, early calibration feature. The document is versioned
and isolated behind a repository so it can be migrated to the future database
without changing calibration or UI contracts.

## Boundaries

- Presentation widgets do not call BLE APIs. They update a draft, invoke a
  calibration controller, and use the lighting command controller for preview.
- `DebugDevicesController` remains the only app layer that executes commands.
  It asks the calibration controller for a device-specific transport command.
- Existing protocol adapters receive ordinary `SetColor` commands; they do not
  know about UI editing or persistence.
- This is a best-effort manual calibration, not a sensor-based measurement and
  not a claim of colour accuracy across strips, firmware, or ambient light.

## Acceptance criteria

1. Selected devices have one protocol ID and the editor can create, select,
   modify, reset, save, and re-open a profile.
2. A saved profile and its device assignments survive an application restart.
3. A `SetColor` to selected calibrated devices sends a separately mapped
   transport colour while their device cards retain the desired colour.
4. A curve drag produces debounced/replaceable preview commands and removes
   the temporary override on exit.
5. Unit tests cover curve interpolation, colour mapping, JSON validation,
   assignment, and the command-boundary mapping.

## Non-goals in this slice

- Full RGB/Lab 3D colour calibration, automatic camera/sensor measurement, or
  inverse decoding of inbound device state.
- Cross-device configuration export/import. This follows the future versioned
  import/export contract in the technical specification.
