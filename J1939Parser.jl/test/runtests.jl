using Test
using J1939Parser

@testset "J1939Parser" begin

    # =========================================================================
    # CanId
    # =========================================================================
    @testset "CanId" begin
        @testset "full constructor" begin
            cid = CanId(UInt8(6), UInt8(0), UInt8(0), UInt8(0xFF), UInt8(0xCA), UInt8(0xFE))
            @test cid.priority == 0x06
            @test cid.edp == 0x00
            @test cid.dp == 0x00
            @test cid.pf == 0xFF
            @test cid.ps == 0xCA
            @test cid.sa == 0xFE
        end

        @testset "simplified constructor (priority, pf, ps, sa)" begin
            cid = CanId(6, 0xFF, 0x00, 0xFE)
            @test cid.priority == 0x06
            @test cid.edp == 0x00
            @test cid.dp == 0x00
            @test cid.pf == 0xFF
            @test cid.ps == 0x00
            @test cid.sa == 0xFE
        end

        @testset "default constructor" begin
            cid = CanId()
            @test cid.priority == 0x00
            @test cid.pf == 0x00
            @test cid.ps == 0x00
            @test cid.sa == 0x00
        end

        @testset "construct from raw id" begin
            # Raw ID: priority=6 (0b110), edp=0, dp=0, pf=0xFE, ps=0xCA, sa=0x00
            # 0b110_0_0_11111110_11001010_00000000 = 0x18FECA00
            rawid = UInt32(0x18FECA00)
            cid = CanId(rawid)
            @test cid.priority == 6
            @test cid.edp == 0
            @test cid.dp == 0
            @test cid.pf == 0xFE
            @test cid.ps == 0xCA
            @test cid.sa == 0x00
        end

        @testset "encode_can_id" begin
            cid = CanId(6, 0xFE, 0xCA, 0x00)
            raw = encode_can_id(cid)
            @test raw == UInt32(0x18FECA00)
        end

        @testset "decode_can_id" begin
            cid = decode_can_id(0x18FECA00)
            @test cid.priority == 6
            @test cid.pf == 0xFE
            @test cid.ps == 0xCA
            @test cid.sa == 0x00
        end

        @testset "encode/decode round-trip" begin
            cid = CanId(UInt8(3), UInt8(1), UInt8(1), UInt8(0xAB), UInt8(0xCD), UInt8(0xEF))
            raw = encode_can_id(cid)
            cid2 = decode_can_id(raw)
            @test cid2.priority == cid.priority
            @test cid2.edp == cid.edp
            @test cid2.dp == cid.dp
            @test cid2.pf == cid.pf
            @test cid2.ps == cid.ps
            @test cid2.sa == cid.sa
        end

        @testset "all fields exercised in round-trip" begin
            for priority in [0, 3, 7]
                for edp in [0, 1]
                    for dp in [0, 1]
                        cid = CanId(UInt8(priority), UInt8(edp), UInt8(dp),
                                    UInt8(0xF0), UInt8(0x0F), UInt8(0xAA))
                        raw = encode_can_id(cid)
                        cid2 = CanId(raw)
                        @test cid2.priority == priority
                        @test cid2.edp == edp
                        @test cid2.dp == dp
                        @test cid2.pf == 0xF0
                        @test cid2.ps == 0x0F
                        @test cid2.sa == 0xAA
                    end
                end
            end
        end

        @testset "show" begin
            cid = CanId(6, 0xFE, 0xCA, 0x00)
            buf = IOBuffer()
            show(buf, cid)
            s = String(take!(buf))
            @test contains(s, "Priority")
            @test contains(s, "PF")
            @test contains(s, "0xFE")
        end

        @testset "validation" begin
            @test_throws ArgumentError CanId(UInt8(8), UInt8(0), UInt8(0), UInt8(0), UInt8(0), UInt8(0))  # priority > 7
            @test_throws ArgumentError CanId(UInt8(0), UInt8(2), UInt8(0), UInt8(0), UInt8(0), UInt8(0))  # edp > 1
            @test_throws ArgumentError CanId(UInt8(0), UInt8(0), UInt8(2), UInt8(0), UInt8(0), UInt8(0))  # dp > 1
            # Valid edge cases
            @test CanId(UInt8(7), UInt8(1), UInt8(1), UInt8(0xFF), UInt8(0xFF), UInt8(0xFF)) isa CanId
            @test CanId() isa CanId
        end
    end

    # =========================================================================
    # CanMessage
    # =========================================================================
    @testset "CanMessage" begin
        @testset "construction" begin
            sigs = [
                Signal("EngineSpeed", 4, 1, 16, 0.125, 0.0),
                Signal("Torque", 2, 1, 8, 1.0, -125.0),
            ]
            msg = CanMessage("EEC1", CanId(6, 0xF0, 0x04, 0x00), sigs)
            @test msg.name == "EEC1"
            @test msg.canid.pf == 0xF0
            @test length(msg.signals) == 2
            @test msg.signals[1].name == "EngineSpeed"
        end

        @testset "signals are copied" begin
            sigs = [Signal("A", 1, 1, 8, 1.0, 0.0)]
            msg = CanMessage("Test", CanId(), sigs)
            push!(sigs, Signal("B", 2, 1, 8, 1.0, 0.0))
            @test length(msg.signals) == 1  # original unaffected
        end

        @testset "default constructor" begin
            msg = CanMessage()
            @test msg.name == ""
            @test length(msg.signals) == 0
        end

        @testset "show" begin
            msg = CanMessage("EEC1", CanId(6, 0xF0, 0x04, 0x00),
                             [Signal("Speed", 1, 1, 8, 1.0, 0.0)])
            buf = IOBuffer()
            show(buf, msg)
            s = String(take!(buf))
            @test contains(s, "EEC1")
            @test contains(s, "Speed")
        end
    end

    # =========================================================================
    # decode!
    # =========================================================================
    @testset "decode!" begin
        @testset "single signal" begin
            sig = Signal("RPM", 1, 1, 16, 0.125, 0.0)
            msg = CanMessage("EEC1", CanId(6, 0xF0, 0x04, 0x00), [sig])

            # Raw value 8000 → RPM = 8000 * 0.125 = 1000.0
            # 8000 = 0x1F40 → little-endian bytes: [0x40, 0x1F, ...]
            data = UInt8[0x40, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            frame = CanFrame(encode_can_id(msg.canid), data)

            sigdict = Dict{String,Float64}()
            result = decode!(frame, msg, sigdict)
            @test result === sigdict
            @test sigdict["RPM"] ≈ 1000.0
        end

        @testset "signal with offset" begin
            sig = Signal("Torque", 1, 1, 8, 1.0, -125.0)
            msg = CanMessage("Test", CanId(), [sig])

            # Raw value 200 → Torque = 200 * 1.0 + (-125.0) = 75.0
            data = UInt8[200, 0, 0, 0, 0, 0, 0, 0]
            frame = CanFrame(0x00, data)

            sigdict = Dict{String,Float64}()
            decode!(frame, msg, sigdict)
            @test sigdict["Torque"] ≈ 75.0
        end

        @testset "multiple signals" begin
            sigs = [
                Signal("A", 1, 1, 8, 1.0, 0.0),   # byte 1
                Signal("B", 2, 1, 8, 2.0, 10.0),   # byte 2
                Signal("C", 3, 1, 16, 0.5, -100.0), # bytes 3-4
            ]
            msg = CanMessage("Multi", CanId(), sigs)

            # A: raw=100, B: raw=50, C: raw=500 (0x01F4)
            data = UInt8[100, 50, 0xF4, 0x01, 0, 0, 0, 0]
            frame = CanFrame(0x00, data)

            sigdict = Dict{String,Float64}()
            decode!(frame, msg, sigdict)
            @test sigdict["A"] ≈ 100.0       # 100 * 1.0 + 0.0
            @test sigdict["B"] ≈ 110.0       # 50 * 2.0 + 10.0
            @test sigdict["C"] ≈ 150.0       # 500 * 0.5 + (-100.0)
        end

        @testset "overwrites existing sigdict values" begin
            sig = Signal("Val", 1, 1, 8, 1.0, 0.0)
            msg = CanMessage("Test", CanId(), [sig])

            sigdict = Dict("Val" => 999.0)
            frame = CanFrame(0x00, UInt8[42, 0, 0, 0, 0, 0, 0, 0])
            decode!(frame, msg, sigdict)
            @test sigdict["Val"] ≈ 42.0
        end
    end

    # =========================================================================
    # match_and_decode!
    # =========================================================================
    @testset "match_and_decode!" begin
        msg1 = CanMessage("EEC1", CanId(6, 0xF0, 0x04, 0x00),
                          [Signal("RPM", 1, 1, 16, 0.125, 0.0)])
        msg2 = CanMessage("ETC1", CanId(6, 0xF0, 0x03, 0x00),
                          [Signal("Gear", 1, 1, 8, 1.0, -125.0)])
        messages = [msg1, msg2]

        @testset "matches correct message" begin
            # Frame matching msg1 (pf=0xF0, ps=0x04, sa=0x00)
            data = UInt8[0x40, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            frame = CanFrame(encode_can_id(CanId(6, 0xF0, 0x04, 0x00)), data)

            sigdict = Dict{String,Float64}()
            matched = match_and_decode!(frame, messages, sigdict)
            @test matched == true
            @test haskey(sigdict, "RPM")
            @test sigdict["RPM"] ≈ 1000.0
        end

        @testset "matches second message" begin
            data = UInt8[200, 0, 0, 0, 0, 0, 0, 0]
            frame = CanFrame(encode_can_id(CanId(6, 0xF0, 0x03, 0x00)), data)

            sigdict = Dict{String,Float64}()
            matched = match_and_decode!(frame, messages, sigdict)
            @test matched == true
            @test sigdict["Gear"] ≈ 75.0
        end

        @testset "no match returns false" begin
            data = zeros(UInt8, 8)
            frame = CanFrame(encode_can_id(CanId(6, 0xFF, 0xFF, 0xFF)), data)

            sigdict = Dict{String,Float64}()
            matched = match_and_decode!(frame, messages, sigdict)
            @test matched == false
            @test isempty(sigdict)
        end

        @testset "matches by pf/ps/sa ignoring priority" begin
            # Same pf/ps/sa as msg1 but different priority
            data = UInt8[0x40, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            frame = CanFrame(encode_can_id(CanId(3, 0xF0, 0x04, 0x00)), data)

            sigdict = Dict{String,Float64}()
            matched = match_and_decode!(frame, messages, sigdict)
            @test matched == true
            @test sigdict["RPM"] ≈ 1000.0
        end
    end

    # =========================================================================
    # encode
    # =========================================================================
    @testset "encode" begin
        @testset "single signal" begin
            sig = Signal("RPM", 1, 1, 16, 0.125, 0.0)
            msg = CanMessage("EEC1", CanId(6, 0xF0, 0x04, 0x00), [sig])

            sigdict = Dict("RPM" => 1000.0)
            frame = encode(msg, sigdict)

            @test frame.canid == encode_can_id(msg.canid)
            # 1000.0 / 0.125 = 8000 = 0x1F40 → LE bytes [0x40, 0x1F]
            @test frame.data[1] == 0x40
            @test frame.data[2] == 0x1F
        end

        @testset "signal with offset" begin
            sig = Signal("Torque", 1, 1, 8, 1.0, -125.0)
            msg = CanMessage("Test", CanId(6, 0xF0, 0x03, 0x00), [sig])

            sigdict = Dict("Torque" => 75.0)
            frame = encode(msg, sigdict)
            # (75.0 - (-125.0)) / 1.0 = 200
            @test frame.data[1] == 200
        end

        @testset "negative raw throws ArgumentError" begin
            sig = Signal("Val", 1, 1, 8, 1.0, 0.0)
            msg = CanMessage("Test", CanId(), [sig])
            sigdict = Dict("Val" => -50.0)
            @test_throws ArgumentError encode(msg, sigdict)
        end

        @testset "overflow throws ArgumentError" begin
            sig = Signal("Val", 1, 1, 8, 1.0, 0.0)
            msg = CanMessage("Test", CanId(), [sig])
            sigdict = Dict("Val" => 256.0)  # 256 exceeds 8-bit max (255)
            @test_throws ArgumentError encode(msg, sigdict)
        end

        @testset "multiple signals" begin
            sigs = [
                Signal("A", 1, 1, 8, 1.0, 0.0),
                Signal("B", 2, 1, 8, 1.0, 0.0),
            ]
            msg = CanMessage("Test", CanId(), sigs)

            sigdict = Dict("A" => 0xAA * 1.0, "B" => 0xBB * 1.0)
            frame = encode(msg, sigdict)
            @test frame.data[1] == 0xAA
            @test frame.data[2] == 0xBB
        end

        @testset "missing signal throws KeyError" begin
            sig = Signal("Missing", 1, 1, 8, 1.0, 0.0)
            msg = CanMessage("Test", CanId(), [sig])
            @test_throws KeyError encode(msg, Dict{String,Float64}())
        end

        @testset "zero scaling throws ArgumentError" begin
            sig = Signal("Bad", 1, 1, 8, 0.0, 0.0)
            msg = CanMessage("Test", CanId(), [sig])
            @test_throws ArgumentError encode(msg, Dict("Bad" => 1.0))
        end
    end

    # =========================================================================
    # encode/decode round-trip
    # =========================================================================
    @testset "encode/decode round-trip" begin
        sigs = [
            Signal("RPM", 1, 1, 16, 0.125, 0.0),
            Signal("Torque", 3, 1, 8, 1.0, -125.0),
            Signal("Load", 4, 1, 8, 0.5, 0.0),
        ]
        msg = CanMessage("EEC1", CanId(6, 0xF0, 0x04, 0x00), sigs)

        original = Dict("RPM" => 1500.0, "Torque" => 50.0, "Load" => 75.0)
        frame = encode(msg, original)

        decoded = Dict{String,Float64}()
        decode!(frame, msg, decoded)

        @test decoded["RPM"] ≈ 1500.0
        @test decoded["Torque"] ≈ 50.0
        @test decoded["Load"] ≈ 75.0
    end

    @testset "encode then match_and_decode round-trip" begin
        msg = CanMessage("EEC1", CanId(6, 0xF0, 0x04, 0x00),
                         [Signal("RPM", 1, 1, 16, 0.125, 0.0)])
        messages = [msg]

        original = Dict("RPM" => 2000.0)
        frame = encode(msg, original)

        sigdict = Dict{String,Float64}()
        matched = match_and_decode!(frame, messages, sigdict)
        @test matched
        @test sigdict["RPM"] ≈ 2000.0
    end

    # =========================================================================
    # create_signal_dict
    # =========================================================================
    @testset "create_signal_dict" begin
        msg1 = CanMessage("M1", CanId(), [Signal("A", 1, 1, 8, 1.0, 0.0),
                                           Signal("B", 2, 1, 8, 1.0, 0.0)])
        msg2 = CanMessage("M2", CanId(), [Signal("C", 1, 1, 16, 1.0, 0.0)])

        sigdict = create_signal_dict([msg1, msg2])
        @test length(sigdict) == 3
        @test sigdict["A"] == 0.0
        @test sigdict["B"] == 0.0
        @test sigdict["C"] == 0.0
    end

    @testset "create_signal_dict with empty messages" begin
        sigdict = create_signal_dict(CanMessage[])
        @test isempty(sigdict)
    end

    # =========================================================================
    # create_signal_dict_storage
    # =========================================================================
    @testset "create_signal_dict_storage" begin
        msg = CanMessage("M1", CanId(), [Signal("X", 1, 1, 8, 1.0, 0.0)])

        @testset "basic" begin
            store = create_signal_dict_storage([msg])
            @test haskey(store, "X")
            @test store["X"] == Float64[]
        end

        @testset "empty" begin
            store = create_signal_dict_storage(CanMessage[])
            @test isempty(store)
        end
    end

    # =========================================================================
    # Re-exported types from CANUtils
    # =========================================================================
    @testset "re-exports" begin
        # CanFrame and Signal should be usable from J1939Parser
        frame = CanFrame(0x00, zeros(UInt8, 8))
        @test frame isa CanFrame

        sig = Signal("Test", 1, 1, 8, 1.0, 0.0)
        @test sig isa Signal
    end

    # =========================================================================
    # pgn
    # =========================================================================
    @testset "pgn" begin
        @testset "PDU2 format (PF >= 0xF0)" begin
            cid = CanId(6, 0xFE, 0xCA, 0x00)
            @test pgn(cid) == UInt32(0xFECA)
        end

        @testset "PDU1 format (PF < 0xF0)" begin
            cid = CanId(6, 0xEF, 0x21, 0x00)
            @test pgn(cid) == UInt32(0xEF00)  # PS excluded
        end

        @testset "with EDP and DP" begin
            cid = CanId(UInt8(6), UInt8(1), UInt8(1), UInt8(0xFE), UInt8(0xCA), UInt8(0x00))
            @test pgn(cid) == UInt32((1 << 17) | (1 << 16) | 0xFECA)
        end

        @testset "from raw id" begin
            @test pgn(UInt32(0x18FECA00)) == UInt32(0xFECA)
        end
    end

    # =========================================================================
    # extra_names support
    # =========================================================================
    @testset "create_signal_dict with extra_names" begin
        msg = CanMessage("M1", CanId(), [Signal("A", 1, 1, 8, 1.0, 0.0)])

        @testset "extra keys included" begin
            sd = create_signal_dict([msg], ["Extra1", "Extra2"])
            @test haskey(sd, "A")
            @test haskey(sd, "Extra1")
            @test haskey(sd, "Extra2")
            @test sd["Extra1"] == 0.0
        end

        @testset "empty messages with extra_names" begin
            sd = create_signal_dict(CanMessage[], ["OnlyExtra"])
            @test length(sd) == 1
            @test sd["OnlyExtra"] == 0.0
        end

        @testset "backward compatible without extra_names" begin
            sd = create_signal_dict([msg])
            @test length(sd) == 1
            @test haskey(sd, "A")
        end
    end

    @testset "create_signal_dict_storage with extra_names" begin
        msg = CanMessage("M1", CanId(), [Signal("A", 1, 1, 8, 1.0, 0.0)])

        @testset "extra keys included" begin
            store = create_signal_dict_storage([msg], ["Extra"])
            @test haskey(store, "A")
            @test haskey(store, "Extra")
            @test store["Extra"] == Float64[]
        end

        @testset "empty messages with extra_names" begin
            store = create_signal_dict_storage(CanMessage[], ["OnlyExtra"])
            @test length(store) == 1
            @test store["OnlyExtra"] == Float64[]
        end
    end

    # =========================================================================
    # Duplicate signal name detection
    # =========================================================================
    @testset "duplicate signal name detection" begin
        @testset "duplicate throws ArgumentError" begin
            @test_throws ArgumentError CanMessage("Bad", CanId(),
                [Signal("A", 1, 1, 8, 1.0, 0.0), Signal("A", 2, 1, 8, 1.0, 0.0)])
        end

        @testset "unique names accepted" begin
            msg = CanMessage("Good", CanId(),
                [Signal("A", 1, 1, 8, 1.0, 0.0), Signal("B", 2, 1, 8, 1.0, 0.0)])
            @test length(msg.signals) == 2
        end
    end

    # =========================================================================
    # Type stability
    # =========================================================================
    @testset "type stability" begin
        cid = CanId(6, 0xF0, 0x04, 0x00)
        sig = Signal("RPM", 1, 1, 16, 0.125, 0.0)
        msg = CanMessage("EEC1", cid, [sig])
        frame = CanFrame(encode_can_id(cid), UInt8[0x40, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        sigdict = Dict{String,Float64}("RPM" => 0.0)

        @test @inferred(encode_can_id(cid)) isa UInt32
        @test @inferred(pgn(cid)) isa UInt32
        @test @inferred(decode!(frame, msg, sigdict)) isa Dict{String,Float64}
        @test @inferred(match_and_decode!(frame, [msg], sigdict)) isa Bool
        @test @inferred(encode(msg, sigdict)) isa CanFrame
    end

    # =========================================================================
    # Zero allocations
    # =========================================================================
    @testset "zero allocations" begin
        cid  = CanId(3, 0xF0, 0x04, 0x00)
        sig  = Signal("RPM", 1, 1, 16, 0.125, 0.0)
        msg  = CanMessage("EEC1", cid, [sig])
        msgs = [msg]
        frame = CanFrame(encode_can_id(cid), UInt8[0x40, 0x1F, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
        sd    = create_signal_dict([msg])

        # Warm up JIT
        decode!(frame, msg, sd)
        match_and_decode!(frame, msgs, sd)
        encode(msg, sd)

        @test @allocated(decode!(frame, msg, sd)) == 0
        @test @allocated(match_and_decode!(frame, msgs, sd)) == 0
        @test @allocated(encode(msg, sd)) == 0
    end

    # =========================================================================
    # J1939 bit masks
    # =========================================================================
    @testset "J1939 masks" begin
        # Verify known raw ID decomposition: 0x18FECA00
        # priority=6 (0b110 << 26), edp=0, dp=0, pf=0xFE, ps=0xCA, sa=0x00
        rawid = UInt32(0x18FECA00)
        @test (rawid & J1939Parser.PRIORITY_MASK) >> 26 == 6
        @test (rawid & J1939Parser.EDP_MASK) >> 25 == 0
        @test (rawid & J1939Parser.DP_MASK) >> 24 == 0
        @test (rawid & J1939Parser.PF_MASK) >> 16 == 0xFE
        @test (rawid & J1939Parser.PS_MASK) >> 8 == 0xCA
        @test (rawid & J1939Parser.SA_MASK) == 0x00
    end

end
