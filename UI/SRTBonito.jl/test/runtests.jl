using Test
using SRTBonito
import Sockets
using Observables

@testset "SRTBonito" begin
    @testset "Config types" begin
        t = TraceDef(signal="sig.A", label="A")
        @test t.signal == "sig.A"
        @test t.mode == :lines

        p = ParamDef(key="gain", label="Gain", min=0.0, max=10.0, step=0.1, default=1.0)
        @test p.default == 1.0
        @test p.kind == :slider

        pd = PlotDef(graph_id="g1", title="Plot 1", traces=[t])
        @test pd.x_signal == "Time"
        @test pd.user_selectable == true
    end

    @testset "TcpClient construction" begin
        c = TcpClient(; stream_port=9999, param_port=9998)
        @test c.host == "localhost"
        @test isempty(c.signal_names)
        @test c.maxlen == 3000
        @test !c.running
    end

    @testset "Shared dashboard primitives" begin
        client = TcpClient(; stream_port=1, param_port=2)
        client.history["a"] = SRTBonito.HistoryBuffer(3)
        client.history["b"] = SRTBonito.HistoryBuffer(3)
        push!(client.history["a"], 1.0, 2.0)
        push!(client.history["b"], 3.0)

        a = Observable(Float64[])
        b = Observable(Float64[])
        @test fetch_histories!([a, b], client, ["a", "b"])
        @test a[] == [1.0]
        @test b[] == [3.0]
        @test_throws DimensionMismatch fetch_histories!([a], client, ["a", "b"])
        status = Observable("")
        status_class = Observable("")
        for (name, value) in
            (("running", 1.0), ("elapsed", 2.5), ("duration", 30.0))
            client.history[name] = SRTBonito.HistoryBuffer(3)
            push!(client.history[name], value)
        end
        update_status_obs!(client, status, status_class)
        @test startswith(status[], "Running: 2.5")
        @test status_class[] == "srt-status srt-status-running"
    end

    @testset "Ring history and incremental updates" begin
        client = TcpClient(; stream_port=1, param_port=2, maxlen=3)
        history = SRTBonito.HistoryBuffer(3)
        client.history["signal"] = history
        push!(history, 1.0, 2.0, 3.0, 4.0)

        @test get_history(client, "signal") == [2.0, 3.0, 4.0]
        samples, cursor = get_history_since(client, "signal", UInt64(0))
        @test samples == [2.0, 3.0, 4.0]
        @test cursor == 4

        observable = Observable(Float64[])
        cursor_ref = Ref(UInt64(0))
        @test append_histories!([observable], client, ["signal"], cursor_ref; maxlen=2)
        @test observable[] == [3.0, 4.0]
        push!(history, 5.0)
        @test append_histories!([observable], client, ["signal"], cursor_ref; maxlen=2)
        @test observable[] == [4.0, 5.0]
        @test !append_histories!([observable], client, ["signal"], cursor_ref; maxlen=2)
    end

    @testset "TCP handshake round-trip" begin
        # Spin up a mock server that sends a valid handshake
        srv = Sockets.listen(Sockets.IPv4("127.0.0.1"), 0)
        port = Int(Sockets.getsockname(srv)[2])

        server_task = @async begin
            sock = Sockets.accept(srv)
            # Handshake: 3 signals
            write(sock, htol(UInt32(3)))
            for name in ["Time", "sig.A", "sig.B"]
                encoded = Vector{UInt8}(name)
                write(sock, htol(UInt16(length(encoded))))
                write(sock, encoded)
            end
            flush(sock)
            # Send one data frame
            frame = htol.([1.0, 2.0, 3.0])
            write(sock, reinterpret(UInt8, frame))
            flush(sock)
            sleep(0.5)  # let client read
            close(sock)
        end

        c = TcpClient(; stream_port=port)
        connect_stream!(c)
        @test c.signal_names == ["Time", "sig.A", "sig.B"]

        sleep(0.3)  # let reader loop process the frame

        @test get_latest(c, "Time") == 1.0
        @test get_latest(c, "sig.A") == 2.0
        @test get_latest(c, "sig.B") == 3.0

        h = get_history(c, "sig.A")
        @test length(h) == 1
        @test h[1] == 2.0

        close!(c)
        close(srv)
        wait(server_task)
    end

    @testset "send_params! round-trip" begin
        srv = Sockets.listen(Sockets.IPv4("127.0.0.1"), 0)
        port = Int(Sockets.getsockname(srv)[2])

        received = Ref(Float64[])
        server_task = @async begin
            sock = Sockets.accept(srv)
            # Handshake: 2 params
            write(sock, htol(UInt32(2)))
            for name in ["gain", "offset"]
                encoded = Vector{UInt8}(name)
                write(sock, htol(UInt16(length(encoded))))
                write(sock, encoded)
            end
            flush(sock)
            # Read one param frame
            data = read(sock, 2 * sizeof(Float64))
            received[] = ltoh.(reinterpret(Float64, data))
            close(sock)
        end

        c = TcpClient(; param_port=port)
        connect_params!(c)
        @test c.param_names == ["gain", "offset"]

        ok = send_params!(c, Dict("gain" => 3.14, "offset" => -1.5))
        @test ok

        wait(server_task)
        @test received[][1] ≈ 3.14
        @test received[][2] ≈ -1.5

        close!(c)
        close(srv)
    end
end
