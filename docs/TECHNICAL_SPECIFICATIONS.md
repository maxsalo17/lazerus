# LightFlow — Technical Specification
## Cross-Platform Bluetooth Lighting Control System

**Document version:** 1.0  
**Platforms:** iOS, macOS  
**Technology:** Flutter / Dart / Swift / CoreBluetooth  
**Architecture:** Clean Architecture, Feature-first, Reactive State Management  
**Primary protocol:** Bluetooth Low Energy (BLE)  
**Backend:** Not required  
**Cloud dependency:** None  
**Target:** Production-quality application

---

# 1. Project Overview

## 1.1 Purpose

Develop a cross-platform Flutter application for controlling multiple Bluetooth LED controllers, individually and as synchronized groups.

The application must provide an extensible system for managing lighting devices, defining effects, creating complex animation pipelines, configuring lighting scenes, and executing synchronized lighting behaviors with low latency.

The application must support both simple everyday usage and advanced programmable lighting automation.

The application should function completely offline without requiring external servers, user accounts, cloud services, or an internet connection.

## 1.2 Supported Platforms

### macOS

- Native Flutter desktop application.
- Full application window.
- Persistent system menu bar integration.
- Continued operation when the main window is closed.
- Background BLE connection management.
- Quick controls accessible from the menu bar.
- Optional launch at login.
- Full editing and configuration capabilities.

### iOS

- Native Flutter mobile application.
- Responsive touch-based UI.
- BLE device discovery and control.
- Management of devices, groups, scenes and pipelines.
- Local persistence.
- Support for iOS lifecycle and Bluetooth permission handling.

Continuous animation execution in the iOS background must not be assumed. Implement only supported CoreBluetooth background and restoration capabilities, and document platform restrictions.

## 1.3 Core Principles

1. Offline-first operation.
2. Low-latency command delivery.
3. Persistent BLE connections.
4. Modular protocol adapters.
5. Independent device management.
6. Group-based lighting control.
7. Deterministic animation calculation.
8. Reusable effects and pipelines.
9. Persistent configuration.
10. Extensible architecture.
11. Platform-native integration when required.
12. Strict separation between UI, business logic, animation processing and BLE transport.

---

# 2. Hardware and Protocol

## 2.1 Initial Hardware

The first supported hardware family is ELK-series Bluetooth LED controllers used with Lotus Lantern applications.

A device already available for integration testing:

```text
Bluetooth Name: ELK-BLEDDM
Platform: macOS
CoreBluetooth Identifier:
91F1A719-67F3-E7F8-3290-A95ECE292FE9

GATT Service:
0000FFF0-0000-1000-8000-00805F9B34FB

Write Characteristic:
0000FFF3-0000-1000-8000-00805F9B34FB

Notify Characteristic:
0000FFF4-0000-1000-8000-00805F9B34FB

Write properties:
read, write-without-response
```

This controller has been successfully discovered and connected through the Python Bleak library.

The existing LotusLampX application has also been used successfully after patching its device discovery behavior.

**Important:** The BLE UUIDs are confirmed, but the exact device protocol and compatibility with every LotusLampX command have not been comprehensively verified.

## 2.2 Reference Implementations

Use these projects as protocol and implementation references:

- https://github.com/l0lsec/LotusLampX
- https://github.com/chameleonbr/LED_UNION
- https://github.com/razibit/Lotus-Lantern-for-Windows-PC

Do not blindly copy protocol implementations. Identify which commands are verified on physical hardware and which have only been inferred through reverse engineering.

## 2.3 Protocol Adapter Architecture

All device-specific logic must be abstracted behind an interface.

```dart
abstract interface class LightingProtocolAdapter {
  String get id;

  bool supports(DeviceDescriptor descriptor);

  DeviceCapabilities get capabilities;

  Uint8List encodePower(bool enabled);

  Uint8List encodeColor(RgbColor color);

  Uint8List encodeBrightness(double brightness);

  Uint8List encodeEffect(DeviceEffect effect);
}
```

The interface can be refined to support capability-dependent and multi-command operations.

Protocol adapters must support:

- Device recognition.
- GATT service and characteristic mapping.
- Command encoding.
- Protocol variants.
- Optional encryption.
- Capability detection.
- Unsupported-operation handling.
- Optional notification decoding.
- Protocol-specific command constraints.

The architecture must allow additional protocols without modifying core business logic.

## 2.4 Device Capability Model

Do not assume that every LED controller supports the same features.

Capabilities should be modeled explicitly:

