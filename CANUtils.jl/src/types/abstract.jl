"""
    AbstractCanMessage

Abstract base type for protocol-specific CAN message definitions.

Protocol-specific parsers (e.g. J1939Parser) must:
1. Define a concrete struct that subtypes `AbstractCanMessage`
2. Implement the interface functions below for their concrete type

Julia's multiple dispatch automatically routes calls to the correct implementation
based on the concrete message type.

# Required Interface

Any subtype `MyMessage <: AbstractCanMessage` must implement:

| Function | Signature |
|----------|-----------|
| [`decode!`](@ref) | `decode!(frame::CanFrame, msg::MyMessage, sigdict::Dict{String,Float64})` |
| [`match_and_decode!`](@ref) | `match_and_decode!(frame::CanFrame, msgs::Vector{MyMessage}, sigdict::Dict{String,Float64})` |
| [`encode`](@ref) | `encode(msg::MyMessage, sigdict::AbstractDict{String,<:Real})` |
| [`create_signal_dict`](@ref) | `create_signal_dict(msgs::Vector{MyMessage})` |

# Example

```julia
using CANUtils

struct MyProtocolMessage <: AbstractCanMessage
    name::String
    id::UInt32
    signals::Vector{Signal}
end

# Then implement decode!, match_and_decode!, encode, create_signal_dict
# for MyProtocolMessage.
```
"""
abstract type AbstractCanMessage end

"""
    decode!(frame::CanFrame, message::AbstractCanMessage, sigdict::Dict{String,Float64}) -> Dict{String,Float64}

Decode a CAN frame using the message definition, storing decoded physical values in `sigdict`.

Each signal in `message` is extracted from `frame.data`, converted to its physical value
via `raw * scaling + offset`, and written into `sigdict` under the signal's name.
Existing entries in `sigdict` are overwritten.

# Arguments
- `frame::CanFrame` — The CAN frame to decode.
- `message::AbstractCanMessage` — Message definition containing signal specifications.
- `sigdict::Dict{String,Float64}` — Dictionary to store/update decoded signal values.

# Returns
The updated `sigdict`.

# Example (using J1939Parser)

```julia
using J1939Parser

sig = Signal("EngineRPM", 1, 1, 16, 0.125, 0.0)
msg = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00), [sig])
frame = CanFrame(encode_can_id(msg.canid), UInt8[0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

sigdict = Dict{String,Float64}()
decode!(frame, msg, sigdict)
sigdict["EngineRPM"]  # 512.0  (raw 4096 * 0.125)
```
"""
function decode!(frame::CanFrame, message::AbstractCanMessage, sigdict::AbstractDict{String,Float64})
    error("decode! not implemented for message type: $(typeof(message))")
end

"""
    match_and_decode!(frame::CanFrame, messages::Vector{<:AbstractCanMessage}, sigdict::Dict{String,Float64}) -> Bool

Search `messages` for a definition that matches `frame`, and decode it if found.

This is the primary entry point for decoding incoming CAN traffic: pass in a frame and
your full list of message definitions, and the function finds the right one and decodes it.
How "matching" works depends on the protocol — e.g. J1939 matches on PF, PS, and SA fields.

# Arguments
- `frame::CanFrame` — The incoming CAN frame.
- `messages::Vector{<:AbstractCanMessage}` — All known message definitions to match against.
- `sigdict::Dict{String,Float64}` — Dictionary to store decoded signal values (modified in-place).

# Returns
- `true` if a matching message was found and `sigdict` was updated.
- `false` if no match was found (`sigdict` is unchanged).

# Example (using J1939Parser)

```julia
using J1939Parser

# Define two message types
eec1 = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00),
                  [Signal("EngineRPM", 1, 1, 16, 0.125, 0.0)])
etc1 = CanMessage("ETC1", CanId(3, 0xF0, 0x03, 0x00),
                  [Signal("TransGear", 1, 1, 8, 1.0, -125.0)])
messages = [eec1, etc1]

sigdict = create_signal_dict(messages)
frame = CanFrame(0x0CF00400, UInt8[0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

match_and_decode!(frame, messages, sigdict)  # true — matched EEC1
sigdict["EngineRPM"]  # decoded value
```
"""
function match_and_decode!(frame::CanFrame, messages::Vector{<:AbstractCanMessage}, sigdict::AbstractDict{String,Float64})
    error("match_and_decode! not implemented for message type: $(eltype(messages))")
