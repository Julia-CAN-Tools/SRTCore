module SRTBonito

using Bonito
using Observables
using Sockets
using OrderedCollections: OrderedDict
using PrecompileTools

include("../../../IO/TCP/SRTMonitorProtocol.jl")
include("tcp_client.jl")
include("config.jl")
include("components.jl")
include("plotly.jl")
include("app_builder.jl")

export TcpClient, connect_stream!, connect_params!, send_params!,
       get_history, get_history_since, get_latest, close!
export AppConfig, ParamDef, PlotDef, TraceDef
export build_app, serve_app,
       build_sidebar, dashboard_layout, fetch_histories!,
       append_histories!, update_status_obs!

@setup_workload begin
    config = AppConfig(
        title = "PrecompileDummy",
        port = 8999,
        stream_port = 9991,
        param_port = 9990,
        params = [
            ParamDef(key="p1", label="Param 1", min=0.0, max=10.0, step=0.1, default=1.0, group="Group"),
        ],
        plots = [
            PlotDef(graph_id="graph-1", title="Plot 1", traces=[
                TraceDef(signal="sig1", label="Sig 1"),
            ], yaxis="Y Axis"),
        ]
    )
    @compile_workload begin
        try
            build_app(config)
        catch
        end
    end
end

end
