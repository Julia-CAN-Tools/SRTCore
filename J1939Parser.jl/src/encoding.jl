# J1939 encoding - implements CANUtils interface

@noinline function _throw_negative_raw(name, phys_val, raw_rounded, offset, scaling)
    throw(ArgumentError(
        "Signal '$(name)': physical value $(phys_val) yields negative raw value " *
        "$raw_rounded (below representable range for offset=$(offset), scaling=$(scaling))"))
end

@noinline function _throw_overflow_raw(name, raw_rounded, length, max_raw)
    throw(ArgumentError(
        "Signal '$(name)': raw value $raw_rounded exceeds $(length)-bit maximum ($max_raw)"))
end

"""
    encode(message::CanMessage, sigdict::AbstractDict{String,<:Real}) -> CanFrame

Encode physical signal values into a CAN frame using a J1939 [`CanMessage`](@ref) definition.

For each signal in `message.signals`:
1. Looks up the physical value in `sigdict` by signal name.
2. Converts to raw: `raw = round((physical - offset) / scaling)`.
3. Validates the raw value is non-negative and fits in the signal's bit length.
4. Packs the raw bits into the correct position in the 8-byte payload.

The resulting frame's CAN ID is computed from `message.canid` via [`encode_can_id`](@ref).

# Arguments
- `message::CanMessage` — J1939 message definition.
- `sigdict::AbstractDict{String,<:Real}` — Signal name → physical value mapping.

# Returns
A [`CanFrame`](@ref) with the encoded CAN ID and payload.

# Throws
- `KeyError` — if a signal name is missing from `sigdict`.
- `ArgumentError` — if `scaling == 0`, raw value is negative, or raw overflows the bit length.

# Example

```julia
sig = Signal("EngineRPM", 4, 1, 16, 0.125, 0.0)
msg = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00), [sig])

sigdict = Dict("EngineRPM" => 1500.0)
frame = encode(msg, sigdict)
# frame.canid == 0x0CF00400
# frame.data contains raw 12000 (1500.0 / 0.125) in bytes 4-5
```
"""
@inline function CU.encode(message::CanMessage, sigdict::AbstractDict{String,<:Real})
    data_g = UInt64(0)

    for sig in message.signals
        haskey(sigdict, sig.name) || throw(KeyError(sig.name))
        (sig.scaling == 0.0 || !isfinite(sig.scaling)) && throw(ArgumentError("Signal '$(sig.name)': scaling must be finite and non-zero, got $(sig.scaling)"))
        !isfinite(sig.offset) && throw(ArgumentError("Signal '$(sig.name)': offset must be finite, got $(sig.offset)"))

        raw = (Float64(sigdict[sig.name]) - sig.offset) / sig.scaling
        raw_rounded = round(Int64, raw)
        raw_rounded < 0 && _throw_negative_raw(sig.name, sigdict[sig.name], raw_rounded, sig.offset, sig.scaling)
        max_raw = sig.length >= 64 ? typemax(UInt64) : (UInt64(1) << sig.length) - UInt64(1)
        UInt64(raw_rounded) > max_raw && _throw_overflow_raw(sig.name, raw_rounded, sig.length, max_raw)
        sigbits = UInt64(raw_rounded)
        data_g = add_signal(data_g, sigbits, sig)
    end

    payload = uint_to_payload(data_g)

    return CanFrame(encode_can_id(message.canid), payload)
end

"""
    create_signal_dict(messages::Vector{CanMessage}) -> Dict{String,Float64}

Create a signal dictionary pre-populated with every signal name from the given J1939
messages, all initialized to `0.0`. Pass this dictionary to [`decode!`](@ref) or
[`match_and_decode!`](@ref) to receive decoded values.

# Arguments
- `messages::Vector{CanMessage}` — J1939 message definitions.

# Returns
A `Dict{String,Float64}` with all signal names as keys, initialized to `0.0`.

# Example

```julia
eec1 = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00),
                  [Signal("EngineRPM", 4, 1, 16, 0.125, 0.0),
                   Signal("EngineLoad", 3, 1, 8, 1.0, 0.0)])
sigdict = create_signal_dict([eec1])
# Dict("EngineRPM" => 0.0, "EngineLoad" => 0.0)
```
"""
function CU.create_signal_dict(messages::Vector{CanMessage}, extra_names::Vector{String}=String[])
    sigdict = Dict{String,Float64}()

    for message in messages
        for sig in message.signals
            sigdict[sig.name] = 0.0
        end
    end

    for name in extra_names
        sigdict[name] = 0.0
    end

    return sigdict
end

"""
    create_signal_dict_storage(messages::Vector{CanMessage}) -> Dict{String,Vector{Float64}}

Create a storage dictionary for recording signal time-series history. Each signal name
maps to an empty `Float64[]` vector. Use with [`store_sigdict!`](@ref) (from CANUtils) to
accumulate values over time for logging or plotting.

# Arguments
- `messages::Vector{CanMessage}` — J1939 message definitions.

# Returns
A `Dict{String,Vector{Float64}}` with all signal names as keys, each mapping to an empty vector.

# Example

```julia
eec1 = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00),
                  [Signal("EngineRPM", 4, 1, 16, 0.125, 0.0)])
storage = create_signal_dict_storage([eec1])
# Dict("EngineRPM" => Float64[])

# In a decode loop:
sigdict = create_signal_dict([eec1])
# ... decode frames into sigdict ...
store_sigdict!(sigdict, storage)  # appends current values
```
"""
function create_signal_dict_storage(messages::Vector{CanMessage}, extra_names::Vector{String}=String[])
    store = Dict{String,Vector{Float64}}()

    for message in messages
        for sig in message.signals
            store[sig.name] = Float64[]
        end
    end

    for name in extra_names
        store[name] = Float64[]
    end

    return store
end