end

"""
    encode(message::AbstractCanMessage, sigdict::AbstractDict{String,<:Real}) -> CanFrame

Encode physical signal values into a CAN frame using the message definition.

For each signal in `message`, the physical value is looked up in `sigdict`, converted to
a raw integer via `raw = (physical - offset) / scaling`, and packed into the correct bit
position in the 8-byte payload.

# Arguments
- `message::AbstractCanMessage` — Message definition with signal specifications.
- `sigdict::AbstractDict{String,<:Real}` — Dictionary mapping signal names → physical values.

# Returns
A [`CanFrame`](@ref) with the message's CAN ID and the encoded payload.

# Throws
- `KeyError` if a signal name from `message` is missing in `sigdict`.
- `ArgumentError` if scaling is zero, or if the raw value is negative or overflows the bit length.

# Example (using J1939Parser)

```julia
using J1939Parser

sig = Signal("EngineRPM", 1, 1, 16, 0.125, 0.0)
msg = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00), [sig])

sigdict = Dict("EngineRPM" => 1000.0)   # 1000 RPM
frame = encode(msg, sigdict)
# frame.data contains raw value 8000 (1000.0 / 0.125) packed into bytes 1-2
```
"""
function encode(message::AbstractCanMessage, sigdict::AbstractDict{String,<:Real})
    error("encode not implemented for message type: $(typeof(message))")
end

"""
    create_signal_dict(messages::Vector{<:AbstractCanMessage}, extra_names::Vector{String}=String[]) -> Dict{String,Float64}

Create a signal dictionary pre-populated with every signal name from `messages`, all
initialized to `0.0`. This dictionary is then passed to [`decode!`](@ref) or
[`match_and_decode!`](@ref) to receive decoded values.

# Arguments
- `messages::Vector{<:AbstractCanMessage}` — Message definitions whose signal names populate the dict.
- `extra_names::Vector{String}` — Additional keys to include (e.g. computed/derived signals).

# Returns
A `Dict{String,Float64}` with all signal names as keys, initialized to `0.0`.

# Example (using J1939Parser)

```julia
using J1939Parser

eec1 = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00),
                  [Signal("EngineRPM", 1, 1, 16, 0.125, 0.0),
                   Signal("EngineLoad", 3, 1, 8, 1.0, 0.0)])

sigdict = create_signal_dict([eec1])
# Dict("EngineRPM" => 0.0, "EngineLoad" => 0.0)
```
"""
function create_signal_dict(messages::Vector{<:AbstractCanMessage}, extra_names::Vector{String}=String[])
    error("create_signal_dict not implemented for message type: $(eltype(messages))")
end

"""
    message_match_key(msg::AbstractCanMessage) -> UInt32

Return a hash key used for O(1) indexed lookup of this message.
Protocol-specific: e.g. J1939 uses `canid & 0x00FFFFFF` (PF:PS:SA, ignoring priority/EDP/DP).
"""
function message_match_key(msg::AbstractCanMessage)::UInt32
    error("message_match_key not implemented for message type: $(typeof(msg))")
end

"""
    match_and_decode!(frame::CanFrame, index::Dict{UInt32,M}, sigdict::Dict{String,Float64}) where {M<:AbstractCanMessage} -> Bool

Hash-indexed variant of `match_and_decode!`. Looks up the frame's match key in `index`
for O(1) dispatch instead of linear scan.
"""
function match_and_decode!(frame::CanFrame, index::Dict{UInt32,M}, sigdict::AbstractDict{String,Float64}) where {M<:AbstractCanMessage}
    error("match_and_decode! not implemented for indexed lookup, message type: $(M)")
end
