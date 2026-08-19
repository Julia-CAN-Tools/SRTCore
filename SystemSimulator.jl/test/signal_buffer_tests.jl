@testset "StopSignal and signal storage" begin
    sf = SS.StopSignal()
    @test !SS.stop_requested(sf)
    SS.request_stop!(sf)
    @test SS.stop_requested(sf)
    SS.cancel_stop!(sf)
    @test !SS.stop_requested(sf)

    buf = SS.SignalBuffer(["a", "b", "a"])
    @test SS.signal_names(buf) == ["a", "b"]
    @test SS.signal_slot(buf, "a") == 1
    buf[1] = 10.0
    buf["b"] = 5.0
    @test buf["a"] == 10.0
    @test buf[2] == 5.0
end