```text
DeviceCapabilities
 ├── RGB
 ├── RGBW
 ├── CCT
 ├── Brightness
 ├── Power
 ├── NativeEffects
 ├── EffectSpeed
 ├── AddressablePixels
 ├── Segments
 ├── Notifications
 ├── Encryption
 └── MaximumUpdateRate
```

Each capability can contain additional limits, supported ranges and protocol-specific metadata.

Unsupported controls must not be presented as available features in the UI.

---

# 3. Device Discovery and Management

## 3.1 Device Discovery

The application must be able to:

- Scan nearby BLE devices.
- Display discovered devices in real time.
- Show device name.
- Show signal strength (RSSI) when available.
- Identify supported protocol families.
- Detect previously saved devices.
- Manually connect to discovered devices.
- Display connection progress.
- Handle connection errors.

### Discovery Requirements

Do not rely exclusively on advertised GATT service UUIDs.

Some controllers expose a GATT service after connection but do not include its UUID in advertising packets.

Discovery must support:

1. General BLE scanning.
2. Filtering by known device names.
3. Filtering by supported advertised services when available.
4. Optional safe capability probing after connection.
5. User-selectable unsupported or unidentified devices for diagnostic purposes.

## 3.2 Saved Devices

Users must be able to save devices permanently.

Each device must have:

- Internal application ID.
- User-defined name.
- Last known BLE identifier.
- Advertised name.
- Protocol adapter ID.
- Capability profile.
- Connection preferences.
- Last known lighting state.
- Default preset.
- Assigned groups.
- Optional physical location.
- Optional visual icon.
- Automatic reconnection preference.

Use an application-generated UUID as the primary internal ID.

Do not treat a BLE MAC address or platform-generated Bluetooth identifier as a universal cross-platform hardware identity.

Support rediscovery and manual relinking if a stored platform identifier becomes invalid.

## 3.3 Device Lifecycle

Define connection states:

```text
Unknown
Discovered
Connecting
Connected
Disconnecting
Disconnected
Reconnecting
Unsupported
Error
```

Implement state transitions explicitly.

Features:

- Persistent connections while active.
- Automatic reconnection.
- Configurable reconnection backoff.
- Connection health monitoring.
- Handling device power loss.
- Handling Bluetooth being disabled.
- Recovering after computer sleep.
- Detecting failed writes and disconnects.
- Restoring desired state after reconnection, when appropriate.

A successful GATT write without response does not necessarily confirm that a device executed the command.

Expose transport success separately from confirmed device state.

## 3.4 Device Configuration

The user must be able to:

- Rename devices.
- Choose an icon.
- Assign a room or zone.
- Configure a startup scene.
- Configure brightness limits.
- Set default behavior.
- Assign groups.
- Enable or disable automatic reconnection.
- Remove a saved device.
- Reassociate a previously saved device with a newly discovered BLE identifier.

---

# 4. Individual Lighting Control

Each device must be controllable independently.

## 4.1 Basic Controls

- Power on/off.
- Color picker.
- RGB color values.
- Brightness slider.
- Color temperature when supported.
- Built-in device effects.
- Effect speed when supported.

## 4.2 Advanced Controls

- Color transitions.
- Fade in/out.
- Timed color changes.
- Smooth interpolation.
- Custom software-driven animations.
- Optional per-device update rate.
- Optional brightness limits.
- Custom default state.

## 4.3 Device Modes

Two categories of modes must exist.

### Native modes

Animations executed by the LED controller firmware.

Examples:

- Color cycle.
- Jump.
- Strobe.
- Breathing.
- Native rainbow.

Native modes should use the minimum number of BLE commands required to configure the controller.

### Software-driven modes

Animations calculated by the application and streamed to devices as lighting states.

Examples:

- Custom wave.
- Dynamic pulse.
- Multi-color transitions.
- Timed flashes.
- Coordinated group animations.

Software-driven modes require an active application runtime and suitable device communication performance.

A device must not simultaneously receive conflicting native-effect and software-animation commands.

---

# 5. Device Groups

## 5.1 Group Management

Users must be able to:

- Create groups.
- Rename groups.
- Delete groups.
- Add devices.
- Remove devices.
- Assign one device to multiple groups.
- Define group colors and icons.
- Save group configurations.

Examples:

```text
Studio
 ├── Monitor Lighting
 │    ├── LED Strip 1
 │    └── LED Strip 2
 ├── Desk Lighting
 │    └── LED Strip 3
 └── Floor Lighting
      ├── LED Strip 4
      └── LED Strip 5
```

Groups are logical collections. They do not imply that Bluetooth hardware provides synchronized execution.

## 5.2 Group Controls

Groups must support:

- Power on/off.
- Shared color.
- Shared brightness.
- Shared native effect where compatible.
- Software-driven group animations.
- Group presets.
- Group scenes.
- Group-specific pipelines.

