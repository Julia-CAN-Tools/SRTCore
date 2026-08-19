"""
    CanId

J1939 29-bit CAN identifier, decomposed into its constituent fields.

# Fields
- `priority::UInt8` — Message priority (0–7, **lower is higher priority**).
- `edp::UInt8` — Extended Data Page (0 or 1). Usually 0.
- `dp::UInt8` — Data Page (0 or 1). Usually 0.
- `pf::UInt8` — PDU Format (0x00–0xFF). Determines PDU1 vs PDU2.
- `ps::UInt8` — PDU Specific (0x00–0xFF). Destination address (PDU1) or group extension (PDU2).
- `sa::UInt8` — Source Address (0x00–0xFF). The ECU that sent the message.

# Constructors

    CanId(priority, edp, dp, pf, ps, sa)       # all 6 fields (UInt8)
    CanId(priority, pf, ps, sa)                 # simplified (edp=0, dp=0)
    CanId(rawid::Integer)                       # decode from raw 29-bit CAN ID
    CanId()                                     # default (all zeros)

# Examples

```julia
# Simplified constructor: priority=3, PF=0xF0, PS=0x04, SA=0x00
id = CanId(3, 0xF0, 0x04, 0x00)

# From a raw 29-bit identifier (e.g. from a CAN log)
id = CanId(0x0CF00400)
id.priority  # 3
id.pf        # 0xF0
id.ps        # 0x04
id.sa        # 0x00

# Full constructor with EDP and DP
id = CanId(UInt8(6), UInt8(1), UInt8(1), UInt8(0xFE), UInt8(0xF2), UInt8(0x00))

# Round-trip: decode → encode
raw = 0x18FEF200
id = CanId(raw)
encode_can_id(id) == UInt32(raw)  # true
```
"""
struct CanId
    priority::UInt8
    edp::UInt8
    dp::UInt8
    pf::UInt8
    ps::UInt8
    sa::UInt8

    function CanId(priority::UInt8, edp::UInt8, dp::UInt8, pf::UInt8, ps::UInt8, sa::UInt8)
        priority <= 7 || throw(ArgumentError(
            "CanId: priority must be 0-7, got $priority"))
        edp <= 1 || throw(ArgumentError(
            "CanId: edp must be 0 or 1, got $edp"))
        dp <= 1 || throw(ArgumentError(
            "CanId: dp must be 0 or 1, got $dp"))
        return new(priority, edp, dp, pf, ps, sa)
    end

    # Raw bit-decode — bit extraction always produces valid values, skip validation
    @inline function CanId(rawid::Integer)
        r = UInt32(rawid)
        return new(
            UInt8((r >> 26) & 0x7),   # priority
            UInt8((r >> 25) & 0x1),   # edp
            UInt8((r >> 24) & 0x1),   # dp
            UInt8((r >> 16) & 0xFF),  # pf
            UInt8((r >>  8) & 0xFF),  # ps
            UInt8( r        & 0xFF),  # sa
        )
    end
end

"""
    CanId(priority::Integer, pf::Integer, ps::Integer, sa::Integer)

Simplified constructor that sets EDP=0 and DP=0 (the most common case in J1939).

# Example

```julia
id = CanId(3, 0xF0, 0x04, 0x00)  # EEC1 from SA 0x00
```
"""
function CanId(priority::Integer, pf::Integer, ps::Integer, sa::Integer)
    return CanId(UInt8(priority), UInt8(0), UInt8(0), UInt8(pf), UInt8(ps), UInt8(sa))
end


CanId() = CanId(UInt32(0))

function Base.show(io::IO, canid::CanId)
    println(io)
    println(io, "---------------------")
    println(io, "    Priority: ", canid.priority)
    println(io, "    DP: ", canid.dp)
    println(io, "    EDP: ", canid.edp)
    println(io, @sprintf("    PF: 0x%02X", canid.pf))
    println(io, @sprintf("    PS: 0x%02X", canid.ps))
    println(io, @sprintf("    SA: 0x%02X", canid.sa))
    println(io, "---------------------")
    return nothing
end

"""
    encode_can_id(canid::CanId) -> UInt32

Encode a [`CanId`](@ref) back to a raw 29-bit CAN identifier stored as `UInt32`.
This is the inverse of `CanId(rawid)` / [`decode_can_id`](@ref).

# Example

```julia
id = CanId(3, 0xF0, 0x04, 0x00)
raw = encode_can_id(id)  # 0x0CF00400
```
"""
@inline function encode_can_id(canid::CanId)
    return (UInt32(canid.priority) << 26) |
           (UInt32(canid.edp) << 25) |
           (UInt32(canid.dp) << 24) |
           (UInt32(canid.pf) << 16) |
           (UInt32(canid.ps) << 8) |
           UInt32(canid.sa)
end

"""
    decode_can_id(rawid::Integer) -> CanId

Decode a raw 29-bit CAN identifier into a [`CanId`](@ref). Equivalent to `CanId(rawid)`.

# Example

```julia
id = decode_can_id(0x18FEF200)
id.pf  # 0xFE
id.ps  # 0xF2
```
"""
@inline decode_can_id(rawid::Integer) = CanId(rawid)

"""
    pgn(canid::CanId) -> UInt32
    pgn(rawid::Integer) -> UInt32

Compute the Parameter Group Number (PGN) from a J1939 CAN identifier.

The PGN uniquely identifies the message type in J1939. Its computation depends on the
PDU format:

- **PDU2 (PF ≥ 0xF0)**: PS is a Group Extension → `PGN = (EDP << 17) | (DP << 16) | (PF << 8) | PS`
- **PDU1 (PF < 0xF0)**: PS is a Destination Address → `PGN = (EDP << 17) | (DP << 16) | (PF << 8)`

# Examples

```julia
# PDU2 example: PGN 0xFEF2 (Fuel Economy)
id = CanId(0x18FEF200)
pgn(id)  # 0x0000FEF2

# PDU1 example: PGN 0xEA00 (Request)
id = CanId(6, 0xEA, 0xFF, 0x00)
pgn(id)  # 0x0000EA00  (PS excluded)

# Directly from raw ID
pgn(0x0CF00400)  # 0x0000F004
```
"""
@inline function pgn(canid::CanId)
    base = (UInt32(canid.edp) << 17) | (UInt32(canid.dp) << 16) | (UInt32(canid.pf) << 8)
    if canid.pf >= 0xF0
        return base | UInt32(canid.ps)
    else
        return base
    end
end

"""
    pgn(rawid::Integer) -> UInt32

Compute the PGN from a raw 29-bit CAN identifier. Shorthand for `pgn(CanId(rawid))`.
"""
@inline pgn(rawid::Integer) = pgn(CanId(rawid))
