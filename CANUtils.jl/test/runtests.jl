using Test
using CANUtils

@testset "CANUtils" begin

    # =========================================================================
    # Signal
    # =========================================================================
    @testset "Signal" begin
        @testset "constructor with all fields" begin
            sig = Signal("EngineSpeed", 4, 1, 16, 0.125, 0.0)
            @test sig.name == "EngineSpeed"
            @test sig.start_byte == UInt8(4)
            @test sig.start_bit == UInt8(1)
            @test sig.length == UInt8(16)
            @test sig.scaling == 0.125
            @test sig.offset == 0.0
        end

        @testset "default constructor" begin
            sig = Signal()
            @test sig.name == ""
            @test sig.start_byte == UInt8(0)
            @test sig.start_bit == UInt8(0)
            @test sig.length == UInt8(0)
            @test sig.scaling == 1.0
            @test sig.offset == 0.0
        end

        @testset "type conversion in constructor" begin
            sig = Signal("Test", Int32(2), Int32(3), Int32(8), Float32(0.5), Float32(-10.0))
            @test sig.start_byte === UInt8(2)
            @test sig.start_bit === UInt8(3)
            @test sig.length === UInt8(8)
            @test sig.scaling === Float64(0.5)
            @test sig.offset === Float64(-10.0)
        end

        @testset "show" begin
            sig = Signal("RPM", 1, 1, 8, 1.0, 0.0)
            buf = IOBuffer()
            show(buf, sig)
            s = String(take!(buf))
            @test contains(s, "RPM")
            @test contains(s, "StartByte")
        end

        @testset "validation" begin
            @test_throws ArgumentError Signal("", 1, 1, 8, 1.0, 0.0)         # empty name
            @test_throws ArgumentError Signal("X", 0, 1, 8, 1.0, 0.0)        # start_byte < 1
            @test_throws ArgumentError Signal("X", 9, 1, 8, 1.0, 0.0)        # start_byte > 8
            @test_throws ArgumentError Signal("X", 1, 0, 8, 1.0, 0.0)        # start_bit < 1
            @test_throws ArgumentError Signal("X", 1, 9, 8, 1.0, 0.0)        # start_bit > 8
            @test_throws ArgumentError Signal("X", 1, 1, 0, 1.0, 0.0)        # length < 1
            @test_throws ArgumentError Signal("X", 1, 1, 65, 1.0, 0.0)       # length > 64
            @test_throws ArgumentError Signal("X", 8, 2, 8, 1.0, 0.0)        # exceeds 64-bit boundary
            # Valid edge cases
            @test Signal("Y", 1, 1, 64, 1.0, 0.0) isa Signal                 # full 64 bits from bit 0
            @test Signal("Z", 8, 1, 8, 1.0, 0.0) isa Signal                  # last byte exactly
            @test Signal() isa Signal                                          # default sentinel
        end
    end

    # =========================================================================
    # CanFrame
    # =========================================================================
    @testset "CanFrame" begin
        @testset "basic construction" begin
            data = UInt8[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
            frame = CanFrame(0x18FF00FE, data)
            @test frame.canid == UInt32(0x18FF00FE)
            @test length(frame.data) == 8
            @test frame.data[1] == 0x01
            @test frame.data[8] == 0x08
        end

        @testset "rejects wrong data length" begin
            @test_throws ArgumentError CanFrame(0x00, UInt8[1, 2, 3])
            @test_throws ArgumentError CanFrame(0x00, UInt8[])
            @test_throws ArgumentError CanFrame(0x00, zeros(UInt8, 9))
        end

        @testset "canid is UInt32" begin
            frame = CanFrame(0xFF, zeros(UInt8, 8))
            @test frame.canid === UInt32(0xFF)
        end

        @testset "show" begin
            frame = CanFrame(0x18FECA00, UInt8[0xAA, 0xBB, 0xCC, 0xDD, 0x00, 0x00, 0x00, 0x00])
            buf = IOBuffer()
            show(buf, frame)
            s = String(take!(buf))
            @test contains(s, "Can ID")
            @test contains(s, "AA")
        end
    end

    # =========================================================================
    # AbstractCanMessage interface
    # =========================================================================
    @testset "AbstractCanMessage fallbacks" begin
        struct TestMsg <: AbstractCanMessage end

        frame = CanFrame(0x00, zeros(UInt8, 8))
        sigdict = Dict{String,Float64}()
        msg = TestMsg()

        @test_throws ErrorException decode!(frame, msg, sigdict)
        @test_throws ErrorException match_and_decode!(frame, [msg], sigdict)
        @test_throws ErrorException encode(msg, sigdict)
        @test_throws ErrorException create_signal_dict([msg])
    end

    # =========================================================================
    # Decoding utilities
    # =========================================================================
    @testset "extract_bits" begin
        @testset "extract single bit" begin
            @test extract_bits(UInt64(0b1010), 0, 1) == UInt64(0)
            @test extract_bits(UInt64(0b1010), 1, 1) == UInt64(1)
            @test extract_bits(UInt64(0b1010), 3, 1) == UInt64(1)
        end

        @testset "extract multi-bit field" begin
            @test extract_bits(UInt64(0xFF), 0, 8) == UInt64(0xFF)
            @test extract_bits(UInt64(0xFF00), 8, 8) == UInt64(0xFF)
            @test extract_bits(UInt64(0xABCD), 0, 16) == UInt64(0xABCD)
        end

        @testset "extract from middle of word" begin
            # 0b11001100: bits [2:5] (0-indexed) = 0b0011
            data = UInt64(0b11001100)
            @test extract_bits(data, 2, 4) == UInt64(0b0011)
        end

        @testset "zero length returns zero" begin
            @test extract_bits(UInt64(0xFFFFFFFF), 0, 0) == UInt64(0)
        end

        @testset "full 64-bit extraction" begin
            val = typemax(UInt64)
            @test extract_bits(val, 0, 64) == val
        end

        @testset "bounds checking" begin
            @test_throws ArgumentError extract_bits(UInt64(0), 60, 8)   # 60+8=68 > 64
            @test_throws ArgumentError extract_bits(UInt64(0), -1, 8)   # negative startbit
            @test extract_bits(UInt64(0), 56, 8) == UInt64(0)           # 56+8=64, valid
        end
    end

    @testset "extract_signal" begin
        # Signal at byte 1, bit 1, length 8 → startbit_g = 0, extracts first byte
        sig = Signal("TestSig", 1, 1, 8, 1.0, 0.0)
        data = UInt64(0xDEADBEEF_CAFEBABE)
        @test extract_signal(data, sig) == UInt64(0xBE)  # first byte (little-endian)

        # Signal at byte 2, bit 1, length 8 → startbit_g = 8
        sig2 = Signal("TestSig2", 2, 1, 8, 1.0, 0.0)
        @test extract_signal(data, sig2) == UInt64(0xBA)  # second byte

        # Signal at byte 1, bit 1, length 16 → startbit_g = 0, extracts first 2 bytes
        sig3 = Signal("TestSig3", 1, 1, 16, 1.0, 0.0)
        @test extract_signal(data, sig3) == UInt64(0xBABE)
    end

    @testset "data_to_int" begin
        @testset "basic conversion" begin
            data = UInt8[0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]
            @test data_to_int(data) == UInt64(0x01)
        end

        @testset "little-endian ordering" begin
            data = UInt8[0xBE, 0xBA, 0xFE, 0xCA, 0xEF, 0xBE, 0xAD, 0xDE]
            @test data_to_int(data) == UInt64(0xDEADBEEFCAFEBABE)
        end

        @testset "all ones" begin
            data = fill(UInt8(0xFF), 8)
            @test data_to_int(data) == typemax(UInt64)
        end

        @testset "rejects wrong length" begin
            @test_throws ArgumentError data_to_int(UInt8[1, 2, 3])
        end

        @testset "NTuple overload" begin
            data = (UInt8(0x01), UInt8(0x02), UInt8(0x03), UInt8(0x04),
                    UInt8(0x05), UInt8(0x06), UInt8(0x07), UInt8(0x08))
            @test data_to_int(data) == UInt64(0x0807060504030201)
        end
    end

    # =========================================================================
    # Encoding utilities
    # =========================================================================
    @testset "add_bits" begin
        @testset "set bits in empty word" begin
            @test add_bits(UInt64(0), UInt64(0xFF), 0, 8) == UInt64(0xFF)
            @test add_bits(UInt64(0), UInt64(0xFF), 8, 8) == UInt64(0xFF00)
        end

        @testset "overwrite existing bits" begin
            data = UInt64(0xFF)
            @test add_bits(data, UInt64(0x00), 0, 8) == UInt64(0x00)
        end

        @testset "preserve other bits" begin
            data = UInt64(0xFF00)
            result = add_bits(data, UInt64(0xAB), 0, 8)
            @test result == UInt64(0xFFAB)
        end

        @testset "single bit" begin
            @test add_bits(UInt64(0), UInt64(1), 5, 1) == UInt64(1 << 5)
        end

        @testset "bounds checking" begin
            @test_throws ArgumentError add_bits(UInt64(0), UInt64(1), 60, 8)    # 60+8=68 > 64
            @test_throws ArgumentError add_bits(UInt64(0), UInt64(1), -1, 8)    # negative startbit
            @test_throws ArgumentError add_bits(UInt64(0), UInt64(0x1FF), 0, 8) # 0x1FF > 255 for 8 bits
            @test add_bits(UInt64(0), UInt64(0xFF), 56, 8) == UInt64(0xFF) << 56  # boundary valid
        end
    end

    @testset "add_signal" begin
        sig = Signal("TestSig", 1, 1, 8, 1.0, 0.0)
        @test add_signal(UInt64(0), UInt64(0xAB), sig) == UInt64(0xAB)

        sig2 = Signal("TestSig2", 3, 1, 16, 1.0, 0.0)
        result = add_signal(UInt64(0), UInt64(0x1234), sig2)
        @test extract_signal(result, sig2) == UInt64(0x1234)
    end

    @testset "uint_to_payload" begin
        @testset "zero" begin
            payload = uint_to_payload(UInt64(0))
            @test length(payload) == 8
            @test all(b -> b == 0x00, payload)
        end

        @testset "little-endian byte order" begin
            payload = uint_to_payload(UInt64(0x0807060504030201))
            @test payload[1] == 0x01
            @test payload[2] == 0x02
            @test payload[8] == 0x08
        end

        @testset "max value" begin
            payload = uint_to_payload(typemax(UInt64))
            @test all(b -> b == 0xFF, payload)
        end
    end

    # =========================================================================
    # Round-trip: encode then decode
    # =========================================================================
    @testset "encode/decode round-trip" begin
        sig = Signal("Speed", 3, 1, 16, 1.0, 0.0)
        raw_value = UInt64(1234)

        # Encode: put raw_value into a 64-bit word
        data_word = add_signal(UInt64(0), raw_value, sig)

        # Decode: extract it back
        extracted = extract_signal(data_word, sig)
        @test extracted == raw_value

        # Also round-trip through payload
        payload = uint_to_payload(data_word)
        data_back = data_to_int(collect(payload))
        extracted2 = extract_signal(data_back, sig)
        @test extracted2 == raw_value
    end

    @testset "multi-signal round-trip" begin
        sig_a = Signal("A", 1, 1, 8, 1.0, 0.0)   # byte 1, 8 bits
        sig_b = Signal("B", 2, 1, 8, 1.0, 0.0)   # byte 2, 8 bits
        sig_c = Signal("C", 3, 1, 16, 1.0, 0.0)  # bytes 3-4, 16 bits

        data_word = UInt64(0)
        data_word = add_signal(data_word, UInt64(0xAA), sig_a)
        data_word = add_signal(data_word, UInt64(0xBB), sig_b)
        data_word = add_signal(data_word, UInt64(0x1234), sig_c)

        @test extract_signal(data_word, sig_a) == UInt64(0xAA)
        @test extract_signal(data_word, sig_b) == UInt64(0xBB)
        @test extract_signal(data_word, sig_c) == UInt64(0x1234)

        # Through payload
        payload = uint_to_payload(data_word)
        data_back = data_to_int(collect(payload))
        @test extract_signal(data_back, sig_a) == UInt64(0xAA)
        @test extract_signal(data_back, sig_b) == UInt64(0xBB)
        @test extract_signal(data_back, sig_c) == UInt64(0x1234)
    end

    # =========================================================================
    # store_sigdict!
    # =========================================================================
    @testset "store_sigdict!" begin
        sigdict = Dict("RPM" => 1500.0, "Speed" => 60.0)
        storage = Dict{String,Vector{Float64}}()

        store_sigdict!(sigdict, storage)
        @test storage["RPM"] == [1500.0]
        @test storage["Speed"] == [60.0]

        sigdict["RPM"] = 2000.0
        sigdict["Speed"] = 80.0
        store_sigdict!(sigdict, storage)
        @test storage["RPM"] == [1500.0, 2000.0]
        @test storage["Speed"] == [60.0, 80.0]
    end

    # =========================================================================
    # CanFrame data type
    # =========================================================================
    @testset "CanFrame data is NTuple" begin
        frame = CanFrame(0x00, UInt8[0, 0, 0, 0, 0, 0, 0, 0])
        @test frame.data isa NTuple{8,UInt8}
    end

    # =========================================================================
    # Edge cases
    # =========================================================================
    @testset "edge cases" begin
        @testset "signal at bit boundary" begin
            # Signal starting at bit 5 of byte 1, 4 bits long
            sig = Signal("Nibble", 1, 5, 4, 1.0, 0.0)
            # Byte 1 = 0b1010_0000 → bits 4-7 = 0b1010
            data_word = UInt64(0b10100000)
            @test extract_signal(data_word, sig) == UInt64(0b1010)
        end

        @testset "extract_bits at high positions" begin
            data = UInt64(1) << 63
            @test extract_bits(data, 63, 1) == UInt64(1)
        end

        @testset "add_bits then extract_bits consistency" begin
            for startbit in [0, 7, 15, 31, 48, 56]
                for len in [1, 4, 8]
                    if startbit + len <= 64
                        val = UInt64((1 << len) - 1)  # max value for len bits
                        result = add_bits(UInt64(0), val, startbit, len)
                        @test extract_bits(result, startbit, len) == val
                    end
                end
            end
        end
    end

    # =========================================================================
    # Sentinel Signal safety
    # =========================================================================
    @testset "sentinel Signal safety" begin
        sentinel = Signal()
        data_g = UInt64(0xDEADBEEFCAFEBABE)

        @testset "extract_signal returns zero for sentinel" begin
            @test extract_signal(data_g, sentinel) == UInt64(0)
        end

        @testset "add_signal returns data unchanged for sentinel" begin
            @test add_signal(data_g, UInt64(0), sentinel) == data_g
        end
    end

    # =========================================================================
    # Type stability
    # =========================================================================
    @testset "type stability" begin
        data_g = UInt64(0x0807060504030201)
        sig = Signal("TypeTest", 1, 1, 16, 0.125, 0.0)
        data_vec = UInt8[0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]
        data_tup = (0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08)

        @test @inferred(extract_bits(data_g, 0, 16)) isa UInt64
        @test @inferred(extract_signal(data_g, sig)) isa UInt64
        @test @inferred(data_to_int(data_vec)) isa UInt64
        @test @inferred(data_to_int(data_tup)) isa UInt64
        @test @inferred(add_bits(UInt64(0), UInt64(0xFF), 0, 8)) isa UInt64
        @test @inferred(add_signal(UInt64(0), UInt64(0xFF), sig)) isa UInt64
        @test @inferred(uint_to_payload(data_g)) isa NTuple{8,UInt8}
    end

end
