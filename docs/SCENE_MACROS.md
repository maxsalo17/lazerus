# Spec: Scene macros and trigger graph

## Status and scope

Tasks 1–4 are implemented: persisted reusable typed graph contracts, pure
validation, local JSON-file persistence, repairable Scene references, a
transport-free runtime/registry, a bounded lighting-intent delivery bridge,
microphone/EQ trigger modules, and the Scene workflow/editor. A Scene Macro
receives trigger data, transforms it, and publishes lighting intents for its
saved device/group bindings.

It extends the directed-graph direction in
[`TECHNICAL_SPECIFICATIONS.md`](TECHNICAL_SPECIFICATIONS.md), but does not
silently introduce a competing writer or claim the full Scene activation and
arbitration runtime is already present. A running macro has explicit lifecycle
state and must publish through the central lighting-intent/scheduler boundary.

## First user flow

```text
Microphone trigger
  └─ triggerMonoAudio ──> Multiband EQ trigger
                               ├─ low level/gate  ──> Strip/group brightness
                               ├─ mid level/gate  ──> Strip/group brightness
                               └─ high level/gate ──> Strip/group brightness
```

The microphone is only the first producer. Future playlist, sensor or other
producers can feed a compatible typed port. A Multiband EQ does not import or
otherwise know about the microphone implementation; it only declares and
receives `triggerMonoAudio` values.

## Contracts

Every port has a stable machine ID, display metadata for the editor, direction,
and one declared type. Connections are valid only between an output and an
input of the same compatible type. A persisted graph stores IDs and parameters,
not active streams, raw audio buffers, platform microphone IDs, BLE IDs, or
confirmed hardware state.

Runtime contract validation uses machine-facing port identity, direction, type
and cardinality. A saved human-readable `displayName` can change for copy or
localization without making an otherwise valid macro unrunnable.

```dart
enum MacroPortType {
  triggerMonoAudio,
  triggerArray,
  triggerGate,
  triggerLevel,
  triggerHsv,
}

sealed class TriggerValue {}

class TriggerArrayValue extends TriggerValue {
  TriggerArrayValue(this.values);
  final List<double> values;
}

class TriggerMonoAudioValue extends TriggerArrayValue {
  TriggerMonoAudioValue({
    required super.values,
    required this.sampleRateHz,
  });

  final int sampleRateHz;
}

class TriggerGateValue extends TriggerValue {
  const TriggerGateValue(this.value);
  final bool value;
}

class TriggerLevelValue extends TriggerValue {
  TriggerLevelValue(this.value);
  final double value; // inclusive 0..1
}

class TriggerHsvValue extends TriggerValue {
  TriggerHsvValue({
    required this.hue,        // inclusive 0..360 degrees
    required this.saturation, // inclusive 0..1
    required this.value,      // inclusive 0..1
  });
}
```

`triggerMonoAudio` accepts only `TriggerMonoAudioValue`; sample rate is always
present. `triggerArray` accepts the generic `TriggerArrayValue` and deliberately
has no audio metadata. `triggerHsv` carries a protocol-neutral HSV value rather
than an RGB/RGBW/CCT wire value. A `TriggerEvent` also contains source-port ID,
monotonic timestamp, sequence number, a primary value and an optional secondary
value. Display identifiers belong to port metadata, rather than being repeated
for every emitted event.

The graph retains typed `MacroTargetBinding` values as its transport-free
runtime delivery contract. The patcher no longer exposes a separate binding
form: an input-only device/group target node is placed on the graph, and each
edge to one of its `Power`, `Brightness` or `Color` inputs derives the matching
binding. Old saved bindings are migrated to target nodes when opened and saved.
The bridge converts a `triggerHsv → Color` binding to the shared RGB desired
state, then the existing device-calibration and protocol-command boundaries
apply. No macro module knows a protocol frame format.

## Modular architecture

Macro-graph contracts and trigger/modifier contracts are public, Flutter-free
and isolated from specific implementations. Concrete modules depend on those
contracts and are registered only at the composition root.

Each macro is one versioned JSON document under the app-support
`lazerus/macros` directory. The file-storage boundary keeps this location out
of the repository contract; malformed individual files are ignored, whereas an
I/O failure remains observable to the caller. A Scene stores only
typed `SceneMacroReference` values, so a missing macro file never mutates or
silently removes the saved Scene reference.

