"""One trace (line) on a plot."""
Base.@kwdef struct TraceDef
    signal::String                                    # e.g. "can_state.Theta1"
    label::String                                     # e.g. "theta1"
    color::Union{Symbol, Nothing} = nothing           # CSS color name, auto if nothing
    linestyle::Union{Symbol, Nothing} = nothing       # :solid, :dash, etc.
    mode::Symbol = :lines                             # :lines, :scatter, :linesscatter
end

"""One graph panel in the 2×2 grid."""
Base.@kwdef struct PlotDef
    graph_id::String
    title::String
    traces::Vector{TraceDef}
    xaxis::String = "Time [s]"
    yaxis::String = ""
    x_signal::String = "Time"                         # signal for x-axis
    user_selectable::Bool = true                      # show signal picker dropdown
end

"""One tunable parameter in the sidebar."""
Base.@kwdef struct ParamDef
    key::String                                       # param name sent to Julia runtime
    label::String                                     # display label
    min::Float64 = 0.0
    max::Float64 = 1.0
    step::Float64 = 0.1
    default::Float64 = 0.0
    kind::Symbol = :slider                            # :slider or :dropdown
    options::Union{Vector{Tuple{String,Float64}}, Nothing} = nothing  # for :dropdown
    group::String = ""                                # section header
end

"""Complete configuration for a simulator Bonito app."""
Base.@kwdef struct AppConfig
    title::String
    port::Int
    stream_port::Int
    param_port::Int
    params::Vector{ParamDef}
    plots::Vector{PlotDef}                            # exactly 4 for 2×2 grid
    include_reset::Bool = false
    interval_ms::Int = 200
    plot_max_points::Int = 1000
    sidebar_width::String = "280px"
    extra_params::Dict{String,Float64} = Dict{String,Float64}()
    param_builder::Union{Function, Nothing} = nothing # optional callable(widget_values) → param_dict
end
