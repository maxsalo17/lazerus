# lazerus_proto_lotus_lamp_x

The first Lazerus protocol adapter: Lotus Lamp X / ELK-family E1 frames over a
generic BLE transport session. This is a local workspace package and is not
published independently.

The adapter implements `LightingProtocolAdapter` from `lazerus_core` and
provides:

- BLE discovery hints for ELK/MELK names and the FFF0 GATT service;
- deterministic protocol matching without requiring the service to appear in
  advertisements;
- a plain 9-byte E1 frame codec for power, RGB color, brightness, and four
  native-effect IDs inferred from LotusLampX; and
- a device session that sends frames through the core `TransportSession`.

## Safety and validation status

The codec is based on the public LotusLampX reference implementation, not on a
completed Lazerus hardware-validation campaign. All exposed features are marked
as `inferred`, ordinary UI must treat them as unavailable, and the session
rejects commands unless `allowUnverifiedCommands: true` is explicitly supplied
for a diagnostic session.

Encrypted framing, notification decoding, native-effect behavior, acknowledgements,
and sustainable write rate are not currently implemented or validated. See
`docs/BLE_PROTOCOLS.md` at the repository root before extending this adapter.
