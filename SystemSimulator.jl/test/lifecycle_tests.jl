@testset "TcpMonitor streaming and param updates" begin
    io = MockIO(["Speed"], ["Command"])
    logfile = tempname() * ".csv"
    mcfg = SS.MonitorConfig("127.0.0.1", 19200, 19201)
    cfg = SS.SystemConfig(20, [SS.IOConfig(:io, io, 32)], logfile, mcfg)
    runtime = try
        SS.SystemRuntime(cfg, SS.StopSignal(), EchoSystem(gain=1.0))
    catch err
        if err isa Base.IOError
            @test_skip "TCP listen blocked in sandbox"
            rm(logfile; force=true)
            return
        end
        rethrow(err)
    end
    SS.start!(runtime)
    sleep(0.2)

    out_sock = Sockets.connect("127.0.0.1", 19201)
    num_sigs = ltoh(read(out_sock, UInt32))
    sig_names = String[]
    for _ in 1:num_sigs
        nlen = ltoh(read(out_sock, UInt16))
        push!(sig_names, String(read(out_sock, nlen)))
    end
    @test "Time" in sig_names
    @test "io.Speed" in sig_names
    @test "io.Command" in sig_names
    @test "gain" in sig_names

    in_sock = Sockets.connect("127.0.0.1", 19200)
    num_params = ltoh(read(in_sock, UInt32))
    param_names = String[]
    for _ in 1:num_params
        nlen = ltoh(read(in_sock, UInt16))
        push!(param_names, String(read(in_sock, nlen)))
    end
    @test param_names == ["gain"]

    write(in_sock, reinterpret(UInt8, htol.([3.0])))
    flush(in_sock)
    @test wait_until(() -> isapprox(runtime.params["gain"], 3.0; atol=1e-6))

    frame_bytes = num_sigs * sizeof(Float64)
    while bytesavailable(out_sock) >= frame_bytes
        read(out_sock, frame_bytes)
    end

    inject_mock_frame!(io, Dict("Speed" => 7.0))
    matched = false
    deadline = time() + 3.0
    while time() < deadline
        raw = read(out_sock, frame_bytes)
        values = ltoh.(reinterpret(Float64, raw))
        stream = Dict(sig_names[i] => values[i] for i in eachindex(sig_names))
        if isapprox(stream["io.Command"], 21.0; atol=1e-6)
            matched = true
            break
        end
    end
    @test matched

    close(in_sock)
    close(out_sock)
    SS.stop!(runtime)
    rm(logfile; force=true)
end