## 5.3 Group Mode Strategies

Implement configurable strategies:

**Uniform:** all group members receive the same lighting state.

**Sequence:** group members receive different states in a defined order.

**Alternating:** states alternate among group members.

**Wave:** the effect propagates through the group according to ordering and delay.

**Mirrored:** devices receive symmetrical states based on their positions.

**Independent Mapping:** one group animation produces different outputs for different members.

Allow configurable ordering and per-device offsets.

## 5.4 Conflict Resolution

A device may belong to multiple groups.

Define explicit arbitration rules:

1. Manual temporary override.
2. Active high-priority scene.
3. Active pipeline.
4. Active group mode.
5. Device default.

Use explicit priorities and stable tie-breaking rules.

A single device must have only one resolved desired output state at any given time.

The arbitration engine must track the winning controller or pipeline, allowing the UI to explain why a device currently has a particular state.

---

# 6. Animation and Mode Engine

## 6.1 General Requirements

Implement a reusable animation engine independent of:

- UI framework.
- BLE transport.
- Specific hardware.
- Application platform.

The engine must calculate desired lighting states based on time and configuration.

It must not directly perform BLE writes.

## 6.2 Animation Modes

Provide built-in modes:

### Static

- Solid color.
- Static brightness.
- Warm/cold white if supported.

### Transition

- Fade.
- Crossfade.
- Color interpolation.
- Smooth color cycle.

### Temporal

- Blink.
- Pulse.
- Breathing.
- Strobe.
- Flash.

### Multi-Device

- Chase.
- Alternate.
- Wave.
- Mirror.
- Sequential fade.
- Random device activation.

### Procedural

- Random colors.
- Noise-based modulation.
- Oscillator modulation.
- Gradient over time.
- Parameter-driven color generation.

All animations must support configurable parameters where appropriate.

## 6.3 Animation Parameters

Possible parameters include:

```text
Color
Brightness
Speed
Duration
Frequency
Phase
Offset
Intensity
Direction
Easing
Repeat
Loop
Delay
BlendMode
RandomSeed
```

The animation engine must support deterministic execution for a fixed input, time and random seed.

---

# 7. Advanced Pipeline System

## 7.1 Purpose

Implement a visual pipeline editor allowing users to create complex lighting behaviors by connecting processing nodes.

Pipelines must be reusable, serializable, composable and executable independently of the UI.

The pipeline system is one of the central features of the application.

## 7.2 Pipeline Model

A pipeline is a directed graph consisting of nodes and connections.

```text
Pipeline
 ├── Nodes[]
 ├── Connections[]
 ├── Inputs[]
 ├── Outputs[]
 ├── Parameters
 └── Metadata
```

Each node represents an operation.

Connections represent typed data flow.

The editor must validate graph structure and data compatibility.

## 7.3 Node Categories

### A. Input Nodes

- Constant Color.
- Constant Number.
- Boolean.
- Time.
- Elapsed Time.
- Device State.
- Group State.
- Manual Trigger.
- Scheduled Trigger.
- Random Value.

### B. Generator Nodes

- Color Generator.
- Rainbow.
- Oscillator.
- Pulse.
- Noise.
- Gradient.
- Wave.
- Pattern Generator.
- Sequence Generator.

### C. Modifier Nodes

- Brightness.
- Hue Shift.
- Saturation.
- Color Blend.
- Clamp.
- Scale.
- Normalize.
- Easing.
- Time Offset.
- Phase Offset.

### D. Logic Nodes

- Condition.
- Compare.
- Switch.
- AND / OR / NOT.
- Threshold.
- Gate.
- State Machine.
- Trigger Filter.

### E. Timing Nodes

- Delay.
- Timer.
- Repeat.
- Loop.
- Sequence.
- Transition.
- Duration.
- Trigger Hold.

### F. Routing Nodes

- Device Selector.
- Group Selector.
- Output Split.
- Device Mapping.
- Group Mapping.
- Channel Routing.

### G. Output Nodes

- Device Color.
- Device Brightness.
- Device Power.
- Device Native Effect.
- Group State.
- Lighting Frame.

## 7.4 Visual Editor

Develop a node-based graphical editor.

Required interactions:

- Add nodes.
- Move nodes.
- Connect nodes.
- Disconnect nodes.
- Delete nodes.
- Duplicate nodes.
- Select multiple nodes.
- Pan canvas.
- Zoom canvas.
- Edit node properties.
- Undo/redo.
- Copy/paste.
- Validate graph.
- Preview output.
- Save pipeline.
- Load pipeline.

macOS must support mouse and keyboard interaction.

