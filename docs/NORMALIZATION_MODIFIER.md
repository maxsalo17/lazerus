# Spec: dual-mode Normalization Macro modifier

## Objective

Add a stateful `modifier.normalization` node that makes reactive lighting
respond to recent audio dynamics rather than to absolute microphone gain. It
accepts mono PCM in both modes and measures the RMS level of every audio frame
in dBFS over a configurable rolling window of `N` seconds.

The user selects one persisted output mode:

| Mode | Input | Output | Use |
| --- | --- | --- | --- |
| `pcm` | Mono PCM | Normalized mono PCM | Normalize audio before Multiband EQ or another audio processor. |
| `value` | Mono PCM | Normalized `0..1` level | Drive brightness or the Value input of a colour modifier directly. |

The default is `pcm`, so the node can form an audio chain:

```text
Microphone (PCM) -> Normalization / pcm -> Multiband EQ -> Lighting target
```

The value mode makes a direct control chain:

```text
Microphone (PCM) -> Normalization / value -> Brightness target
```

## Typed graph contract

Both modes have one input:

```text
audio input: triggerMonoAudio
```

The dynamic output is determined by `outputMode`:

```text
pcm mode:   normalized output: triggerMonoAudio
value mode: normalized output: triggerLevel (0..1)
```

`triggerMonoAudio` is the existing portable PCM contract. PCM samples are
always emitted in `-1.0..1.0` and preserve the input sample rate. `0..1` is a
control value, not PCM and not a new dB-valued graph type.

When the user changes mode, the editor rebuilds this node's output port
declaration and removes edges attached to that output if their type is no
longer compatible. It must not leave an invalid edge that later produces
`Needs repair` at runtime.

## Shared dynamic-range algorithm

For an incoming PCM frame `x` at monotonic runtime timestamp `t`:

1. Calculate frame RMS: `rms = sqrt(sum(x^2) / sampleCount)`.
2. Calculate `currentDb = clamp(20 * log10(rms), -72, 0)`. A silent frame is
   `-72 dBFS`.
3. Keep the transient pair `(t, currentDb)` for the last `N` seconds, evicting
   every entry with `timestamp < t - N`. The current frame is included before
   calculating the range.
4. Find `minimumDb` and `maximumDb` in the retained history. When their range
   is meaningful, calculate the normalized dynamic level:

   ```text
   normalized = clamp((currentDb - minimumDb) / (maximumDb - minimumDb), 0, 1)
   targetDb = -72 + 72 * normalized
   ```

   Thus the dynamic range maps to `-72..0 dBFS`, independently of the
   microphone's fixed gain.

5. If the range is effectively zero, use `normalized = 0`. This is the safe
   neutral value for the control mode while there is no detected dynamics.

The rolling dBFS history is bounded and is never written to Macro JSON. The
calculation uses runtime event timestamps, never wall-clock time.

## Mode-specific output behavior

### `pcm`

For silence, emit silence. For a non-silent frame with a meaningful rolling
range, convert `targetDb` to `targetRms`, derive `gain = targetRms / rms`, and
multiply every input sample by this gain. Clamp every result to `-1.0..1.0` to
keep valid PCM and prevent overflow. Preserve source port identity (as this
node's output port), timestamp, sequence and sample rate.

When no rolling dynamics exist yet, pass the PCM frame through while still
clamping samples. That avoids replacing a steady non-silent source with
artificial silence during startup. A peak clamp can make actual RMS lower than
the requested `targetDb`, but never above `0 dBFS`.

This is frame-level gain normalization, not sample-by-sample dB remapping: it
preserves waveform shape within a frame.

### `value`

Emit `TriggerLevelValue(normalized)`, preserving the incoming timestamp and
sequence. It represents the same `-72..0 dBFS` dynamic mapping as the PCM
mode, expressed in the Macro system's existing `0..1` control range. It can
connect to brightness or to the Value input of the colour-plus-brightness
modifier.

## Configuration and persistence

The immutable, typed configuration persists only:

```json
{
  "outputMode": "pcm",
  "windowDurationMilliseconds": 5000
}
```

`windowDurationMilliseconds` defaults to 5000 and accepts a bounded positive
whole-millisecond duration. Invalid mode/duration values cause a repairable
configuration error. Runtime PCM, dBFS history, gain and derived values are
not serialized.

## Tech stack

- `TriggerMonoAudioValue`, `TriggerLevelValue`, and typed Macro ports from
  `packages/lazerus_core`.
- A pure stateful modifier in `apps/lazerus_app/lib/core/macros`.
- Flutter editor node module, including mode and duration controls.
- Generic editor edge cleanup for any output-port type change.

## Planned files

```text
apps/lazerus_app/lib/core/macros/
  modifiers/normalization/normalization_modifier.dart
  registry/macro_module_registry.dart
apps/lazerus_app/lib/features/macros/presentation/
  macro_editor_page.dart
  node_modules/normalization/normalization_macro_editor_node_module.dart
  node_modules/macro_editor_node_registry.dart
apps/lazerus_app/test/core/macros/modifiers/
  normalization_modifier_test.dart
apps/lazerus_app/test/features/macros/presentation/node_modules/
  normalization_macro_editor_node_module_test.dart
apps/lazerus_app/test/features/macros/presentation/
  macro_editor_page_test.dart
```

## Testing strategy

- Configuration defaults, serialization and invalid-value rejection.
- Port declarations for both modes and mode-specific runtime values.
- RMS dBFS calculation, exact `N`-window expiry, `-72..0` mapping, silent
  input, zero-range behavior, PCM peak protection and sample-rate preservation.
- Equivalent relative dynamics at quiet and loud microphone gains produce
  equivalent normalized levels after the rolling window has populated.
- Mode change rebuilds ports and removes now-incompatible connected edges.
- Full analyzer, full Flutter tests and a macOS debug build; real microphone
  behavior remains a documented manual validation.

## Boundaries

- Always keep PCM/audio history transient, preserve source timing metadata,
  avoid microphone/transport/widget dependencies in the modifier, and clamp
  emitted PCM.
- Never persist PCM or frame history, expose PCM in logs/telemetry, perform raw
  GATT writes, or alter behaviour of other modules.

## Success criteria

1. The Macro palette has one Normalization node with output mode and rolling
   window `N` controls.
2. PCM mode is `triggerMonoAudio -> triggerMonoAudio`; value mode is
   `triggerMonoAudio -> triggerLevel`.
3. Both modes use the same rolling `-72..0 dBFS` dynamic mapping.
4. The value mode always emits a finite `0..1` signal; PCM mode always emits
   finite PCM values in `-1.0..1.0` and preserves its sample rate.
5. A mode change never leaves an incompatible graph edge behind.