```text
packages/lazerus_core/lib/src/macros/
  contracts/       # macro graph, port declarations, bindings and schema
  triggers/
    contracts/     # trigger values, events and executor/factory API
  modifiers/
    contracts/     # modifier executor/factory API
  validation/      # pure type, missing-port, target and cycle validation
  runtime/         # graph compiler, routing interfaces, lifecycle contracts

apps/lazerus_app/lib/core/macros/
  registry/        # composition-root registration of concrete modules
  persistence/     # versioned local JSON repositories
  runtime/         # target expansion, stream binding, diagnostics and bridge
  triggers/
    microphone/    # implemented platform PCM16 mono source
    multiband_eq/  # implemented pure typed mono-audio processor
  modifiers/       # independently registered colour/transform modules
  sinks/           # input-only plot targets and lighting-intent mapping

apps/lazerus_app/lib/features/macros/
  application/     # Riverpod controllers
  presentation/    # library, editor, patcher canvas and inspectors
```

Each trigger/modifier exposes a definition, port declarations, parameter
schema, and executor/factory through a common registry interface. It must not
import a sibling trigger or modifier. The only permitted communication between
modules is an event across a validated graph edge. Removing a module leaves its
saved node and bindings detectable as unavailable/repairable; it must not
silently rewrite or delete macro JSON.

## Target nodes and initial colour modifiers

The palette contains registered source, trigger/modifier and discovered-device
entries. On desktop, an entry can be dragged onto the X/Y plot; a click adds it
at the next available position. Device nodes expose input ports only, based on
their currently declared capability profile. Therefore an unavailable colour,
brightness or power capability cannot be wired as though it worked.

`modifier.color` is a manual HSV source with a compact hue picker. It has no
input and emits a `triggerHsv` value. `modifier.color_brightness_combine` takes
one HSV input and one `triggerLevel` input; it replaces the HSV **Value**
component with that level and emits a new `triggerHsv` output. Its level input
is not a strip brightness command. Both outputs use ordinary graph edge
fan-out, so one colour source or combined colour can drive multiple compatible
inputs while any one input still permits only one source.

Colour delivery is converted at the application bridge to `RgbColor`, then
passes through existing per-device calibration and the selected protocol
adapter. This gives Lotus Lamp X the same macro colour route as ordinary colour
commands without coupling its package to macro contracts. A black HSV Value is
encoded as a black RGB frame, which has been reported to fully turn off the
locally tested strips; it is not substituted with the Lotus brightness command.
Device-specific limits and real strip response still require further hardware
validation.

## Graph and runtime rules

- Macro definitions are versioned local JSON with a schema version, stable
  macro/node/port/edge IDs, parameters, bindings and editor layout. Runtime
  subscriptions, DSP state and stream buffers are separate and never persisted.
- A graph is validated before run: known node kind, unique IDs, compatible
  input/output types, input cardinality, required bindings, live target
  capability, and no unrestricted cycles. Feedback requires a later explicit
  delay/state node.
- A macro has `created`, `validated`, `ready`, `running`, `stopped`, and
  `error` states. Start/stop is explicit; it does not claim automatic full
  Scene activation, priority or deactivation policy.
- Microphone capture, DSP and macro execution are outside Flutter build
  methods. Widgets consume sampled view state and diagnostics through
  controllers; they do not own audio subscriptions or BLE commands.
- Raw microphone data is transient. The app must request platform microphone
  permission, show denial/session errors, and never persist or export audio
  buffers as part of macro configuration.

## Initial Multiband EQ

The EQ has one `triggerMonoAudio` input and an ordered list of bands. Each band
has a stable ID, lower/upper frequency bounds, output mode, and smoothing.
Changing the number of bands must preserve compatible IDs where possible and
leave routes to removed outputs visibly broken.

- **Gate mode:** `threshold` in dBFS, hysteresis in dB, attack and release;
  output is a `triggerGate` value.
- **Level mode:** lower/upper normalisation bounds in dBFS, attack and
  release; output is `triggerLevel` in the inclusive range 0..1.
