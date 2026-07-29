const PLOTLY_VERSION = "3.7.0"
const PLOTLY_JS = Bonito.Asset(
    joinpath(@__DIR__, "..", "assets", "plotly-$PLOTLY_VERSION.min.js");
    name="Plotly",
)

mutable struct PlotlyPanelState
    definition::PlotDef
    cursor::Base.RefValue{UInt64}
    updates::Observable{Any}
end

function _plotly_trace(trace::TraceDef)
    mode = if trace.mode === :scatter
        "markers"
    elseif trace.mode === :linesscatter
        "lines+markers"
    else
        "lines"
    end
    result = Dict{String,Any}(
        "x" => Float64[],
        "y" => Float64[],
        "name" => trace.label,
        "type" => "scatter",
        "mode" => mode,
        "hovertemplate" => "%{x:.3f}, %{y:.3f}<extra>$(trace.label)</extra>",
    )
    trace.color === nothing || (result["line"] = Dict("color" => string(trace.color)))
    trace.linestyle === nothing ||
        (result["line"] = merge(
            get(result, "line", Dict{String,Any}()),
            Dict("dash" => string(trace.linestyle)),
        ))
    return result
end

function _plotly_layout(definition::PlotDef)
    axis_style = Dict{String,Any}(
        "gridcolor" => "rgba(255,255,255,0.08)",
        "zerolinecolor" => "rgba(255,255,255,0.15)",
        "tickfont" => Dict("color" => TEXT_SECONDARY),
        "titlefont" => Dict("color" => TEXT_PRIMARY),
        "automargin" => true,
    )
    return Dict{String,Any}(
        "title" => Dict("text" => definition.title, "font" => Dict("color" => "#ffffff", "size" => 16)),
        "paper_bgcolor" => DARK_BG,
        "plot_bgcolor" => CARD_BG,
        "font" => Dict("color" => TEXT_PRIMARY),
        "margin" => Dict("l" => 65, "r" => 20, "t" => 48, "b" => 55),
        "xaxis" => merge(copy(axis_style), Dict("title" => Dict("text" => definition.xaxis))),
        "yaxis" => merge(copy(axis_style), Dict("title" => Dict("text" => definition.yaxis))),
        "legend" => Dict("orientation" => "h", "y" => 1.02, "x" => 1.0, "xanchor" => "right", "yanchor" => "bottom"),
        "autosize" => true,
        "uirevision" => definition.graph_id,
    )
end

function build_plotly_panel(session::Session, definition::PlotDef)
    element = DOM.div(; id=definition.graph_id, class="srt-plot-cell")
    traces = [_plotly_trace(trace) for trace in definition.traces]
    layout = _plotly_layout(definition)
    config = Dict{String,Any}(
        "responsive" => true,
        "displaylogo" => false,
        "scrollZoom" => true,
    )
    updates = Observable{Any}(nothing)

    Bonito.onload(session, element, js"""function (element) {
        element._srtPlotlyQueue = [];
        const initialize = () => {
            if (!window.Plotly) {
                window.setTimeout(initialize, 10);
                return;
            }
            window.Plotly.newPlot(element, $(traces), $(layout), $(config)).then(() => {
                element._srtPlotlyReady = true;
                for (const payload of element._srtPlotlyQueue) {
                    window.Plotly.extendTraces(
                        element, {x: payload.x, y: payload.y},
                        payload.indices, payload.maxpoints
                    );
                }
                element._srtPlotlyQueue = [];
            });
        };
        initialize();
    }""")

    Bonito.onjs(session, updates, js"""function (payload) {
        if (!payload) return;
        const element = document.getElementById($(definition.graph_id));
        if (!element) return;
        if (!element._srtPlotlyReady) {
            element._srtPlotlyQueue = element._srtPlotlyQueue || [];
            element._srtPlotlyQueue.push(payload);
            return;
        }
        window.Plotly.extendTraces(
            element, {x: payload.x, y: payload.y},
            payload.indices, payload.maxpoints
        );
    }""")

    return element, PlotlyPanelState(definition, Ref(UInt64(0)), updates)
end

function update_plotly_panel!(
    panel::PlotlyPanelState,
    client::TcpClient;
    maxpoints::Int=1000,
)
    definition = panel.definition
    signal_names = String[definition.x_signal]
    append!(signal_names, trace.signal for trace in definition.traces)

    batches = Vector{Vector{Float64}}(undef, length(signal_names))
    cursors = Vector{UInt64}(undef, length(signal_names))
    for index in eachindex(signal_names)
        batches[index], cursors[index] =
            get_history_since(client, signal_names[index], panel.cursor[])
    end
    any(isempty, batches) && return false

    sample_count = minimum(length, batches)
    x_values = batches[1][end-sample_count+1:end]
    panel.updates[] = Dict{String,Any}(
        "x" => [x_values for _ in definition.traces],
        "y" => [batch[end-sample_count+1:end] for batch in batches[2:end]],
        "indices" => collect(0:length(definition.traces)-1),
        "maxpoints" => maxpoints,
    )
    panel.cursor[] = minimum(cursors)
    return true
end
