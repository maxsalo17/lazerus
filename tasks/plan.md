# Plan: per-device hue calibration

1. Add pure, protocol-scoped hue-calibration models plus a versioned local JSON
   repository and tests.
2. Add a Riverpod controller for profile assignment and temporary preview
   mappings, then apply its mapping at the command/protocol boundary.
3. Add Devices multi-selection and a calibration editor with an interactive
   curve, profile dropdown, preview, reset, and save.
4. Update architecture/data/testing documentation and run app/package checks.

## Plan: Scene control surfaces

1. Define and persist typed Scene composition, slotted controls and bindings.
   References stay indirect so group membership and device capability are
   resolved live.
2. Add Scene library and Settings/editor workflows, including creation,
   modification and deletion of custom-control slots.
3. Add Scene detail rendering and capability-aware one-to-many command
   dispatch, then validate deduplication, ticker behaviour and recovery states.

## Plan: Scene macros and trigger graph

1. Define versioned, immutable macro/trigger contracts and JSON persistence:
   typed ports, values, events, graph nodes/edges, target bindings, validation,
   and Scene references to saved macro IDs.
2. Build the transport-independent macro graph runtime and registry, including
   typed routing, explicit lifecycle, deterministic validation, and a bounded
   latest-wins lighting-intent scheduler that does not claim device delivery.
3. Implement the first independent trigger modules: microphone mono-audio
   source and Multiband EQ. The EQ accepts only mono-audio trigger arrays and
   emits one gate or level output per configured band.
4. Add saved-macro selection to Scene, target parameter bindings, and a
   patcher-style graph editor with Spectrum/EQ configuration and diagnostics.

## Plan: portable Macro templates

1. Define an independent, versioned template JSON contract and pure graph
   transformer that removes every source-device reference and creates stable
   per-target placeholders.
2. Add validated import/export orchestration at the Macro-library boundary,
   using the approved system file or clipboard interaction mechanism.
3. Extend the lighting-target editor module to render unresolved placeholders
   and explicitly replace one with a capability-compatible discovered device.
4. Cover contract, import error, mapping and widget flows; document format and
   run Flutter checks.

## Plan: dual-mode PCM Normalization modifier

1. Add a typed, transient normalization modifier with an `N`-second dBFS RMS
   history and dynamic `pcm` / `value` output-port contracts.
2. Register the module in runtime and editor composition roots, then expose
   mode and window-duration controls in a dedicated inspector.
3. Update generic editor replacement to remove connections whose port type
   changes, preventing stale incompatible edges after a mode switch.
4. Cover DSP, ports, configuration, editor behavior and graph cleanup with
   focused tests; update Macro documentation and run Flutter verification.

## Plan: Normalization waveform visualization

1. Add a presentation-only, duration-bounded history for overlaying PCM
   input/output frames and `0..1` input/output level points.
2. Add a VSync-coalesced waveform card plus display-duration slider to the
   Normalization inspector, consuming only its connected runtime frame ports.
3. Prove trim, zoom-out and mode behavior with focused tests; document the
   no-backfill/no-persistence limits and run Flutter verification.
