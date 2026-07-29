# CANUtils Agent Instructions

Follow the workspace `../AGENTS.md`. This package defines the bit-level CAN signal
and frame representation used by downstream parsers, runtimes, and applications.

- Treat signal byte/bit numbering, scaling, offsets, signedness, DLC, and public
  constructors as compatibility-sensitive.
- Add boundary and round-trip tests for encoding/decoding changes, including
  invalid ranges and values at representation limits.
- This project has no reason to open a CAN interface during normal development.
- Verify offline with `julia --project=. test/runtests.jl`.
