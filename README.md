# SRTCore

Shared Julia infrastructure for SRT examples:

- `IO/CAN/Drivers/CANInterface.jl` — Linux SocketCAN transport
- `IO/CAN/Protocols/CANUtils.jl` — CAN signal and frame encoding
- `IO/CAN/Protocols/J1939Parser.jl` — J1939 message definitions and catalogs
- `IO/CAN/SRTCanAdapter.jl` — SystemSimulator CAN adapter
- `IO/TCP/SRTMonitorProtocol.jl` and `IO/TCP/SRTMonitorServer.jl` — monitor wire protocol and server
- `IO/File/SRTCSVLogger.jl` — buffered CSV logging
- `SystemSimulator.jl` — deterministic threaded runtime
- `UI/SRTBonito.jl` — TCP-connected Bonito dashboards

The packages are unregistered and use relative path dependencies. Keep
`SRTCore`, `DroneExample`, and `AcrobotExample` as sibling repositories.

See [AGENTS.md](AGENTS.md) for verification and safety requirements.
