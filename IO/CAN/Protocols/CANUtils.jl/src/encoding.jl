# Generic bit addition utilities for CAN data encoding

"""
    add_bits(data_g::UInt64, sigbits::UInt64, startbit_g::Integer, length::Integer) -> UInt64

Insert `length` bits from `sigbits` at global bit position `startbit_g` in the 64-bit data
word. Overwrites existing bits at that position while preserving all other bits.

This is the inverse of [`extract_bits`](@ref) — you can round-trip data through
`add_bits` / `extract_bits` losslessly.

# Arguments
- `data_g::UInt64` — The existing 64-bit data word.
- `sigbits::UInt64` — The right-aligned bits to insert (must fit in `length` bits).
- `startbit_g::Integer` — Starting bit position (0-indexed from LSB).
- `length::Integer` — Number of bits to write.

# Returns
The updated data word with `sigbits` written at the specified position.

# Throws
- `ArgumentError` if the bit range exceeds 64 bits.
- `ArgumentError` if `sigbits` exceeds the maximum for `length` bits.

# Examples

```julia
data_g = UInt64(0)
data_g = add_bits(data_g, UInt64(0xFF), 0, 8)   # set byte 1 to 0xFF
data_g = add_bits(data_g, UInt64(0xAB), 8, 8)   # set byte 2 to 0xAB
extract_bits(data_g, 0, 16)  # 0xABFF
```
"""
@inline function add_bits(data_g::UInt64, sigbits::UInt64, startbit_g::Integer, length::Integer)
    length < 1 && return data_g
    (startbit_g >= 0 && startbit_g + length <= 64) || throw(ArgumentError(
        "Bit range [$startbit_g, $(startbit_g + length)) exceeds 64-bit data word"))
    max_val = length >= 64 ? typemax(UInt64) : (UInt64(1) << length) - UInt64(1)
    sigbits > max_val && throw(ArgumentError(
        "Signal value $sigbits exceeds maximum for $length bits (max=$max_val)"))
    maskbits = max_val
    mask = maskbits << startbit_g
    data_g &= ~mask
    data_g |= sigbits << startbit_g
    return data_g
end

"""
    add_signal(data_g::UInt64, sigbits::UInt64, sig::Signal) -> UInt64

Insert raw signal bits into a 64-bit data word at the position defined by a
[`Signal`](@ref). This is the encoding counterpart of [`extract_signal`](@ref).

Converts the signal's 1-indexed `(start_byte, start_bit)` to a 0-indexed global bit
position, then delegates to [`add_bits`](@ref).

# Arguments
- `data_g::UInt64` — The existing 64-bit data word.
- `sigbits::UInt64` — The raw signal value (before physical conversion).
- `sig::Signal` — Signal definition specifying the bit layout.

# Returns
The updated data word with the signal bits inserted.

# Example

```julia
sig = Signal("RPM", 1, 1, 16, 0.125, 0.0)
data_g = UInt64(0)
data_g = add_signal(data_g, UInt64(8000), sig)  # 1000 RPM / 0.125 = 8000 raw
payload = uint_to_payload(data_g)               # ready for CanFrame
```
"""
@inline function add_signal(data_g::UInt64, sigbits::UInt64, sig::Signal)
    sig.length == 0 && return data_g
    startbit_g = UInt64(sig.start_byte - 1) * UInt64(8) + UInt64(sig.start_bit - 1)
    return add_bits(data_g, sigbits, startbit_g, sig.length)
end

"""
    uint_to_payload(data_g::UInt64) -> NTuple{8,UInt8}

Convert a 64-bit integer back to an 8-byte CAN payload in little-endian byte order.
This is the inverse of [`data_to_int`](@ref).

# Arguments
- `data_g::UInt64` — The 64-bit data word.

# Returns
An `NTuple{8,UInt8}` suitable for constructing a [`CanFrame`](@ref).

# Example

```julia
data_g = UInt64(0x0807060504030201)
payload = uint_to_payload(data_g)
# payload == (0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)

# Round-trip
data_to_int(uint_to_payload(data_g)) == data_g  # true
```
"""
function uint_to_payload(data_g::UInt64)::NTuple{8,UInt8}
    return (
        UInt8( data_g        & 0xff),
        UInt8((data_g >>  8) & 0xff),
        UInt8((data_g >> 16) & 0xff),
        UInt8((data_g >> 24) & 0xff),
        UInt8((data_g >> 32) & 0xff),
        UInt8((data_g >> 40) & 0xff),
        UInt8((data_g >> 48) & 0xff),
        UInt8((data_g >> 56) & 0xff),
    )
end

"""
    store_sigdict!(sigdict::Dict{String,Float64}, storage::Dict{String,Vector{Float64}}) -> Dict{String,Vector{Float64}}

Append current signal values from `sigdict` to a time-series `storage` dictionary.

For each key in `sigdict`, the value is `push!`-ed onto the corresponding vector in
`storage`. If a key doesn't yet exist in `storage`, a new empty vector is created first.
Call this once per CAN frame / timestep to build up signal history for logging or plotting.

# Arguments
- `sigdict::Dict{String,Float64}` — Current decoded signal values (e.g. from [`decode!`](@ref)).
- `storage::Dict{String,Vector{Float64}}` — Accumulator for signal time-series.

# Returns
The updated `storage`.

# Example

```julia
sigdict = Dict("RPM" => 1500.0, "Temp" => 85.0)
storage = Dict("RPM" => Float64[], "Temp" => Float64[])

store_sigdict!(sigdict, storage)  # first sample
sigdict["RPM"] = 1600.0
store_sigdict!(sigdict, storage)  # second sample

storage["RPM"]   # [1500.0, 1600.0]
storage["Temp"]  # [85.0, 85.0]
```
"""
function store_sigdict!(sigdict::Dict{String,Float64}, storage::Dict{String,Vector{Float64}})
    for (key, value) in sigdict
        if !haskey(storage, key)
            storage[key] = Float64[]
        end
        push!(storage[key], value)
    end
    return storage
end