iOS must support touch gestures, panning and zooming.

For complex pipelines, the mobile editor may provide a simplified presentation while preserving editing and execution capabilities.

## 7.5 Typed Connections

Define an explicit type system:

```text
Number
Boolean
Color
Duration
Trigger
Time
LightingState
DeviceReference
GroupReference
LightingFrame
```

Reject incompatible connections or provide explicitly defined conversion nodes.

## 7.6 Pipeline Execution

Pipeline execution must:

1. Load graph.
2. Validate structure.
3. Resolve node dependencies.
4. Compile an execution plan.
5. Evaluate nodes.
6. Generate lighting outputs.
7. Send desired states to the scheduler.

Do not permit unrestricted circular graph dependencies.

Stateful feedback must use explicit state/delay nodes with well-defined evaluation semantics.

A pipeline must be able to run without the visual editor being open.

## 7.7 Pipeline Lifecycle

```text
Created
Validated
Ready
Running
Paused
Stopped
Error
```

Provide:

- Start.
- Stop.
- Pause.
- Resume.
- Restart.
- Reset state.
- Manual trigger.
- Parameter updates during execution.

## 7.8 Pipeline Examples

### Example 1: Alternating Lights

```text
Timer (500ms)
    ↓
Toggle
    ↓
Condition
    ├── Strip A → Red
    └── Strip B → Blue
```

### Example 2: Sequential Wave

```text
Wave Generator
    ↓
Color Gradient
    ↓
Group Device Mapping
    ↓
Lighting Outputs
```

### Example 3: Pulsating Group

```text
Oscillator
    ↓
Normalize
    ↓
Brightness Modifier
    ↓
Group Output
```

## 7.9 Pipeline Reusability

Pipelines must support:

- Parameterized inputs.
- Multiple target devices.
- Group targets.
- Saving as templates.
- Duplication.
- Versioned JSON serialization.
- Import/export.

Pipeline execution state must be separate from the saved pipeline definition.

---

# 8. Presets

## 8.1 Preset Definition

A preset is a reusable configuration of lighting parameters or behavior.

A preset may target:

- One device.
- A group.
- Multiple selected devices.

## 8.2 Built-in Presets

Include:

- Warm Ambient.
- Cool Ambient.
- Relax.
- Focus.
- Reading.
- Gaming.
- Cinema.
- Night.
- Neon.
- Rainbow.
- Pulse.
- Party.
- Strobe.

Presets requiring unsupported capabilities must be hidden, adapted safely, or clearly marked unavailable.

## 8.3 Custom Presets

Users must be able to:

- Create a preset from current lighting state.
- Edit a preset.
- Rename a preset.
- Duplicate a preset.
- Delete a preset.
- Assign an icon and color.
- Organize presets.
- Mark favorites.
- Export/import presets.

Presets must store actual parameter values and references, not merely UI labels.

---

# 9. Scenes

## 9.1 Scene Definition

A scene is a configuration that can coordinate multiple devices, groups, presets and pipelines.

Unlike a preset, a scene may contain multiple independent lighting behaviors.

Example:

```text
Scene: Gaming

Monitor Strip:
  Blue + Purple Gradient

Desk Strip:
  Static Purple

Floor Lights:
  Slow Alternating Pulse

Ambient Group:
  Brightness 40%
```

## 9.2 Scene Management

Users must be able to:

- Create scenes.
- Rename scenes.
- Duplicate scenes.
- Delete scenes.
- Save current setup as a scene.
- Assign devices and groups.
- Assign presets.
- Assign pipelines.
- Configure transition duration.
- Set scene priority.
- Mark favorites.
- Import/export scenes.

## 9.3 Scene Activation

Scene activation must:

1. Resolve all scene targets.
2. Validate required capabilities.
3. Resolve control conflicts.
4. Stop or suspend incompatible running behaviors.
5. Apply initial states.
6. Start required pipelines.
7. Update active scene status.

Define scene deactivation policy explicitly.

Supported policies:

- Restore previous desired state.
- Apply configured fallback preset.
- Keep last output.
- Turn off affected devices.

## 9.4 Scene Transitions

Support:

- Instant.
- Fade.
- Crossfade.
- Sequential.
- Custom transition pipeline.

Transitions must be executed only where the hardware and active runtime can support them.

---

# 10. Low-Latency BLE Engine

## 10.1 Core Requirement

The application must avoid reconnecting to a BLE controller for every command.

Connections must be reused across consecutive commands.

## 10.2 Transport Layer

Implement:

```text
BleTransport
 ├── Discovery
 ├── ConnectionManager
 ├── GattClient
 ├── ProtocolAdapterRegistry
 ├── CommandScheduler
 ├── ConnectionRecovery
 └── Diagnostics
```

