# Macro system

## Scope

Macros are Lazerus's only multi-device automation surface. A macro is a
versioned, typed node graph that transforms transient signals into direct
device parameters. There is no separate Scene or Group target model and no
standalone Control screen: manual controls live on an individual device page,
while reactive control lives in the macro editor.

Macros do not own BLE sessions or protocol frames. They produce typed intents;
the application delivery bridge resolves the target device, applies calibration,
checks current capabilities and connection state, then sends the ordinary
lighting command through the active protocol session.

## First flow

```text
Microphone
  └─ triggerMonoAudio ──> Normalization
                              ├─ PCM ──> Multiband EQ
                              │             ├─ low level/gate ──> Device brightness/power
                              │             ├─ mid level/gate ──> Device brightness/power
                              │             └─ high level/gate ─> Device brightness/power
                              └─ Value ──> Device brightness

Colour source ──> Colour + brightness ──> Device colour
```

The microphone is only the first source. A future source may be registered if
it declares compatible ports; no node implementation imports or otherwise
knows about another node implementation.

## Typed contracts

Every port has a stable machine identifier, direction and one declared type.
Only an output can connect to an input, and their types must be compatible.
Input cardinality is validated before a runtime begins. Display labels are
editor metadata and do not determine routing.

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
```

`triggerMonoAudio` always includes a positive sample rate. `triggerArray` is a
generic array type and intentionally has no audio metadata. `triggerGate` is a
boolean, `triggerLevel` is normalized `0..1`, and `triggerHsv` carries a
protocol-neutral hue (`0..360`), saturation (`0..1`) and value (`0..1`).

`MacroTargetBinding` identifies a source port, a direct application device ID
and the target parameter (`power`, `brightness` or `color`). It has no target
kind discriminator. The input-only `sink.lighting_target` device node derives
these bindings from its incoming graph edges.

## Modular structure

```text
packages/lazerus_core/lib/src/macros/
  contracts/       # graph, ports, bindings and schema
  triggers/contracts/
  modifiers/contracts/
  validation/      # pure graph validation
  runtime/         # compiler, routing and lifecycle contracts

apps/lazerus_app/lib/core/macros/
  registry/        # only composition root for concrete modules
  persistence/     # local JSON storage
  runtime/         # delivery bridge and diagnostics
  triggers/        # microphone and multiband EQ implementations
  modifiers/       # independently registered modifier implementations
  sinks/           # device target mapping

apps/lazerus_app/lib/features/macros/
  application/
  presentation/
    node_modules/  # one isolated UI module per node family
