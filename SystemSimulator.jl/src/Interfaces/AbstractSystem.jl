abstract type AbstractSystem end

parameter_names(::AbstractSystem)::Vector{String} = String[]
monitor_parameter_names(system::AbstractSystem)::Vector{String} = parameter_names(system)

function initialize_parameters!(::AbstractSystem, _params)::Nothing
    return nothing
end

function bind!(::AbstractSystem, _runtime)::Nothing
    return nothing
end

function parameters_updated!(::AbstractSystem, _params)::Nothing
    return nothing
end

function control_step!(system::AbstractSystem, inputs, outputs, params, dt)
    error("control_step! not implemented for system type: $(typeof(system))")
end
