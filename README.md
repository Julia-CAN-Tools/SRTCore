# SRTCore

Shared Julia infrastructure for SRT examples:

- `CANUtils.jl` — CAN signal and frame encoding
- `J1939Parser.jl` — J1939 message definitions and catalogs
- `CANInterface.jl` — Linux SocketCAN transport
- `SystemSimulator.jl` — deterministic threaded runtime
- `SRTBonito.jl` — TCP-connected Bonito dashboards

The packages are unregistered and use relative path dependencies. Keep
`SRTCore`, `DroneExample`, and `AcrobotExample` as sibling repositories.

See [AGENTS.md](AGENTS.md) for verification and safety requirements.