- A band's dBFS magnitude is the root-sum-of-squares of its selected DFT bins,
  not an average over their count. Therefore widening a band with empty bins
  does not move the Level minimum/maximum thresholds; e.g. `-54…-36 dBFS`
  starts increasing from `-54 dBFS` and reaches `1` at `-36 dBFS`.
- Persisted bands declare `amplitudeUnit: "dbfs"`. Legacy bands without that
  marker are decoded as the previous linear 0..1 values and converted to the
  bounded `-72…0 dBFS` scale (`0` becomes `-72 dBFS`); the next save writes
  the dBFS marker and values. This preserves existing macros while making the
  saved unit explicit.
- Each band has an `outputBufferMilliseconds` peak-hold window. The default is
  50 ms: a `Level` output emits the greatest normalized value sampled during
  the window, and a `Gate` output emits `true` if it was true at any point.
  `0` explicitly means immediate output. This is applied before target binding
  and the in-flight-first lighting bridge, so it bounds macro intent traffic
  without creating a BLE write queue.
- The spectrum view is a decimated display model, not the source of runtime
  calculation. It may resemble a multiband analyser, but must not copy a
  third-party product UI.

The graph editor displays the EQ spectrum and band handles in its node
inspector. On macOS, a pannable X/Y canvas lets users connect ports with a
mouse. iOS gets an accessible touch-safe presentation that preserves the same
graph and binding capabilities.

While a macro is running, the inspector receives a sampled in-memory analyzer
snapshot at most every 50 ms. The EQ plot uses frequency-addressable spectrum
bins on a dBFS vertical scale and overlays each configured band with its
frequency bounds, `Gate`/`Level` mode and its threshold or normalization
limits. This visual analyzer is diagnostic/presentation state only: it neither
changes EQ output nor becomes part of the saved macro definition.

The implemented EQ uses deterministic dependency-free DFT band energy for the
short PCM frames it receives. A buffered output is flushed when the next live
audio frame reaches its window boundary; no timer or pending output survives a
stopped runtime. This is a runtime coalescing policy, not a measured BLE rate
or latency claim. Invalid persisted band parameters are surfaced as a
repairable node-contract validation issue.

## Initial microphone source

`trigger.microphone.mono_audio` owns a `record`-backed `AudioRecorder` session
only while its macro node is running. It requests permission, starts a 44.1 kHz
mono PCM16 stream, normalises signed little-endian samples and emits transient
`TriggerMonoAudioValue` values. Permission denial and capture errors are
available through the microphone session status stream. Captured bytes are not
written to a file or included in macro persistence. iOS/macOS declare the
microphone usage text; macOS also declares the Audio Input sandbox entitlement.
This is integrated code, but real microphone capture and microphone-to-light
latency remain pending hardware validation.

The selected microphone trigger shows the corresponding sampled RMS input level
on a bounded `-72…0 dBFS` meter. The runtime immediately discards source PCM
after deriving this meter and the EQ analyzer snapshot; no audio samples,
audio level history or spectrum history are stored in macro JSON.

## Lighting delivery policy: in-flight first, no delivery guarantee

Macro outputs become `MacroLightingIntent` values; they never call a BLE
session, protocol adapter or widget directly. The scheduler expands a group to
current application device IDs, deduplicates them, rechecks capability and
connection state, and serializes writes per device.

For macro-triggered reactive output, the bridge permits exactly one pending or
in-flight write per device. Every newer value received before that write settles
is dropped; it neither replaces the active request nor changes the saved desired
state. After a `transmitted`, failed, rejected, timed-out or dropped result, the
next later macro value may be accepted. This avoids both a BLE animation backlog
and accidental command replacement. A newly accepted partial update still
merges into the most recently accepted desired output, so it does not erase a
previous colour or power parameter.

A write-without-response is only `transmitted` at the transport boundary. The
runtime records `queued`, `dropped`, `failed` or `timedOut` in
diagnostics as applicable, but must not present a macro reaction as a hardware
delivery or physical-state confirmation. Retrying an old animation value after
a newer one exists is prohibited.

## Delivery plan

### Task 1 — contracts, validation and persistence (complete)

Delivered immutable typed models, port/node interfaces, graph edges, target
bindings, one-file-per-macro JSON persistence and typed Scene references. Pure
tests cover JSON, deep immutability, type compatibility, missing-node/port,
invalid-target, cycle and persistence failure cases.

