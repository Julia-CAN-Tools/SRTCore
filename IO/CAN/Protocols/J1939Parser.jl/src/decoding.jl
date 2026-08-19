# J1939 decoding - implements CANUtils interface

"""
    decode!(frame::CanFrame, message::CanMessage, sigdict::Dict{String,Float64}) -> Dict{String,Float64}

Decode a CAN frame using a J1939 [`CanMessage`](@ref) definition.

For each signal in `message.signals`, extracts the raw bits from `frame.data` and converts
to a physical value: `physical = raw * scaling + offset`. Results are written into `sigdict`
(existing keys are overwritten).

# Arguments
- `frame::CanFrame` — The CAN frame to decode.
- `message::CanMessage` — J1939 message definition with signal specs.
- `sigdict::Dict{String,Float64}` — Dictionary to receive decoded values (modified in-place).

# Returns
The updated `sigdict`.

# Example

```julia
sig = Signal("EngineRPM", 4, 1, 16, 0.125, 0.0)
msg = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00), [sig])
frame = CanFrame(encode_can_id(msg.canid), UInt8[0x00, 0x00, 0x00, 0x40, 0x1F, 0x00, 0x00, 0x00])

sigdict = Dict{String,Float64}()
decode!(frame, msg, sigdict)
sigdict["EngineRPM"]  # physical RPM value
```
"""
@inline function CU.decode!(frame::CanFrame, message::CanMessage, sigdict::AbstractDict{String,Float64})
    data_g = data_to_int(frame.data)
    for sig in message.signals
        sigbits = extract_signal(data_g, sig)
        sigdict[sig.name] = Float64(sigbits) * sig.scaling + sig.offset
    end
    return sigdict
end

"""
    match_and_decode!(frame::CanFrame, messages::Vector{CanMessage}, sigdict::Dict{String,Float64}) -> Bool

Find a matching J1939 message definition for `frame` and decode it into `sigdict`.

Matching is performed on **PF, PS, and SA fields only**. Priority, EDP, and DP are
intentionally ignored — the same PGN may appear at different priorities, and EDP/DP
rarely vary in practice. The first match in `messages` wins.

# Arguments
- `frame::CanFrame` — The incoming CAN frame.
- `messages::Vector{CanMessage}` — Known J1939 message definitions.
- `sigdict::Dict{String,Float64}` — Dictionary to receive decoded values (modified in-place).

# Returns
- `true` — a match was found and `sigdict` was updated.
- `false` — no match; `sigdict` is unchanged.

# Example

```julia
eec1 = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00),
                  [Signal("EngineRPM", 4, 1, 16, 0.125, 0.0)])
messages = [eec1]
sigdict = create_signal_dict(messages)

frame = CanFrame(0x0CF00400, UInt8[0x00, 0x00, 0x00, 0x40, 0x1F, 0x00, 0x00, 0x00])
matched = match_and_decode!(frame, messages, sigdict)  # true

# Unknown message → no match
frame2 = CanFrame(0x18FF0000, UInt8[0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
match_and_decode!(frame2, messages, sigdict)  # false
```
"""
@inline function CU.match_and_decode!(frame::CanFrame, messages::Vector{CanMessage}, sigdict::AbstractDict{String,Float64})
    rawid    = frame.canid
    frame_pf = UInt8((rawid >> 16) & 0xFF)
    frame_ps = UInt8((rawid >>  8) & 0xFF)
    frame_sa = UInt8( rawid        & 0xFF)

    for message in messages
        mid = message.canid
        if frame_pf == mid.pf && frame_ps == mid.ps && frame_sa == mid.sa
            CU.decode!(frame, message, sigdict)
            return true
        end
    end

    return false
end

"""
    message_match_key(msg::CanMessage) -> UInt32

J1939 match key: `canid & 0x00FFFFFF` (PF:PS:SA, ignoring Priority/EDP/DP).
"""
@inline function CU.message_match_key(msg::CanMessage)::UInt32
    return encode_can_id(msg.canid) & UInt32(0x00FFFFFF)
end

"""
    match_and_decode!(frame, index::Dict{UInt32,CanMessage}, sigdict) -> Bool

O(1) hash-indexed lookup variant. Key = `frame.canid & 0x00FFFFFF`.
"""
@inline function CU.match_and_decode!(frame::CanFrame, index::Dict{UInt32,CanMessage}, sigdict::AbstractDict{String,Float64})
    key = frame.canid & UInt32(0x00FFFFFF)
    msg = get(index, key, nothing)
    msg === nothing && return false
    CU.decode!(frame, msg, sigdict)
    return true
end
