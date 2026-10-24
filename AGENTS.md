# Lazerus — Instructions for Contributors and Coding Agents

## Source of truth

`docs/TECHNICAL_SPECIFICATIONS.md` is the primary requirements document for
this project. Read the relevant sections before designing or changing a
feature. When a request conflicts with the specification, call out the
conflict and obtain a deliberate product decision; do not silently change the
architecture or reduce a required capability.

Lazerus is a production-oriented, offline-first lighting-control application
for macOS and iOS. It is not a cloud service or a one-device Bluetooth remote.
The target stack is Flutter/Dart with Swift/AppKit/CoreBluetooth integration
where native macOS behavior is required.

## Product invariants

- Keep the app fully functional without an account, backend, cloud service, or
  internet connection.
- Support multiple lighting controllers independently and through direct-device
  Macro automation.
- Treat BLE as the first implemented transport, while keeping transport
  selection separate from device-protocol selection so later USB, Wi-Fi, HTTP,
  MQTT, or other transports do not require a domain-model rewrite.
- Keep active BLE connections persistent; never reconnect for each lighting
  command or animation frame.
- Do not hard-code a test device's MAC address, CoreBluetooth identifier, or
  other platform-specific identifier into application logic.
- Keep protocol, BLE transport, lighting/animation calculation, state
  arbitration, persistence, and UI separate.
- Prefer a small, maintainable implementation over speculative abstractions or
  dependencies.
- Never present an unsupported controller capability or iOS background behavior
  as working.

## Architecture and dependency direction

Use Clean Architecture with feature-first UI organization, dependency
injection, repository boundaries, immutable typed models where practical, and
testable reactive state management (Riverpod or a similarly well-supported
alternative).

Organize new code along the intended boundaries:

```text
lib/
  app/                 # Bootstrap, routing, theme and composition root
  core/
    transports/        # BLE now; discovery, sessions and transport drivers
    protocols/         # Adapter registry and hardware-family implementations
    lighting/          # Domain models, arbitration and synchronization
    animation/         # Pure time-based effects and timeline evaluation
    pipeline/          # Graph, nodes, compiler and runtime
    persistence/       # Local database, migrations and repositories
    diagnostics/       # Metrics and safe diagnostic export
    platform/          # Narrow platform abstractions and channels
  features/            # Devices, calibration, macros, diagnostics and settings UI
  shared/              # Reusable presentation-only utilities and widgets
```

- `features/` must not call transport APIs directly. Widgets must not own
  transport state or perform business logic.
- The animation engine must be pure with respect to transport: it evaluates a
  desired lighting state for a timestamp; the scheduler performs writes.
- Add protocol families only through `LightingProtocolAdapter`-style
  abstractions and a registry. Core business logic must not branch on a device
  brand or UUID.
- Avoid circular package/module dependencies. Expose narrow public APIs at
  each boundary.

## Transport, BLE, and hardware rules

- A transport owns physical discovery, connection, I/O, and transport-level
  lifecycle. A protocol adapter recognizes compatible endpoints, exposes the
  device capability profile, and encodes/decodes device-specific messages. See
  `docs/ARCHITECTURE.md` for the shared contracts and selection flow.
- Protocol adapters participate in discovery by declaring filters and optional
  safe probes; they must not create competing platform scanner loops.

- Scan generally, then filter by known names and advertised services when
  available. Do not require a service UUID to be advertised: some supported
  controllers expose it only after connection.
- Model device lifecycle states explicitly: `Unknown`, `Discovered`,
  `Connecting`, `Connected`, `Disconnecting`, `Disconnected`, `Reconnecting`,
  `Unsupported`, and `Error`.
- Use an application-generated UUID as the saved device's primary identity.
  Treat platform BLE IDs as mutable link data and support rediscovery/relinking.
- Model capabilities and their limits explicitly. Hide or safely disable
  controls unsupported by the selected adapter/device.
- Treat a write-without-response as transport success, not confirmation that a
  controller applied the state. Keep configuration, desired, transport, and
  observed state distinct.
- Serialize writes per device. The centralized scheduler must coalesce
  replaceable frames, remove duplicates, rate-limit, prioritize, track queue
  metrics, and discard stale unsent animation frames. Do not create unbounded
  queues or overlapping writes.
