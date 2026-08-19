# SRTBonito Agent Instructions

Follow the workspace `../../AGENTS.md`. This package owns the shared Bonito/Plotly.js
UI foundation and TCP client for parameter input and signal streaming.

- Preserve the binary protocol: little-endian signal count, length-prefixed UTF-8
  names, and ordered `Float64` frames.
- Keep application parameter and plot definitions in their application
  repositories; this package owns only shared rendering, controls, transport, and
  layout behavior.
- Plotly.js is pinned locally in `assets/`; do not replace it with a CDN dependency
  or update it without preserving its license and testing browser initialization.
- Keep network work asynchronous and avoid blocking the UI/reactive event path.
- Tests use localhost mock servers and are offline; they must not require a
  running simulator or CAN interface.
- Verify with `julia --project=. test/runtests.jl`.
