@testset "IO modes and runtime construction" begin
    io = MockIO(["Speed"], ["Command"])
    cfg = SS.IOConfig(:io, io, 16)
    @test SS.is_read_enabled(cfg)
    @test SS.is_write_enabled(cfg)

    logfile = tempname() * ".csv"
    runtime = SS.SystemRuntime(SS.SystemConfig(20, [cfg], logfile), SS.StopSignal(), EchoSystem())
    @test SS.signal_names(runtime.inputs) == ["io.Speed"]
    @test SS.signal_names(runtime.outputs) == ["io.Command"]
    @test SS.signal_names(runtime.params) == ["gain"]
    @test runtime.params["gain"] == 1.0
    close(runtime.logger.filehandle)
    rm(logfile; force=true)
end
