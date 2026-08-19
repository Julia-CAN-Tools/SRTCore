# ── Styles ────────────────────────────────────────────────────────────────

const DARK_BG       = "#0f0f23"
const SIDEBAR_BG    = "#1a1a2e"
const CARD_BG       = "#16213e"
const ACCENT        = "#0f3460"
const TEXT_PRIMARY   = "#e0e0e0"
const TEXT_SECONDARY = "#a0a0b0"
const GREEN          = "#00c853"
const RED            = "#ff1744"
const AMBER          = "#ffc107"
const BORDER         = "#2a2a4a"

const GLOBAL_CSS = DOM.style("""
    * { box-sizing: border-box; margin: 0; padding: 0; }
    body { font-family: 'Inter', 'Segoe UI', system-ui, sans-serif;
           background: $DARK_BG; color: $TEXT_PRIMARY; }

    .srt-sidebar {
        width: 280px; min-width: 280px; padding: 16px;
        overflow-y: auto; border-right: 1px solid $BORDER;
        height: 100vh; background: $SIDEBAR_BG;
    }
    .srt-sidebar h3 { margin: 0 0 12px 0; font-size: 18px; color: #fff; }
    .srt-sidebar h4 {
        margin: 12px 0 6px 0; font-size: 13px; color: $TEXT_SECONDARY;
        text-transform: uppercase; letter-spacing: 0.5px;
    }
    .srt-sidebar hr {
        border: none; border-top: 1px solid $BORDER; margin: 10px 0;
    }

    .srt-slider-label {
        display: block; font-size: 11px; color: $TEXT_SECONDARY; margin-bottom: 2px;
    }
    .srt-slider-container { margin-bottom: 8px; }

    .srt-btn {
        border: none; padding: 8px 20px; font-size: 14px; font-weight: 600;
        border-radius: 6px; cursor: pointer; color: #fff; margin-right: 6px;
        transition: filter 0.15s;
    }
    .srt-btn:hover { filter: brightness(1.15); }
    .srt-btn-start { background: $GREEN; }
    .srt-btn-stop  { background: $RED; }
    .srt-btn-reset { background: #6c757d; }

    .srt-status {
        text-align: center; font-size: 13px; font-weight: 600;
        padding: 6px; border-radius: 6px; margin-top: 8px;
    }
    .srt-status-idle     { background: #2a2a4a; color: $TEXT_SECONDARY; }
    .srt-status-running  { background: #0a3d20; color: $GREEN; }
    .srt-status-finished { background: #3d3a0a; color: $AMBER; }

    .srt-main { display: flex; height: 100vh; background: $DARK_BG; overflow: hidden; }
    .srt-plot-grid {
        display: grid; flex: 1; grid-template-columns: repeat(2, minmax(0, 1fr));
        grid-template-rows: repeat(2, minmax(0, 1fr));
        height: 100%; min-width: 0; overflow: hidden;
    }
    .srt-plot-cell { width: 100%; height: 100%; min-width: 0; min-height: 0; }
""")

# ── Widget factories ──────────────────────────────────────────────────────

"""Create a slider widget. Returns (dom_element, Observable{Float64})."""
function make_slider(p::ParamDef)
    r = range(p.min, p.max; step=p.step)
    slider = Bonito.Slider(r; value=p.default)
    label_el = DOM.label(p.label; class="srt-slider-label")
    container = DOM.div(label_el, slider; class="srt-slider-container")
    return container, slider.value
end

"""Create a dropdown widget. Returns (dom_element, Observable{Float64})."""
function make_dropdown(p::ParamDef)
    opts = something(p.options, [("None", 0.0)])
    labels = first.(opts)
    label_to_val = Dict(label => val for (label, val) in opts)

    # Find the default index
    default_idx = findfirst(x -> x[2] == p.default, opts)
    default_idx = something(default_idx, 1)

    dd = Bonito.Dropdown(labels; index=default_idx)

    # Map selected label → Float64 value
    value_obs = Observable(p.default)
    on(dd.value) do selected_label
        value_obs[] = get(label_to_val, selected_label, 0.0)
    end

    label_el = DOM.label(p.label; style="font-size: 12px; font-weight: 600; color: $(TEXT_SECONDARY);")
    container = DOM.div(label_el, dd; style="margin-bottom: 8px;")
    return container, value_obs
end

"""Create Start/Stop/Reset buttons + status display.

Returns (buttons_dom, status_dom, start_btn, stop_btn, reset_btn_or_nothing, status_obs, status_class).
"""
function make_start_stop_buttons(; include_reset=false)
    start_btn = Bonito.Button("Start"; class="srt-btn srt-btn-start")
    stop_btn  = Bonito.Button("Stop";  class="srt-btn srt-btn-stop")

    btns = Any[start_btn, stop_btn]
    reset_btn = nothing
    if include_reset
        reset_btn = Bonito.Button("Reset"; class="srt-btn srt-btn-reset")
        push!(btns, reset_btn)
    end

    btn_area = DOM.div(btns...;
        style="display: flex; justify-content: center; margin-bottom: 8px;")

    status_obs = Observable("Idle")
    status_class = Observable("srt-status srt-status-idle")
    status_el = DOM.div(status_obs; class=status_class)

    return btn_area, status_el, start_btn, stop_btn, reset_btn, status_obs, status_class
end

