mutable struct MockIO <: SS.AbstractIO
    rx::Channel{Any}
    tx::Channel{Any}
    in_names::Vector{String}
    out_names::Vector{String}
    closed::Bool
    throw_decode::Bool
    throw_write::Bool
end

function MockIO(in_names::Vector{String}, out_names::Vector{String}; bufsize::Int=128)
    return MockIO(
        Channel{Any}(bufsize),
        Channel{Any}(bufsize),
        in_names,
        out_names,
        false,
        false,
        false,
    )
end

function SS.read_raw(io::MockIO)
    io.closed && return nothing
    try
        if isready(io.rx)
            return take!(io.rx)
        end
    catch
        return nothing
    end
    sleep(0.005)
    return nothing
end

function SS.decode_raw!(io::MockIO, raw, local_inputs::AbstractDict{String,Float64})::Bool
    io.throw_decode && throw(ErrorException("mock decode failure"))
    raw isa AbstractDict || return false
    for name in io.in_names
        haskey(raw, name) && (local_inputs[name] = Float64(raw[name]))
    end
    return true
end

function SS.encode_raw(io::MockIO, local_outputs::AbstractDict{String,<:Real})::Vector{Any}
    isempty(io.out_names) && return Any[]
    payload = Dict{String,Float64}(name => Float64(get(local_outputs, name, 0.0)) for name in io.out_names)
    return Any[payload]
end

function SS.write_raw(io::MockIO, payload)::Nothing
    io.throw_write && throw(ErrorException("mock write failure"))
    io.closed && return nothing
    put!(io.tx, payload)
    return nothing
end

SS.input_signal_names(io::MockIO) = copy(io.in_names)
SS.output_signal_names(io::MockIO) = copy(io.out_names)

function Base.close(io::MockIO)::Nothing
    io.closed = true
    isopen(io.rx) && close(io.rx)
    isopen(io.tx) && close(io.tx)
    return nothing
end

inject_mock_frame!(io::MockIO, frame::Dict{String,Float64}) = put!(io.rx, frame)

mutable struct MockCanDriver <: CI.AbstractCanDriver
    channelname::String
    rx::Channel{CI.CanFrameRaw}
    tx::Channel{CI.CanFrameRaw}
    closed::Bool
end

function MockCanDriver(name::String; bufsize=256)
    MockCanDriver(name, Channel{CI.CanFrameRaw}(bufsize), Channel{CI.CanFrameRaw}(bufsize), false)
end

function CI.read(d::MockCanDriver)
    d.closed && return nothing
    try
        if isready(d.rx)
            return take!(d.rx)
        end
    catch
        return nothing
    end
    sleep(0.005)
    return nothing
end

function CI.write(d::MockCanDriver, canid::UInt32, data::NTuple{8,UInt8})
    d.closed && return nothing
    put!(d.tx, CI.CanFrameRaw(canid, UInt8(8), 0x00, 0x00, 0x00, data))
    return nothing
end

function CI.write(d::MockCanDriver, canid::UInt32, data::AbstractVector{UInt8})
    CI.write(d, canid, ntuple(i -> data[i], 8))
end

function CI.close(d::MockCanDriver)
    d.closed = true
    isopen(d.rx) && close(d.rx)
    isopen(d.tx) && close(d.tx)
    return nothing
end

function inject_can_frame!(driver::MockCanDriver, canid::UInt32, data::Vector{UInt8})
    frame = CI.CanFrameRaw(canid, UInt8(8), 0x00, 0x00, 0x00, ntuple(i -> data[i], 8))
    put!(driver.rx, frame)
end

const TEST_RX_CATALOG = CP.CanMessage[
    CP.CanMessage(
        "EEC1",
        CP.CanId(3, 0xF0, 0x04, 0x00),
        CU.Signal[
            CU.Signal("EngineSpeed", 4, 1, 16, 0.125, 0.0),
            CU.Signal("ActualEngTorque", 3, 1, 8, 1.0, -125.0),
        ],
    ),
]

const TEST_TX_CATALOG = CP.CanMessage[
    CP.CanMessage(
        "TSC1",
        CP.CanId(3, 0x00, 0x00, 0x03),
        CU.Signal[
            CU.Signal("ReqSpeed_SpeedLimit", 2, 1, 16, 0.125, 0.0),
            CU.Signal("ReqTorque_TorqueLimit", 4, 1, 8, 1.0, -125.0),
        ],
    ),
]

mutable struct EchoSystem <: SS.AbstractSystem
    gain_default::Float64
    in_slot::Int
    out_slot::Int
    gain_slot::Int
end

EchoSystem(; gain=1.0) = EchoSystem(gain, 0, 0, 0)
SS.parameter_names(::EchoSystem) = ["gain"]

function SS.initialize_parameters!(sys::EchoSystem, params)
    params["gain"] = sys.gain_default
    return nothing
end

function SS.bind!(sys::EchoSystem, runtime)
    sys.in_slot = SS.signal_slot(runtime.inputs, "io.Speed")
    sys.out_slot = SS.signal_slot(runtime.outputs, "io.Command")
    sys.gain_slot = SS.signal_slot(runtime.params, "gain")
    return nothing
end

function SS.control_step!(sys::EchoSystem, inputs, outputs, params, _dt)
    outputs[sys.out_slot] = inputs[sys.in_slot] * params[sys.gain_slot]
    return nothing
end

mutable struct MultiIOSystem <: SS.AbstractSystem
    in_slots::Vector{Int}
    out_slot::Int
end

MultiIOSystem() = MultiIOSystem(Int[], 0)

function SS.bind!(sys::MultiIOSystem, runtime)
    sys.in_slots = [
        SS.signal_slot(runtime.inputs, "ioA.Speed"),
        SS.signal_slot(runtime.inputs, "ioB.Speed"),
    ]
    sys.out_slot = SS.signal_slot(runtime.outputs, "ioOut.Command")
    return nothing
end

function SS.control_step!(sys::MultiIOSystem, inputs, outputs, _params, _dt)
    outputs[sys.out_slot] = inputs[sys.in_slots[1]] + inputs[sys.in_slots[2]]
    return nothing
end

mutable struct CanBridgeSystem <: SS.AbstractSystem
    in_slot::Int
    out_slot::Int
end

CanBridgeSystem() = CanBridgeSystem(0, 0)

function SS.bind!(sys::CanBridgeSystem, runtime)
    sys.in_slot = SS.signal_slot(runtime.inputs, "rx.EngineSpeed")
    sys.out_slot = SS.signal_slot(runtime.outputs, "tx.ReqSpeed_SpeedLimit")
    return nothing
end

function SS.control_step!(sys::CanBridgeSystem, inputs, outputs, _params, _dt)
    outputs[sys.out_slot] = inputs[sys.in_slot]
    return nothing
end

function wait_until(predicate; timeout=2.0, step=0.01)
    t0 = time()
    while time() - t0 < timeout
        predicate() && return true
        sleep(step)
    end
    return predicate()
end