Use an abstraction suitable for Flutter on iOS and macOS.

Evaluate `flutter_blue_plus` or a native CoreBluetooth bridge. The selection must account for platform support, long-lived connections, state restoration, licensing and maintainability.

## 10.3 Command Scheduler

Implement a centralized scheduler responsible for converting desired lighting states into BLE commands.

Requirements:

- Per-device queues.
- Per-device write serialization.
- Frame coalescing.
- Duplicate elimination.
- Rate limiting.
- Priority handling.
- Connection-aware scheduling.
- Reconnection recovery.
- Metrics.
- Preventing stale command backlogs.

Never queue every intermediate animation frame indefinitely.

When a newer replaceable lighting state becomes available, older untransmitted states should be discarded.

Do not coalesce critical ordered operations unless their semantics permit it.

## 10.4 Update Rates

The application must support configurable update rates.

Initial testing targets:

```text
10 Hz
20 Hz
30 Hz
```

These are experimental targets, not guaranteed hardware capabilities.

Actual supported update rates must be established through measurement.

The scheduler must adapt to controller limitations and BLE throughput.

## 10.5 Connection Persistence

On macOS, keep active BLE sessions running while the app is minimized or the main window is closed.

Reconnect when necessary without rebuilding the entire application state.

## 10.6 Synchronization Engine

All software-driven animations must share a common monotonic time source.

For each animation evaluation:

```text
frame = animation.evaluate(timestamp)
```

Outputs for different devices should be computed using the same logical timestamp.

The BLE scheduler delivers the resulting states independently.

Do not pretend BLE writes execute atomically across multiple devices.

Implement optional per-device phase offsets and latency compensation based on measurements.

## 10.7 Performance Goals

Engineering targets:

- No intentional 300 ms delay before every command.
- No BLE reconnect per lighting frame.
- Responsive manual controls.
- Smooth animations at measured sustainable rates.
- No unbounded write queues.
- No uncontrolled overlapping writes.
- Automatic recovery after disconnects.
- Predictable CPU and memory usage.

Collect actual performance metrics rather than claiming a specific BLE latency without hardware measurements.

---

# 11. macOS Menu Bar Integration

## 11.1 General Requirement

The application must provide a native menu bar control interface.

The main window may be closed without stopping the application.

Explicit Quit must terminate the app.

## 11.2 Implementation

Use a native Swift macOS integration based on AppKit `NSStatusItem` and an appropriate native menu or popover.

Communicate with Flutter through a platform channel or supported integration mechanism.

Avoid running duplicate BLE managers in Swift and Dart.

## 11.3 Menu Bar Features

The menu bar interface must provide:

- Application status.
- Connected device count.
- Quick device selection.
- Individual device power toggles.
- Group power toggles.
- Quick brightness.
- Quick color selection.
- Favorite scenes.
- Recently used scenes.
- Active scene.
- Active pipeline status.
- Stop all active pipelines.
- Open full application.
- Preferences.
- Quit.

## 11.4 Background Behavior

When the main window closes:

- Hide the main window.
- Keep the application process running.
- Keep eligible BLE connections active.
- Keep active pipelines executing.
- Keep the menu bar interface available.

Explicit application quit:

- Stop active runtime tasks.
- Persist required state.
- Disconnect BLE cleanly.
- Exit the application.

Support optional launch at login.

Do not use a headless background process unless required by the final implementation architecture.

---

# 12. iOS Lifecycle

The iOS application must handle:

- Bluetooth authorization.
- Bluetooth disabled state.
- Application backgrounding.
- Foreground restoration.
- Connection restoration where supported.
- Device rediscovery.
- Graceful interruption of software-driven effects.

The application must clearly distinguish between:

- Native effects executed by controller firmware.
- App-generated animations requiring an active runtime.

Do not promise uninterrupted software animation streaming when the iOS app is suspended or force-quit.

---

# 13. Persistence

## 13.1 Storage Requirements

All user-created and configured entities must persist locally.

Persist:

- Devices.
- Device profiles.
- Groups.
- Group membership.
- Presets.
- Scenes.
- Pipelines.
- Node configurations.
- User preferences.
- Device overrides.
- Favorites.
- Connection preferences.
- Default startup behavior.

## 13.2 Database

Use a structured local persistence solution such as SQLite through Drift.

Requirements:

- Typed models.
- Database migrations.
- Schema versioning.
- Transactions.
- Referential integrity.
- Reactive data access where appropriate.

## 13.3 Data Integrity

Deleting a device must not silently corrupt groups, presets, scenes or pipelines.

References to unavailable devices must remain detectable and repairable.