```

Each trigger or modifier exposes its definition, port declarations, parameter
schema and executor through the common registry. It cannot import a sibling
module. The only inter-module communication is a typed event over a validated
edge. Removing an installed module leaves any saved node detectable and
repairable; it does not silently mutate saved JSON.

## Portable Macro templates

A Macro can be transferred as a versioned JSON template. Export replaces every
`sink.lighting_target` application-device ID and user-visible device name with
a template-local placeholder, while retaining the node ports, edges, editor
positions and reset policy. The template contains no BLE or installation-local
device identity.

Import validates the independent template schema and saves a Macro with a new
local ID. Its placeholders are visibly unresolved on the patcher canvas and
are skipped at runtime. Selecting a placeholder opens a capability-filtered
device chooser; the selection updates only that target node and preserves its
node and port IDs so the existing graph wiring remains intact. Other mapped
targets continue to run while a placeholder remains unresolved.

The Flutter editor follows the same boundary. It knows graph editing,
connection validation, persistence and runtime replacement, but not concrete
node types. A `MacroEditorNodeModule` owns one node family's palette entry,
creation, title, compact card, inspector and configuration changes. The node
module registry is the presentation composition root.

## Implemented modules

- `trigger.microphone.mono_audio` owns a PCM16 mono capture session only while
  its macro is running. It requests permission and emits transient audio data.
  PCM buffers are never persisted.
- `trigger.multiband_eq` accepts mono audio and exposes dynamic, persisted
  band outputs. A band emits a `triggerGate` or `triggerLevel` value.
- `modifier.normalization` accepts mono PCM and retains a transient rolling
  RMS dBFS range for the selected N-second window. Its persisted mode is
  either `pcm` (normalized `triggerMonoAudio` for further audio processing) or
  `value` (normalized `triggerLevel` in `0..1` for brightness/HSV Value).
  PCM buffers and the rolling history are never persisted. Changing modes
  updates the output port contract and removes only connections that are no
  longer type-compatible. Its inspector can show a transient, VSync-coalesced
  overlay: PCM input/output waves in `pcm` mode, or the input's fixed dBFS
  level and the normalized `0..1` value in `value` mode. The graph slider
  bounds retained data to its currently displayed time window; zooming out
  never restores discarded samples and may wait for the larger window to fill.
- `modifier.color` is a manual HSV source with a compact hue picker.
- `modifier.color_brightness_combine` takes HSV plus normalized level and
  replaces HSV Value; its output remains HSV.
- `modifier.strobe` accepts a gate and emits a brightness pulse with a
  persisted flash duration (100 ms by default).
- `sink.lighting_target` represents one discovered device and exposes only
  capability-supported inputs. It performs no I/O.

The EQ shows an in-memory dBFS spectrum while running. Its persisted bands have
frequency bounds, mode, threshold or level limits, smoothing and a peak-hold
output buffer. `0` milliseconds means immediate delivery; the default 50 ms
window emits the greatest level, or any `true` gate, observed in that interval.
The generic runtime forwards unbuffered raw `TriggerEvent`s only. The EQ
presentation module filters events to the source port connected to its own
input, derives its display spectrum, then renders through Flutter's VSync
ticker while dropping intermediate frames rather than queueing repaints.
Compact runtime telemetry and the microphone meter remain independently
rate-limited. Display telemetry does not affect the DSP calculation and is not
persisted.

The EQ visual module uses up to a 2,048-sample window and 256 logarithmically
spaced frequency points. `TriggerMonoAudioValue` always carries the source
sample rate, so its frequency axis is calculated from the actual capture rate.
At the default 44.1 kHz rate, a full window has approximately 21.5 Hz
frequency-bin resolution; smaller platform PCM frames cannot provide more
input resolution until a future rolling display window is introduced.

## Runtime and delivery

A graph is validated before it runs: node availability, IDs, port types,
input cardinality, direct-device bindings, target capabilities and cycle rules
must all be valid. Runtime states are `created`, `validated`, `ready`,
`running`, `stopped` and `error`.

Macros are editable while running. Valid runtime-relevant edits replace the
in-memory runtime after a short coalescing interval; invalid edits leave the
last valid runtime operating and appear in diagnostics. **Save** or **Cmd+S**
persists the current graph.

A target input takes priority over the matching manual control while it is
connected and values are arriving. Each Macro has a persisted **Reset on stop**
setting, enabled by default for compatibility with existing Macro files. When
enabled, stop first ends source events and lets an accepted write settle, then
sends a best-effort restore of the pre-macro desired state only for devices
actually changed by that Macro. When disabled, its last accepted state remains
active after stop.

Reactive output is deliberately best effort. The bridge permits exactly one
pending or in-flight write for a device. Values arriving while that write is
unsettled are dropped, not queued and not used to replace the write. A later
value may be accepted after the result settles. This prevents accumulated
animation delay. `transmitted` means the transport accepted the frame, not
that the controller physically applied it.

For HSV colour bindings, conversion to shared RGB happens in the app delivery
bridge, followed by the ordinary per-device calibration and protocol encoding
route. A black HSV Value is preserved for Lotus Lamp X as a black RGB frame;
it is not rewritten to a Lotus brightness command.

## Persistence

Each macro is a separate versioned JSON document below the application-support
`lazerus/macros` directory. It stores graph topology, node parameters, direct
device IDs, bindings and editor positions. Runtime subscriptions, event data,
audio buffers, analyzer history, BLE identifiers and controller confirmation
state are never saved.

Malformed individual documents are ignored without deleting other macro files;
an I/O failure remains observable to the caller. Legacy documents may contain
an obsolete `targetKind` field. It is ignored on read, and the next explicit
save writes the current device-only binding shape. A legacy target ID that is
not a current device produces a visible unresolved-target diagnostic and no
command.

## Verification

Automated checks intentionally focus on public graph contracts and module
conformance: serialization, type compatibility, runtime routing, dynamic EQ
port declarations and the in-flight delivery rule. Patcher gestures, audio
capture latency and physical-light response are manual or hardware validation,
not a broad synthetic widget-test suite.

Run from the respective package directories:

```sh
flutter analyze
flutter test
```

Before treating a macro path as hardware-validated, record the controller,
firmware, command path, sustained update rate and observed result in
[`BLE_PROTOCOLS.md`](BLE_PROTOCOLS.md).
