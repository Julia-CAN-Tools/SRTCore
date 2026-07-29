"""
    Signal

Generic signal definition for CAN messages. Describes the bit layout and
physical-value conversion for a single signal within a CAN frame's 8-byte payload.

# Fields
- `name::String` — Human-readable signal name (must not be empty).
- `start_byte::UInt8` — Starting byte position in the payload (**1-indexed**, 1–8).
- `start_bit::UInt8` — Starting bit position within that byte (**1-indexed**, 1–8).
- `length::UInt8` — Signal length in bits (1–64). The signal must fit within the 64-bit payload.
- `scaling::Float64` — Multiplicative scaling factor for raw→physical conversion.
- `offset::Float64` — Additive offset for raw→physical conversion.

# Physical Value Conversion

    physical_value = raw_bits * scaling + offset
    raw_bits       = (physical_value - offset) / scaling

# Constructors

    Signal(name, start_byte, start_bit, length, scaling, offset)
    Signal()   # sentinel with name="", all positions 0, scaling=1.0, offset=0.0

# Examples

```julia
# A 16-bit engine RPM signal starting at byte 1, bit 1, with 0.125 RPM/bit resolution
rpm = Signal("EngineRPM", 1, 1, 16, 0.125, 0.0)

# An 8-bit temperature signal at byte 4, bit 1, with offset of -40°C
temp = Signal("CoolantTemp", 4, 1, 8, 1.0, -40.0)

# A 2-bit gear indicator at byte 1, bit 5 (bits 5-6 of byte 1)
gear = Signal("CurrentGear", 1, 5, 2, 1.0, 0.0)

# Default sentinel (used as a placeholder)
empty = Signal()
```
"""
struct Signal
    name::String
    start_byte::UInt8
    start_bit::UInt8
    length::UInt8
    scaling::Float64
    offset::Float64

    function Signal(name::AbstractString, start_byte::Integer, start_bit::Integer,
                    length::Integer, scaling::Real, offset::Real)
        isempty(name) && throw(ArgumentError("Signal name must not be empty"))
        (1 <= start_byte <= 8) || throw(ArgumentError(
            "Signal '$name': start_byte must be 1-8, got $start_byte"))
        (1 <= start_bit <= 8) || throw(ArgumentError(
            "Signal '$name': start_bit must be 1-8, got $start_bit"))
        (1 <= length <= 64) || throw(ArgumentError(
            "Signal '$name': length must be 1-64, got $length"))
        global_startbit = (start_byte - 1) * 8 + (start_bit - 1)
        (global_startbit + length <= 64) || throw(ArgumentError(
            "Signal '$name': signal exceeds 64-bit CAN data boundary " *
            "(start_byte=$start_byte, start_bit=$start_bit, length=$length)"))
        return new(String(name), UInt8(start_byte), UInt8(start_bit), UInt8(length),
                   Float64(scaling), Float64(offset))
    end

    function Signal()
        return new("", UInt8(0), UInt8(0), UInt8(0), 1.0, 0.0)
    end
end

function Base.show(io::IO, sig::Signal)
    println(io)
    println(io, "----------------------")
    println(io, "***** ", sig.name, " *****")
    println(io, "    StartByte: ", sig.start_byte)
    println(io, "    StartBit: ", sig.start_bit)
    println(io, "    Length: ", sig.length)
    println(io, "    Offset: ", sig.offset)
    println(io, "    Scaling: ", sig.scaling)
    println(io, "----------------------")
    return nothing
end