Support restoring scene/device mappings when devices are rediscovered.

## 13.4 Import and Export

Implement portable JSON configuration packages.

Supported exports:

- Preset.
- Scene.
- Pipeline.
- Complete configuration backup.

Imports must include:

- Schema validation.
- Version compatibility checks.
- Reference remapping.
- Conflict resolution.
- Duplicate handling.

Saved device identifiers must not be assumed portable between macOS and iOS.

A configuration imported onto another device must provide a way to relink hardware.

---

# 14. User Interface

## 14.1 Design Goals

The application should feature a modern interface suitable for professional lighting control.

Design principles:

- Clean layout.
- Dark theme as primary.
- Optional light theme.
- Responsive layout.
- Minimal interaction latency.
- Clear device status.
- Visual animation feedback.
- Consistent component design.
- Keyboard shortcuts on macOS.

## 14.2 Main Navigation

### Dashboard

Overview of all connected lighting.

Display:

- Devices.
- Groups.
- Active scenes.
- Favorite presets.
- Quick actions.
- Current system state.

### Devices

Device management and independent controls.

### Groups

Group composition, arrangement and group modes.

### Presets

Built-in and custom presets.

### Scenes

Multi-device scene management.

### Pipelines

Visual node editor, execution and templates.

### Settings

Application, BLE, performance, appearance and persistence configuration.

## 14.3 macOS Layout

Use a desktop-oriented responsive layout with:

- Sidebar navigation.
- Detail panels.
- Multi-column views.
- Context menus.
- Keyboard shortcuts.
- Advanced pipeline canvas.

## 14.4 iOS Layout

Use mobile-friendly navigation with:

- Bottom navigation or adaptive equivalent.
- Touch-sized controls.
- Device cards.
- Full-screen editors when appropriate.
- Responsive forms.
- Gesture-friendly pipeline canvas.

## 14.5 Live Preview

Implement a software preview of expected output colors and effects.

Preview rendering must be independent of physical device communication.

Allow previewing a pipeline without connecting real devices.

The UI must distinguish a simulated expected output from a confirmed physical device state.

---

# 15. Application Architecture

## 15.1 Architectural Style

Use:

- Clean Architecture.
- Feature-first organization.
- Dependency injection.
- Repository pattern.
- Reactive state management.
- Strongly typed domain models.
- Separation of pure computation from side effects.

Avoid excessive abstraction where it provides no concrete benefit.

## 15.2 Suggested Project Structure

```text
lib/
 ├── app/
 │   ├── bootstrap/
 │   ├── router/
 │   └── theme/
 │
 ├── core/
 │   ├── bluetooth/
 │   │   ├── transport/
 │   │   ├── discovery/
 │   │   ├── connection/
 │   │   └── scheduler/
 │   │
 │   ├── protocols/
 │   │   ├── registry/
 │   │   └── elk/
 │   │
 │   ├── lighting/
 │   │   ├── models/
 │   │   ├── arbitration/
 │   │   └── synchronization/
 │   │
 │   ├── animation/
 │   │   ├── engine/
 │   │   ├── effects/
 │   │   └── timeline/
 │   │
 │   ├── pipeline/
 │   │   ├── graph/
 │   │   ├── nodes/
 │   │   ├── compiler/
 │   │   └── runtime/
 │   │
 │   ├── persistence/
 │   ├── diagnostics/
 │   └── platform/
 │
 ├── features/
 │   ├── dashboard/
 │   ├── devices/
 │   ├── groups/
 │   ├── presets/
 │   ├── scenes/
 │   ├── pipelines/
 │   └── settings/
 │
 └── shared/
     ├── widgets/
     ├── extensions/
     └── utilities/
```

Organize modules with clear public APIs and avoid circular dependencies.

## 15.3 State Management

Use Riverpod or an equivalent well-supported, testable state management solution.

Requirements:

- Reactive UI updates.
- Testable controllers.
- Explicit lifecycle management.
- No uncontrolled global mutable state.
- No direct BLE calls inside widgets.
- Clear separation between persistent configuration and ephemeral runtime state.

## 15.4 Domain Models

At minimum, define:

```text
LightingDevice
DeviceDescriptor
DeviceCapabilities
DeviceConnectionState
LightingState
DesiredLightingState
DeviceGroup
GroupMembership
LightingMode
LightingPreset
LightingScene
SceneAssignment
PipelineDefinition
PipelineNode
PipelineConnection
PipelineExecution
DeviceOverride
ApplicationSettings
```

Use immutable models where practical.

## 15.5 State Resolution

Separate these concepts:

**Configuration state:** what is stored in the database.

