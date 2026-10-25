# Spec: Normalization input/output waveform visualization

## Objective

Show the Normalization input and output on one overlaid time-domain graph in
its Macro inspector. The graph lets a user see the gain/dynamic-range effect
without saving, exporting or broadly retaining raw audio. A slider changes the
visible time window, referred to here as the display frame.

The graph displays two amplitude-level traces over the same `0..1` axis:

- **Input** — maximum absolute PCM amplitude from each N-sample window received
  by the Normalization input port.
- **Normalized** — the same maximum-amplitude aggregation of PCM frames emitted
  by that Normalization node.

It uses the unbuffered runtime-frame stream already exposed to node-presentation
modules. It does not change Macro runtime behavior, audio processing or device
delivery.

## Typed behavior

1. In `pcm` mode, the overlay contains original and normalized peak-amplitude
   envelopes on the shared `0..1` amplitude axis. Every point is the maximum
   absolute PCM amplitude over a contiguous N-sample window.
2. In `value` mode, the overlay is a `0..1` level timeline rather than a raw
   waveform. Each incoming PCM frame contributes its RMS dBFS level mapped from
   `-72..0 dBFS` to `0..1`; the second trace is the emitted
   `TriggerLevelValue` after rolling normalization. The two traces therefore
   have compatible units and directly show the normalization effect over time.
3. The default display frame is 5 seconds; the slider supports 50 ms through
   10 seconds in 50 ms increments. These are presentation settings only and are never persisted in
   the Macro or application settings.
4. A fixed 100 ms presentation delay separates the display cursor from the
   runtime clock. It ensures a frame's normalized output has arrived before
   that timestamp reaches the right edge of the graph.
5. In PCM mode, a separate non-persisted `Amplitude window` slider controls
   N from 50 through 44,000 samples; its default is 1,024 samples. A smaller
   N creates a denser peak envelope, while a larger N creates fewer,
   longer-duration amplitude points.
6. A `TriggerEvent.timestamp` denotes the end of its PCM frame for display
   placement. With a source sample rate, the display derives the frame start
   as `timestamp - sampleCount / sampleRateHz`.

## Bounded display buffer

The presentation module owns separate transient input/output buffers. PCM mode
stores cropped PCM frames; value mode stores only `(timestamp, level)` points.
For the currently selected display duration `D`:

- it retains no PCM samples whose time is older than `latestTimestamp - D`;
- a frame crossing that cutoff is cropped to retain only its visible samples;
- it retains no inactive-widget history: changing selection, stopping a Macro,
  or replacing the runtime stream disposes the buffers;
- the graph has a continuously advancing display clock. Each received frame is
  positioned according to its timestamp, enters at the right edge of the
  `D`-wide viewport, and scrolls left even if no later audio arrives;
- empty portions of the viewport stay empty: the UI never waits for a full
  window and never synthesizes a trace to fill a signal gap;
- expanding the slider never recreates discarded samples. Its newly revealed
  older portion is empty until new frames naturally pass through it;
- reducing the slider trims immediately to the smaller duration.

This means each trace uses at most the selected time horizon, even at the
slider maximum, plus the fixed 100 ms processing lead needed for the delayed
right edge. Rendering uses a temporary bounded/downsampled snapshot so a
large sample rate does not cause unbounded paint work. The Flutter `Ticker`
uses VSync to advance only the display cursor; it neither changes the Macro
runtime clock nor retains additional audio.

PCM aggregation is anchored to a stable N-sample range. Each rendered point
uses the maximum absolute PCM amplitude from its range, so the graph shows
levels rather than signed waveform oscillations. This changes no PCM frame or
Normalization DSP output.

## UI

The Normalization inspector gains a `Waveform` card below its output mode and
window fields:

```text
Waveform: [Overlay | Split]
[ 50 ms ----------- 5 s ----------- 10 s ]
┌──────────────────────────────────────────────┐
│ input peak level       (blue)                  │
│ normalized peak level  (amber, overlay/split)  │
└──────────────────────────────────────────────┘
[ Amplitude window: 50 samples --- 1024 --- 44000 samples ]
```

The card has an accessible label describing the current live time window. It
does not show a `Waiting` overlay. Its corner segment control switches between
the `Overlay` view and `Split` view, in which input and normalized traces use
parallel panels with a shared time axis. In `value` mode it labels the traces
as `Input level` and `Normalized value`, both on a `0..1` axis; that mode has
no PCM amplitude-window slider because no PCM output exists to aggregate.

## Tech stack and structure

- Flutter `StatefulWidget`, `Ticker`, `CustomPainter`, and a subscription to
  `MacroEditorNodePresentationState.runtimeFrames`.
- `TriggerMonoAudioValue`, `TriggerLevelValue`, and the Normalization node's
  declared input/output port IDs; no microphone, EQ or transport imports.
- A pure, unit-testable waveform-history buffer in the Normalization
  presentation folder.

```text
apps/lazerus_app/lib/features/macros/presentation/
  normalization_waveform_display.dart
  node_modules/normalization/normalization_macro_editor_node_module.dart
apps/lazerus_app/test/features/macros/presentation/
  normalization_waveform_display_test.dart
  node_modules/normalization_macro_editor_node_module_test.dart
```

## Code style

The buffer is presentation-only, explicitly bounded by the selected duration,
and produces immutable render snapshots. The ticker coalesces updates; PCM
events update the bounded buffer immediately but do not call `setState` per
audio frame.

```dart
buffer.addInput(event);
buffer.trimTo(displayDuration);
if (!_ticker.isActive) _ticker.start();
```

## Testing strategy

- Unit tests cover event-port filtering, frame/point timing, crop/trim
  boundaries, slider expansion without historic backfill, readiness after
  enough data, and a strict `retainedDuration <= selectedDuration` invariant
  for both traces.
- Unit tests cover a frame scrolling left and disappearing once its selected
  time horizon has passed. Widget tests cover the overlay/slider in PCM mode,
  the absence of a waiting reset after a zoom-out, and the `0..1`
  input-level/output-value display in value mode.
- Run `flutter analyze`, focused tests, full `flutter test`, and `flutter
  build macos --debug`.

## Boundaries

- Always: retain PCM only in the selected visible horizon, cancel stream/ticker
  resources, drop intermediate repaint requests, clamp painter data, and keep
  audio out of logs, persistence and diagnostics export.
- Ask first: persist display preferences, alter Macro graph contracts, add an
  audio dependency, or visualize a synthetic PCM signal for `value` mode.
- Never: retain a longer history to make zoom-out appear filled, modify DSP
  output for visualization, or route visualization audio to transport/device
  code.

## Success criteria

1. A PCM-mode Normalization inspector renders max-amplitude envelopes for the
   original and normalized PCM in Overlay or parallel Split view.
2. The display frame slider controls the maximum retained PCM time exactly.
3. Zooming out never reveals discarded audio/data. The graph continuously
   scrolls right-to-left, and its newly exposed older portion remains empty
   until new audio naturally occupies it.
4. Value mode overlays the fixed-range input level and rolling-normalized
   `0..1` output value over time without retaining PCM.
5. No visualization samples are persisted or retained after the inspector is
   disposed; analyzer, tests and macOS build succeed.
