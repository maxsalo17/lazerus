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