**Desired state:** what the animation and arbitration systems want the lights to display.

**Transport state:** whether the command has been queued or written.

**Observed state:** what the hardware reports, if available.

Never assume desired, transmitted and observed states are identical.

---

# 16. Reliability and Diagnostics

Implement a diagnostics interface.

It must expose:

- BLE scan results.
- Advertisement information.
- GATT services.
- Characteristics and properties.
- Connection attempts.
- Connection durations.
- Reconnection attempts.
- Outgoing command count.
- Write duration.
- Command queue size.
- Scheduler frame rate.
- Dropped/coalesced frames.
- Errors and disconnect reasons.

Provide optional verbose logging and diagnostic export.

Avoid logging sensitive or unrelated nearby Bluetooth-device information unnecessarily.

Do not expose raw arbitrary GATT writes in ordinary user-facing controls.

---

# 17. Testing

## 17.1 Unit Tests

Test:

- Color calculations.
- Brightness scaling.
- Animation evaluation.
- Graph validation.
- Pipeline execution.
- Group membership.
- Arbitration logic.
- Scheduling decisions.
- Serialization and migrations.

## 17.2 BLE Tests

Use mocked BLE transports to test:

- Connection success.
- Connection failure.
- Disconnection.
- Reconnection.
- Write serialization.
- Dropped frames.
- Device switching.
- Protocol encoding.
- Missing characteristics.

## 17.3 Integration Tests

Test:

- Device discovery.
- Saving and restoring devices.
- Creating groups.
- Applying presets.
- Scene activation.
- Pipeline execution.
- Persistence across restarts.
- Menu bar controls.
- Closing and reopening macOS window.

## 17.4 Hardware Validation

Real hardware testing is required for:

- Actual device protocol.
- Supported commands.
- Maximum sustainable write rate.
- Connection stability.
- Multiple device connections.
- Group synchronization accuracy.

Do not claim hardware compatibility based only on mocked tests.

---

# 18. Acceptance Criteria

## Device Management

- User can discover the ELK-BLEDDM controller.
- User can save and rename it.
- Saved configuration survives application restart.
- User can reconnect without repeating onboarding.
- Connection errors are handled gracefully.

## Individual Controls

- Power can be controlled.
- Supported colors can be changed.
- Brightness can be controlled.
- Supported native modes can be selected.
- Consecutive changes do not require new BLE connections.

## Groups

- User can create and edit a group.
- User can add multiple devices.
- Group commands target all selected members.
- Per-device overrides work according to defined arbitration rules.

## Pipelines

- User can create a pipeline visually.
- User can connect compatible nodes.
- Invalid graphs produce useful validation errors.
- Pipelines can be saved and reopened.
- Pipelines execute without the editor being visible.
- Animation outputs are passed through the scheduler.

## Scenes and Presets

- Built-in presets are available.
- Custom presets can be created.
- Custom scenes can coordinate multiple targets.
- Scenes survive application restart.
- Scene activation and conflict handling are deterministic.

## macOS

- Main application window can be closed.
- Application remains available in the menu bar.
- Lighting remains controllable without reopening the main window.
- Pipelines continue while the main window is closed.
- Explicit Quit terminates the application.

## iOS

- User can discover and control supported BLE hardware.
- Devices, scenes, presets and pipelines can be configured.
- The application behaves correctly during lifecycle transitions.
- Unsupported background functionality is not falsely presented as available.

---

# 19. Implementation Phases

## Phase 1 — Foundation and BLE

Implement:

- Flutter project initialization.
- Architecture and dependency injection.
- BLE abstraction.
- ELK protocol adapter.
- Device scanning.
- Device connections.
- Persistent BLE sessions.
- Independent power/color/brightness controls.
- Initial diagnostics.

**Deliverable:** Functional macOS and iOS applications controlling supported hardware.

## Phase 2 — Device Management and Persistence

Implement:

- Local database.
- Saved devices.
- Device renaming.
- Automatic reconnection.
- Capabilities.
- Configuration restoration.
- Basic settings.

**Deliverable:** Reliable everyday device management.

## Phase 3 — Groups and Presets

Implement:

- Device groups.
- Group controls.
- Group arbitration.
- Built-in presets.
- Custom presets.
- Favorites.

**Deliverable:** Multi-device lighting management.

## Phase 4 — Animation Engine

Implement:

- Animation timeline.
- Built-in software effects.
- Device scheduler.
- Frame coalescing.
- Rate limiting.
- Synchronization model.
- Performance instrumentation.

**Deliverable:** Stable software-generated lighting animations.

## Phase 5 — Scenes

Implement:

- Scene creation.
- Multi-device assignments.
- Scene transitions.
- Scene persistence.
- Scene activation policies.
- Conflict resolution.

