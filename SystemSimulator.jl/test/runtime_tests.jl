@testset "Slot-based control loop with mock IO" begin
    io = MockIO(["Speed"], ["Command"])
    logfile = tempname() * ".csv"
    cfg = SS.SystemConfig(20, [SS.IOConfig(:io, io, 32)], logfile)
    runtime = SS.SystemRuntime(cfg, SS.StopSignal(), EchoSystem(gain=2.0))
    SS.start!(runtime)

    inject_mock_frame!(io, Dict("Speed" => 12.5))
    @test wait_until(() -> isapprox(runtime.outputs["io.Command"], 25.0; atol=1e-6))
    @test isready(io.tx)
    payload = take!(io.tx)
    while isready(io.tx)
        payload = take!(io.tx)
    end
    @test payload["Command"] ≈ 25.0 atol=1e-6

    SS.stop!(runtime)
    @test wait_until(() -> isfile(logfile))
    rm(logfile; force=true)
end

@testset "Multiple IO endpoints" begin
    io_a = MockIO(["Speed"], String[])
    io_b = MockIO(["Speed"], String[])
    io_out = MockIO(String[], ["Command"])
    logfile = tempname() * ".csv"
    cfg = SS.SystemConfig(
        20,
        [
            SS.IOConfig(:ioA, io_a, 32, SS.IO_MODE_READONLY),
            SS.IOConfig(:ioB, io_b, 32, SS.IO_MODE_READONLY),
            SS.IOConfig(:ioOut, io_out, 32, SS.IO_MODE_WRITEONLY),
        ],
        logfile,
    )
    runtime = SS.SystemRuntime(cfg, SS.StopSignal(), MultiIOSystem())
    SS.start!(runtime)

    inject_mock_frame!(io_a, Dict("Speed" => 10.0))
    inject_mock_frame!(io_b, Dict("Speed" => 15.0))
    @test wait_until(() -> isapprox(runtime.outputs["ioOut.Command"], 25.0; atol=1e-6))
    tx_payload = take!(io_out.tx)
    while isready(io_out.tx)
        tx_payload = take!(io_out.tx)
    end
    @test tx_payload["Command"] ≈ 25.0 atol=1e-6

    SS.stop!(runtime)
    rm(logfile; force=true)
end

@testset "CAN adapter end-to-end" begin
    rx_driver = MockCanDriver("mock_rx")
    tx_driver = MockCanDriver("mock_tx")
    rx_io = SS.CanIO(rx_driver, TEST_RX_CATALOG, CP.CanMessage[])
    tx_io = SS.CanIO(tx_driver, CP.CanMessage[], TEST_TX_CATALOG)
    logfile = tempname() * ".csv"
    cfg = SS.SystemConfig(
        20,
        [SS.IOConfig(:rx, rx_io, 64), SS.IOConfig(:tx, tx_io, 64)],
        logfile,
    )
    runtime = SS.SystemRuntime(cfg, SS.StopSignal(), CanBridgeSystem())
    SS.start!(runtime)

    canid = CP.encode_can_id(CP.CanId(3, 0xF0, 0x04, 0x00))
    data = UInt8[0x00, 0x00, 0x00, 0xE0, 0x2E, 0x00, 0x00, 0x00]
    inject_can_frame!(rx_driver, canid, data)

    @test wait_until(() -> isapprox(runtime.inputs["rx.EngineSpeed"], 1500.0; atol=0.5); timeout=3.0)
    @test wait_until(() -> isready(tx_driver.tx))
    tx_frame = take!(tx_driver.tx)
    @test tx_frame.can_dlc == 8

    SS.stop!(runtime)
    rm(logfile; force=true)
end