### Task 2 — runtime, registry and in-flight-first intent boundary (complete)

Delivered the `MacroModuleRegistry`, a transport-free runtime with explicit
`created → validated → ready → running → stopped/error` lifecycle, registered
port-contract validation, typed event routing and typed lighting intents. The
app bridge resolves live device/protocol/custom-group references, rechecks
connection/capability state before queueing and dispatch, and accepts one
in-flight device write while dropping subsequent macro values until it settles.
An explicit
stream binding connects a runtime to that bridge without making either lifecycle
implicit. `transmitted` is transport-only; it is never a physical-device
confirmation.

Tests are intentionally focused on contract conformance: one runtime
route/contract-mismatch case and one in-flight value-drop case. Existing
graph validation covers static incompatible connections and cycles; no device or
microphone behavior is claimed.

### Task 3 — microphone and Multiband EQ modules (complete)

Delivered `trigger.microphone.mono_audio` with an explicit PCM16 mono session,
permission/session status stream and deterministic little-endian sample decode.
Delivered an independent `trigger.multiband_eq` with dynamic node-derived
ports, serializable stable bands, gate/level modes, threshold/hysteresis,
normalisation, attack/release smoothing and a bounded output interval. The
registry now supports node-configured port contracts, so changing a saved band
set is validated precisely while an unavailable or malformed node remains
repairable. The composition root is the only code importing both modules.

Tests stay contract-focused: PCM-to-mono trigger conversion, EQ input/output
port correspondence and dynamic-port registry conformance. No synthetic
hardware, latency or exhaustive DSP test matrix was added.

### Task 4 — Scene workflow and patcher editor (complete)

The app has a Macros library and a Scene picker. A Scene persists only selected
macro IDs; absent files remain visible as missing, repairable references and
are never deleted as a side effect of loading or selecting a Scene.

`MacroEditorPage` creates an editable `Microphone → Multiband EQ` starter
graph. Its desktop X/Y patcher uses a click-to-patch flow: click any port to
start a cable, move the pointer without holding a button, then click another
port to validate and connect it. A click on an incompatible port or empty plot
cancels the pending cable. Clicking a connected port detaches its cable and
continues from the opposite endpoint, ready to be re-patched. When a port has
more than one cable, its context menu lists the connected node and input/output
indices so the intended cable is selected before detaching. Node titles also
include their plot index for this disambiguation. Touch has the equivalent
tap-to-start then tap-to-finish workflow.
Node positions, edges, bands, source settings and target-node-derived bindings
are saved with **Save**. Pressing **Start** also first saves the current editor
draft, then builds the runtime from that persisted version; this ensures a
visible source setting such as a Color modifier hue is the value the runtime
emits. While a macro is running the editor is read-only, so its graph cannot
silently diverge from the active runtime.

The EQ inspector exposes stable bands, gate/level mode and relevant threshold
or normalization values. It receives only an in-memory, derived spectrum view
from the running macro; PCM bytes are immediately discarded and are never
written to JSON, logs or diagnostic export. Dragging a module output to a
device input is the only way to create a target route: gate→power,
level→brightness and HSV→colour. A saved target can later disappear; its node
remains repairable and the delivery bridge rechecks live target, connection and
capability at send time.

The runtime panel presents validation issues and the latest delivery outcome.
It distinguishes `transmitted` from controller confirmation and preserves the
in-flight-first value-drop policy. Start and stop are explicit. Scene
selection does not yet mean automatic Scene activation, conflict arbitration or
an iOS background guarantee. While the editor is open, microphone
permission/capture status is shown without retaining its PCM data.

While running, each connected scalar output cable shows the latest `ON`/`OFF`
gate state, normalized `0..1` level or HSV hue above the cable. These are
transient UI values only; audio frames and output histories are neither
persisted nor exported. The IDE console also records each scalar/HSV binding
lifecycle under `Lazerus.MacroLightingDeliveryBridge` (macro, binding, target,
parameter, value and transport outcome), without logging microphone PCM.

## Verification

Each task runs focused tests, then from `apps/lazerus_app`:

```sh
flutter analyze
flutter test
flutter build macos --debug
```

Real-device validation must measure microphone-to-light latency and supported
device update rates before any performance, synchronisation or delivery claim
is made.
