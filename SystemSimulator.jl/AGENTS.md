# SystemSimulator Agent Instructions

Follow the workspace `../AGENTS.md`. This is the deterministic runtime used by all
plants and controllers.

- Preserve the `AbstractIO` contract, `AbstractSystem` hooks, signal namespacing,
  lifecycle behavior, logger ordering, and TCP handshake/frame ordering.
- Run runtimes with multiple Julia threads. Each IO owns reader/parser/writer
  tasks; global tasks include control, logging, monitoring, and shutdown.
- Keep steady-state loops allocation-free: bind names to slots at setup,
  preallocate buffers, avoid closure-based locking, and do not log in hot paths.
- Tests use mock IO/local TCP and are offline.
- Verify with `julia --threads=auto --project=. test/runtests.jl`.