- Use one monotonic logical timestamp for software-driven multi-device frames.
  BLE delivery is not atomic across devices; do not claim perfect hardware
  synchronization without measured validation.
- Record what has been tested on real hardware. Protocol commands inferred from
  reverse engineering must be marked unverified until physical validation.
- Do not expose arbitrary raw GATT writes in normal user-facing controls.

## Lighting, macros, and pipelines

- A device has exactly one resolved desired output at any time. An active Macro
  input takes priority over the same manual device parameter; otherwise the
  device's manual value is used. Make this deterministic and retain the winning
  source so the UI can explain why the device has its current state.
- A device must not receive conflicting native-effect and app-streamed
  animation commands concurrently.
- Animation evaluation must be deterministic for fixed inputs, timestamp, and
  random seed. It must be independent of Flutter widgets and BLE transport.
- Pipelines are typed, versioned, serializable directed graphs. Validate data
  types and graph structure before execution; reject unrestricted cycles.
  Stateful feedback must use explicit delay/state semantics.
- Persist pipeline definitions separately from runtime execution state. Pipelines
  must run without their editor open.
- Validate direct Macro targets and capabilities before start, resolve
  conflicts, and follow the explicit stop/restoration policy.

## Persistence and platform integration

- Store configuration locally in a structured database (the specification
  proposes SQLite via Drift), with typed models, migrations, schema versions,
  transactions, and referential integrity.
- Device deletion must not silently corrupt presets, macros or pipelines.
  Preserve broken references in a detectable, repairable form.
- Imports/exports are versioned JSON and require schema validation, compatibility
  checks, conflict handling, duplicate handling, and hardware-reference
  remapping. BLE identifiers are not portable across platforms.
- On macOS, closing the main window hides it rather than quitting. Eligible BLE
  sessions, pipelines, and the native `NSStatusItem` menu-bar controls continue
  until explicit Quit. Avoid duplicate Swift and Dart BLE managers.
- On iOS, support only lifecycle/background behavior CoreBluetooth actually
  permits. Clearly distinguish controller-native effects from app-streamed
  animations, which cannot be promised while the app is suspended or
  force-quit.

## Implementation workflow

1. Identify the relevant specification requirements and acceptance criteria.
2. Define or refine typed domain contracts before UI or adapter implementation.
3. Implement pure domain logic and tests first where possible.
4. Add repositories, transport, and platform adapters behind interfaces.
5. Wire controllers and UI last; expose loading, unsupported, error, and
   recovery states.
6. Run the narrowest relevant automated checks, then broader platform checks as
   appropriate. Perform real-device validation for hardware-dependent work.
7. Update documentation whenever public architecture, data, protocol knowledge,
   performance measurements, testing procedure, or delivery phase changes.

Do not leave disconnected mock screens, placeholder behavior, or silent
fallbacks in place of required functionality. If a dependency API or device
protocol is uncertain, verify it before committing to an integration.

## Tests and definition of done

Critical logic requires automated coverage: color/brightness calculations,
animation evaluation, graph validation and execution,
arbitration, scheduler decisions, protocol encoding, serialization, and database
migrations. Use mocked BLE transports for connection, recovery, write ordering,
frame dropping, and characteristic-missing cases. Add integration and lifecycle
tests where the feature crosses persistence, UI, or native macOS boundaries.

A feature is complete only when its UI (where applicable), domain behavior,
persistence, error handling, and tests are connected; the relevant targets
compile; and hardware-dependent behavior has either been physically validated
or explicitly documented as pending validation.

## Documentation to maintain

Keep these documents current as implementation begins:

- `README.md`
- `docs/ARCHITECTURE.md`
- `docs/BLE_PROTOCOLS.md`
- `docs/DATA_MODELS.md`
- `docs/PIPELINE_ENGINE.md`
- `docs/MACRO_SYSTEM.md`
- `docs/PERFORMANCE.md`
- `docs/TESTING.md`
- `docs/ROADMAP.md`

Do not claim measured BLE performance, protocol compatibility, or background
execution behavior without supporting hardware or platform evidence.
