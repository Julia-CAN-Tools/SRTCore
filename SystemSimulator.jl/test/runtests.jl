using Test
using Sockets
import SystemSimulator as SS
import CANInterface as CI
import CANUtils as CU
import J1939Parser as CP

include("support/MockIO.jl")

@testset "SystemSimulator" begin
    include("signal_buffer_tests.jl")
    include("configuration_tests.jl")
    include("runtime_tests.jl")
    include("lifecycle_tests.jl")
end
