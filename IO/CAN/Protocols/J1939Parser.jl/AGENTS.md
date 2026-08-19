# J1939Parser Agent Instructions

Follow the workspace `../../../../AGENTS.md`. This package owns J1939 identifier parsing and
message catalogs and depends on the local `CANUtils.jl`.

- Preserve 29-bit identifier layout, PDU1/PDU2 semantics, source/destination
  handling, and catalog signal scaling.
- Changes to catalogs or encoded IDs require decode/encode round-trip tests and a
  review of downstream application catalogs.
- Unit tests are offline and must not open SocketCAN.
- Verify with `julia --project=. test/runtests.jl`.
