"""
    J1939Parser

SAE J1939 protocol parser built on [`CANUtils`](@ref). Provides types and functions for
decoding and encoding J1939 CAN messages used in heavy-duty vehicles, trucks, buses, and
off-highway equipment.

# Overview

- **[`CanId`](@ref)** — J1939 29-bit identifier decomposed into Priority, EDP, DP, PF, PS, SA.
- **[`CanMessage`](@ref)** — Message definition linking a `CanId` to a set of [`Signal`](@ref) definitions.
- **[`pgn`](@ref)** — Extract the Parameter Group Number (PGN) from a `CanId` or raw ID.
- Implements the full CANUtils interface: [`decode!`](@ref), [`match_and_decode!`](@ref),
  [`encode`](@ref), [`create_signal_dict`](@ref).

# Quick Start

```julia
using J1939Parser

# Define signals for the Electronic Engine Controller 1 (EEC1) message
rpm_sig  = Signal("EngineRPM",  4, 1, 16, 0.125, 0.0)   # 16-bit, 0.125 RPM/bit
load_sig = Signal("EngineLoad", 3, 1,  8, 1.0,   0.0)    # 8-bit, 1%/bit

# Define the EEC1 message (PGN 0xF004, priority 3, SA 0x00)
eec1 = CanMessage("EEC1", CanId(3, 0xF0, 0x04, 0x00), [rpm_sig, load_sig])

# --- Decoding ---
sigdict = create_signal_dict([eec1])
frame = CanFrame(0x0CF00400, UInt8[0x00, 0x00, 0x50, 0x40, 0x1F, 0x00, 0x00, 0x00])
match_and_decode!(frame, [eec1], sigdict)
sigdict["EngineRPM"]   # decoded physical value
sigdict["EngineLoad"]  # decoded physical value

# --- Encoding ---
sigdict["EngineRPM"]  = 1500.0
sigdict["EngineLoad"] = 80.0
frame = encode(eec1, sigdict)

# --- CAN ID utilities ---
id = CanId(0x18FEF200)        # decode raw 29-bit ID
pgn(id)                        # extract PGN
encode_can_id(id)              # re-encode to UInt32
```

# J1939 Identifier Layout (29 bits)

    | Priority (3) | EDP (1) | DP (1) | PF (8) | PS (8) | SA (8) |
    |  bits 28-26  | bit 25  | bit 24 | 23-16  | 15-8   |  7-0   |

- **PF ≥ 0xF0 (PDU2)**: PS is a Group Extension → PGN = DP:PF:PS
- **PF < 0xF0 (PDU1)**: PS is a Destination Address → PGN = DP:PF (PS excluded)
"""
module J1939Parser

import CANUtils as CU
using CANUtils: CanFrame, Signal, AbstractCanMessage
using CANUtils: extract_bits, extract_signal, data_to_int
using CANUtils: add_bits, add_signal, uint_to_payload
using CANUtils: decode!, match_and_decode!, encode, create_signal_dict, message_match_key

using Printf
using PrecompileTools

# J1939 bit masks
const PRIORITY_MASK = UInt32(0x1c000000)
const EDP_MASK = UInt32(0x02000000)
const DP_MASK = UInt32(0x01000000)
const PF_MASK = UInt32(0x00ff0000)
const PS_MASK = UInt32(0x0000ff00)
const SA_MASK = UInt32(0x000000ff)
const PGN_MASK = UInt32(0x00ffff00)

# Include type definitions
include("types/CanId.jl")
include("types/CanMessage.jl")

# Include implementations
include("decoding.jl")
include("encoding.jl")

# Re-export CANUtils types for convenience
export CanFrame, Signal

# Export J1939-specific types
export CanId, CanMessage

# Export J1939-specific functions
export encode_can_id, decode_can_id, pgn

# Export interface implementations (also available via CU.decode! etc.)
export decode!, match_and_decode!, encode, create_signal_dict, message_match_key
export create_signal_dict_storage

@compile_workload begin
    # CanId constructors + utilities
    cid = CanId(UInt8(6), UInt8(0), UInt8(0), UInt8(0xFE), UInt8(0xCA), UInt8(0x00))
    cid2 = CanId(3, 0xF0, 0x04, 0x00)
    cid3 = CanId(UInt32(0x18FECA00))
    CanId()
    raw = encode_can_id(cid)
    decode_can_id(raw)
    pgn(cid)
    pgn(UInt32(0x18FECA00))

    # CanMessage construction
    sig = Signal("PrecompRPM", 1, 1, 16, 0.125, 0.0)
    msg = CanMessage("PrecompMsg", cid2, [sig])
    CanMessage()

    # create_signal_dict (with and without extra_names)
    sd = create_signal_dict([msg])
    sd2 = create_signal_dict([msg], ["Extra"])
    store = create_signal_dict_storage([msg])
    store2 = create_signal_dict_storage([msg], ["Extra"])

    # decode! / match_and_decode! / encode
    frame = CanFrame(encode_can_id(cid2), UInt8[0x40, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    CU.decode!(frame, msg, sd)
    CU.match_and_decode!(frame, [msg], sd)
    sd["PrecompRPM"] = 1000.0
    CU.encode(msg, sd)
end

end

