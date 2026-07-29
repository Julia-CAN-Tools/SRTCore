"""
    CANUtils

Generic CAN utilities and abstract interface for protocol-specific CAN parsers.

# Overview

CANUtils provides the building blocks for working with CAN bus data in Julia:

- **Types**: [`CanFrame`](@ref) (8-byte CAN frame), [`Signal`](@ref) (signal definition with
  bit layout and physical scaling), [`AbstractCanMessage`](@ref) (base type for protocol messages)
- **Interface functions**: [`decode!`](@ref), [`match_and_decode!`](@ref), [`encode`](@ref),
  [`create_signal_dict`](@ref) — implemented by protocol-specific packages (e.g. J1939Parser)
- **Bit-level utilities**: [`extract_bits`](@ref), [`extract_signal`](@ref), [`data_to_int`](@ref),
  [`add_bits`](@ref), [`add_signal`](@ref), [`uint_to_payload`](@ref)
- **History recording**: [`store_sigdict!`](@ref)

# Quick Start

```julia
using CANUtils

# Define a signal: name, start_byte (1-8), start_bit (1-8), length (bits), scaling, offset
rpm_signal = Signal("EngineRPM", 1, 1, 16, 0.125, 0.0)

# Create a CAN frame (ID + 8-byte payload)
frame = CanFrame(0x0CF00400, UInt8[0x00, 0x10, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

# Low-level extraction: convert payload to UInt64 and extract raw bits
data_g = data_to_int(frame.data)
raw = extract_signal(data_g, rpm_signal)
physical = Float64(raw) * rpm_signal.scaling + rpm_signal.offset
```

# Implementing a Protocol Parser

To add support for a new CAN protocol, create a package that:

1. Defines a concrete message type that subtypes [`AbstractCanMessage`](@ref)
2. Implements [`decode!`](@ref), [`match_and_decode!`](@ref), [`encode`](@ref),
   and [`create_signal_dict`](@ref) for the new message type

See `J1939Parser.jl` for a complete reference implementation.
"""
module CANUtils

using Printf
using PrecompileTools

# Include type definitions
include("types/Signal.jl")
include("types/CanFrame.jl")
include("types/abstract.jl")

# Include utilities
include("decoding.jl")
include("encoding.jl")

# Export types
export CanFrame, Signal, AbstractCanMessage

# Export interface functions (to be implemented by parsers)
export decode!, match_and_decode!, encode, create_signal_dict, message_match_key

# Export utility functions
export extract_bits, extract_signal, data_to_int
export add_bits, add_signal, uint_to_payload
export store_sigdict!

@compile_workload begin
    # Signal / CanFrame construction
    sig = Signal("PrecompSig", 1, 1, 16, 0.125, 0.0)
    sentinel = Signal()
    frame = CanFrame(UInt32(0x0CF00400), UInt8[0x40, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])

    # data_to_int (Vector and Tuple)
    data_g = data_to_int(frame.data)
    data_to_int((0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08))

    # extract_bits / extract_signal
    extract_bits(data_g, 0, 16)
    extract_signal(data_g, sig)

    # Sentinel no-op paths
    extract_signal(data_g, sentinel)

    # add_bits / add_signal / uint_to_payload
    dg = add_bits(UInt64(0), UInt64(0xFF), 0, 8)
    dg = add_signal(dg, UInt64(8000), sig)
    add_signal(dg, UInt64(0), sentinel)
    uint_to_payload(dg)

    # store_sigdict!
    sd = Dict("PrecompSig" => 0.0)
    st = Dict("PrecompSig" => Float64[])
    store_sigdict!(sd, st)

    # show methods (exercises Printf formatting paths)
    buf = IOBuffer()
    show(buf, sig)
    show(buf, frame)
end

end # module CANUtils
