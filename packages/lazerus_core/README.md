# lazerus_core

Transport-neutral lighting protocol contracts for Lazerus. The package contains
no Flutter widgets or platform API calls.

It defines:

- transport discovery, sessions, messages, receipts, and lifecycle contracts;
- protocol matching, probing, selection, and session contracts;
- common lighting commands and normalized lighting state;
- capability evidence (`verified`, `inferred`, or `unsupported`); and
- command and device-observation result models.

Protocol implementations depend on this package; transports and application UI
depend on its abstractions instead of a controller brand or BLE plugin. See the
repository's `docs/ARCHITECTURE.md` for the architecture decision and boundary
rules.