"""
    build_sidebar(title, params, client; kwargs...)

Build the shared parameter sidebar and wire its controls to `client`. Application
packages own their parameter definitions; SRTBonito owns their common rendering
and lifecycle command behavior.
"""
function build_sidebar(
    title::String,
    params::Vector{ParamDef},
    client::TcpClient;
    include_reset::Bool=false,
    extra_params::Dict{String,Float64}=Dict{String,Float64}(),
    param_builder::Union{Function,Nothing}=nothing,
    sidebar_width::String="280px",
)
    sidebar_children = Any[DOM.h3(title)]
    widget_map = OrderedDict{String,Observable}()
    groups = OrderedDict{String,Vector{ParamDef}}()

    for param in params
        push!(get!(groups, param.group, ParamDef[]), param)
    end
    for (group_name, param_list) in groups
        if !isempty(group_name)
            push!(sidebar_children, DOM.hr(), DOM.h4(group_name))
        end
        for param in param_list
            element, observable =
                param.kind == :dropdown ? make_dropdown(param) : make_slider(param)
            push!(sidebar_children, element)
            widget_map[param.key] = observable
        end
    end

    button_area, status_element, start_button, stop_button, reset_button,
        status_observable, status_class =
        make_start_stop_buttons(; include_reset=include_reset)
    push!(sidebar_children, DOM.hr(), button_area, status_element)

    start_count = Observable(0)
    stop_count = Observable(0)
    reset_count = Observable(0)
    previous_reset = Ref(0)

    function sync_params!()
        ensure_connected!(client)
        widget_values =
            Dict{String,Float64}(key => Float64(value[]) for (key, value) in widget_map)
        values = param_builder === nothing ? widget_values : param_builder(widget_values)
        merge!(values, extra_params)
        values["start_cmd"] = Float64(start_count[])
        values["stop_cmd"] = Float64(stop_count[])
        if include_reset
            current_reset = reset_count[]
            values["reset"] = current_reset > previous_reset[] ? 1.0 : 0.0
            previous_reset[] = current_reset
        end
        send_params!(client, values)
        return nothing
    end

    on(start_button.value) do clicked
        clicked || return
        start_count[] += 1
        sync_params!()
        start_button.value[] = false
    end
    on(stop_button.value) do clicked
        clicked || return
        stop_count[] += 1
        sync_params!()
        stop_button.value[] = false
    end
    if reset_button !== nothing
        on(reset_button.value) do clicked
            clicked || return
            reset_count[] += 1
            sync_params!()
            reset_button.value[] = false
        end
    end
    for observable in values(widget_map)
        on(observable) do _
            sync_params!()
        end
    end
    sync_params!()

    sidebar = DOM.div(
        sidebar_children...;
        class="srt-sidebar",
        style="width: $sidebar_width; min-width: $sidebar_width;",
    )
    return sidebar, status_observable, status_class
end

"""Update the standard Idle/Running/Finished status observables."""
function update_status_obs!(client::TcpClient, status_observable, status_class)
    running_value = get_latest(client, "running")
    elapsed = something(get_latest(client, "elapsed"), 0.0)
    duration = something(get_latest(client, "duration"), 30.0)

    if running_value !== nothing && running_value >= 0.5
        status_observable[] =
            "Running: $(round(elapsed; digits=1)) / $(round(Int, duration)) s"
        status_class[] = "srt-status srt-status-running"
    elseif elapsed > 0.5
        status_observable[] = "Finished: $(round(elapsed; digits=1)) s"
        status_class[] = "srt-status srt-status-finished"
    else
        status_observable[] = "Idle"
        status_class[] = "srt-status srt-status-idle"
    end
    return nothing
end

"""
    fetch_histories!(observables, client, signals) -> Bool

Copy equally sized signal histories into matching observables. Returns `false`
until every requested signal has data.
"""
function fetch_histories!(observables, client::TcpClient, signals)
    length(observables) == length(signals) ||
        throw(DimensionMismatch("one observable is required per signal"))
    histories = [get_history(client, String(signal)) for signal in signals]
    any(isempty, histories) && return false
    sample_count = minimum(length, histories)
    for (observable, history) in zip(observables, histories)
        observable[] = history[1:sample_count]
    end
    return true
end

"""
    append_histories!(observables, client, signals, cursor; maxlen=1000) -> Bool

Append only samples received after `cursor[]`, retaining at most `maxlen` points
in each browser-facing observable. All signals are frame-aligned by using the
smallest available incremental batch.
"""
function append_histories!(
    observables,
    client::TcpClient,
    signals,
    cursor::Base.RefValue{UInt64};
    maxlen::Int=1000,
)
    length(observables) == length(signals) ||
        throw(DimensionMismatch("one observable is required per signal"))
    maxlen > 0 || throw(ArgumentError("maxlen must be positive"))

    batches = Vector{Vector{Float64}}(undef, length(signals))
    next_cursors = Vector{UInt64}(undef, length(signals))
    for index in eachindex(signals)
        batches[index], next_cursors[index] =
            get_history_since(client, String(signals[index]), cursor[])
    end
    any(isempty, batches) && return false

    new_count = min(minimum(length, batches), maxlen)
    for (observable, batch) in zip(observables, batches)
        current = observable[]
        combined_count = min(maxlen, length(current) + new_count)
        updated = Vector{Float64}(undef, combined_count)
        old_to_keep = combined_count - new_count
        if old_to_keep > 0
            copyto!(updated, 1, current, length(current) - old_to_keep + 1, old_to_keep)
        end
        copyto!(updated, old_to_keep + 1, batch, length(batch) - new_count + 1, new_count)
        observable[] = updated
    end
    cursor[] = minimum(next_cursors)
    return true
end

"""Wrap an application-owned dashboard body in the shared SRT page layout."""
dashboard_layout(sidebar, body) =
    DOM.div(GLOBAL_CSS, DOM.div(sidebar, body; class="srt-main"))