**Deliverable:** Full lighting scene management.

## Phase 6 — Pipeline Engine

Implement:

- Pipeline graph models.
- Typed nodes.
- Graph validation.
- Graph execution.
- Node library.
- Stateful pipeline runtime.
- Persistence.
- Runtime diagnostics.

**Deliverable:** Functional pipeline engine with automated tests.

## Phase 7 — Visual Pipeline Editor

Implement:

- Node canvas.
- Drag-and-drop.
- Connection editing.
- Property inspector.
- Zoom and pan.
- Undo/redo.
- Live preview.
- Import/export.

**Deliverable:** Complete user-facing pipeline editor.

## Phase 8 — macOS Integration

Implement:

- Native menu bar.
- Main-window close behavior.
- Background runtime.
- Quick controls.
- Favorite scenes.
- Launch at login.
- Application lifecycle tests.

**Deliverable:** Fully integrated macOS application.

## Phase 9 — Optimization and Release

Implement:

- Multi-device stress testing.
- BLE performance optimization.
- UI performance improvements.
- Error handling.
- Configuration backup.
- End-to-end tests.
- Platform-specific packaging.
- Documentation.

**Deliverable:** Production-ready application.

---

# 20. Future Extensibility

The architecture should permit adding the following features later without rewriting the core system:

### Audio Reactive Lighting

- Audio input.
- FFT analysis.
- Frequency bands.
- Beat detection.
- Onset detection.
- Audio-driven pipeline nodes.

### MIDI Integration

- MIDI note input.
- MIDI velocity mapping.
- MIDI CC input.
- MIDI clock.
- Ableton integration.
- Instrument-specific lighting mappings.

### Advanced Music Analysis

- Drum, bass, lead, vocal and ambient categories.
- Note and velocity events.
- Composition section events.
- Musical energy classification.
- Genre-independent scene automation.

### Additional Hardware

- Other BLE controller families.
- RGBIC controllers.
- Addressable LED strips.
- ESP32-based custom devices.
- Network-connected lighting controllers.
- Multi-channel lighting hardware.

### Scheduling

- Time-based lighting automation.
- Daily schedules.
- Startup scenes.
- Sunrise/sunset-inspired transitions.
- Configurable triggers.

These are architectural extension points, not mandatory first-release features.

---

# 21. AI Development Instructions

The implementing AI agent must follow these rules:

1. Treat this specification as the primary project requirements document.
2. Build functioning production-oriented code rather than disconnected examples.
3. Preserve modularity and platform compatibility.
4. Use maintained packages and check API compatibility before integration.
5. Do not assume BLE hardware behavior without validation.
6. Do not hardcode specific device identifiers into application logic.
7. Keep all protocol-specific code isolated.
8. Keep animation calculation independent of BLE.
9. Implement persistent BLE sessions.
10. Do not establish a new connection for each lighting command.
11. Do not accumulate unbounded animation frames.
12. Define and test deterministic state arbitration.
13. Include database migration support.
14. Include tests for critical domain logic.
15. Document native macOS and iOS integration requirements.
16. Avoid unnecessary backend or cloud services.
17. Prefer simple, maintainable implementations over excessive dependencies.
18. Do not silently substitute placeholders for required functionality.
19. Clearly mark hardware-dependent features requiring physical validation.
20. Maintain a coherent, compiling project throughout development.

## Required Project Documentation

Create and maintain:

```text
README.md
docs/ARCHITECTURE.md
docs/BLE_PROTOCOLS.md
docs/DATA_MODELS.md
docs/PIPELINE_ENGINE.md
docs/SCENE_SYSTEM.md
docs/PERFORMANCE.md
docs/TESTING.md
docs/ROADMAP.md
```

## Definition of Done

A feature is complete only when:

- Implementation exists.
- Relevant UI is functional.
- Business logic is connected.
- Persistence works where required.
- Error states are handled.
- Automated tests cover critical behavior.
- The project compiles for the relevant platforms.
- Hardware-dependent functionality has either been validated or explicitly identified as awaiting hardware validation.

---

# 22. Final Product Goal

The final product must function as an extensible local lighting control platform, not merely as a Bluetooth remote.

It must provide a consistent system for discovering devices, storing configurations, independently controlling lights, grouping hardware, constructing reusable lighting behaviors, executing complex animation pipelines and activating synchronized multi-device scenes.

The system should scale from two simple Bluetooth LED strips to a larger, heterogeneous lighting installation without fundamental architectural changes.

**Primary engineering priority: reliable low-latency lighting control with a clean separation between device communication, animation logic, state resolution and user configuration.**
