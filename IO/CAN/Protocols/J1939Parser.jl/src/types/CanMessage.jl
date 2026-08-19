"""
    CanMessage <: AbstractCanMessage

J1939 message definition that links a [`CanId`](@ref) to a set of [`Signal`](@ref)
definitions. This is the concrete implementation of [`AbstractCanMessage`](@ref) for the
J1939 protocol.

# Fields
- `name::String` — Human-readable message name (e.g. "EEC1", "CCVS").
- `canid::CanId` — The J1939 identifier for this message.
- `signals::Vector{Signal}` — Signal definitions within the 8-byte payload.
  The signals vector is **copied** on construction (modifications to the original won't affect the message).

# Constructors

    CanMessage(name, canid, signals)   # full constructor
    CanMessage()                       # empty sentinel (name="", no signals)

# Examples

```julia
using J1939Parser

# Electronic Engine Controller 1 (EEC1) — PGN 0xF004
eec1 = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00), [
    Signal("EngineRPM",       4, 1, 16, 0.125, 0.0),
    Signal("DriverDemand",    2, 1,  8, 1.0,   0.0),
    Signal("ActualEngTorque", 3, 1,  8, 1.0,  -125.0),
])

# Cruise Control / Vehicle Speed (CCVS) — PGN 0xFEF1
ccvs = CanMessage("CCVS", CanId(6, 0xFE, 0xF1, 0x00), [
    Signal("VehicleSpeed", 2, 1, 16, 1/256, 0.0),
])

# Use in a decode loop
messages = [eec1, ccvs]
sigdict = create_signal_dict(messages)
```
"""
struct CanMessage <: AbstractCanMessage
    name::String
    canid::CanId
    signals::Vector{Signal}

    function CanMessage(name::AbstractString, canid::CanId, signals::Vector{Signal})
        seen = Set{String}()
        for sig in signals
            sig.name in seen && throw(ArgumentError(
                "CanMessage '$name': duplicate signal name '$(sig.name)'"))
            push!(seen, sig.name)
        end
        return new(String(name), canid, copy(signals))
    end

    function CanMessage()
        return new("", CanId(), Signal[])
    end
end

function Base.show(io::IO, msg::CanMessage)
    println(io)
    println(io, "=== CanMessage: ", msg.name, " ===")
    println(io, "  CAN ID: ", msg.canid)
    println(io, "  Signals: ", length(msg.signals))
    for sig in msg.signals
        println(io, "    - ", sig.name)
    end
    return nothing
end
