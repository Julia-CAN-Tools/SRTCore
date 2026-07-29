# Generic bit extraction utilities for CAN data

"""
    extract_bits(data_g::UInt64, startbit_g::Integer, length::Integer) -> UInt64

Extract `length` bits starting at global bit position `startbit_g` from a 64-bit data word.

The data word `data_g` represents 8 CAN bytes packed in little-endian order (byte 1 in the
lowest 8 bits). Bits are numbered 0–63 from LSB.

# Arguments
- `data_g::UInt64` — The 64-bit data word (8 CAN bytes packed as little-endian).
- `startbit_g::Integer` — Starting bit position (0-indexed from LSB).
- `length::Integer` — Number of bits to extract (1–64).

# Returns
The extracted bits as a `UInt64`, right-aligned (i.e. shifted down to bit 0).
Returns `0` if `length < 1`.

# Throws
`ArgumentError` if the bit range `[startbit_g, startbit_g + length)` exceeds 64 bits.

# Examples

```julia
data_g = UInt64(0x00000000_0000FF03)

extract_bits(data_g, 0, 8)   # 0x03 — first byte
extract_bits(data_g, 8, 8)   # 0xFF — second byte
extract_bits(data_g, 0, 16)  # 0xFF03 — first two bytes
extract_bits(data_g, 4, 4)   # 0x00 — bits 4-7 of first byte
```
"""
@inline function extract_bits(data_g::UInt64, startbit_g::Integer, length::Integer)
    length < 1 && return UInt64(0)
    (startbit_g >= 0 && startbit_g + length <= 64) || throw(ArgumentError(
        "Bit range [$startbit_g, $(startbit_g + length)) exceeds 64-bit data word"))
    mask = length >= 64 ? typemax(UInt64) : (UInt64(1) << length) - UInt64(1)
    mask <<= startbit_g
    return (data_g & mask) >> startbit_g
end

"""
    extract_signal(data_g::UInt64, sig::Signal) -> UInt64

Extract raw signal bits from a 64-bit data word using a [`Signal`](@ref) definition.

Converts the signal's 1-indexed `(start_byte, start_bit)` to a 0-indexed global bit
position: `global_bit = (start_byte - 1) * 8 + (start_bit - 1)`, then delegates to
[`extract_bits`](@ref).

# Arguments
- `data_g::UInt64` — The 64-bit data word (from [`data_to_int`](@ref)).
- `sig::Signal` — Signal definition specifying bit layout.

# Returns
The raw signal bits as a `UInt64` (before applying scaling/offset).

# Example

```julia
sig = Signal("RPM", 1, 1, 16, 0.125, 0.0)  # 16 bits starting at byte 1, bit 1
data_g = data_to_int(UInt8[0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
raw = extract_signal(data_g, sig)  # 4096
physical = Float64(raw) * sig.scaling + sig.offset  # 512.0 RPM
```
"""
@inline function extract_signal(data_g::UInt64, sig::Signal)
    sig.length == 0 && return UInt64(0)
    startbit_g = UInt64(sig.start_byte - 1) * UInt64(8) + UInt64(sig.start_bit - 1)
    return extract_bits(data_g, startbit_g, sig.length)
end

@inline function _accumulate_bytes(iter)::UInt64
    value = UInt64(0)
    i = 0
    for byte in iter
        value += UInt64(byte) << (8 * i)
        i += 1
    end
    return value
end

"""
    data_to_int(data::AbstractVector{<:Integer}) -> UInt64
    data_to_int(data::NTuple{8,<:Integer}) -> UInt64

Convert an 8-byte CAN payload to a `UInt64` in little-endian byte order.

Byte 1 occupies bits 0–7 (LSB), byte 2 occupies bits 8–15, and so on. This is the
internal representation used by [`extract_bits`](@ref) and [`extract_signal`](@ref).

# Arguments
- `data` — An 8-element vector or tuple of bytes.

# Returns
The payload packed as a `UInt64`.

# Throws
`ArgumentError` if the vector is not exactly 8 bytes.

# Examples

```julia
data_to_int(UInt8[0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])  # UInt64(1)
data_to_int(UInt8[0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])  # UInt64(256)
data_to_int(UInt8[0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF])  # typemax(UInt64)

# Also works with tuples
data_to_int((0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08))
```
"""
function data_to_int(data::AbstractVector{<:Integer})
    length(data) == 8 || throw(ArgumentError("CAN frames require 8 bytes"))
    return _accumulate_bytes(data)
end

function data_to_int(data::NTuple{8,<:Integer})
    return _accumulate_bytes(data)
end
