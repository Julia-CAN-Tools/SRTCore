"""
    build_app(config::AppConfig) → Bonito.App

Build a dashboard from application-owned definitions using shared controls,
TCP transport, and locally served Plotly.js panels.
"""
function build_app(config::AppConfig)
    client = TcpClient(;
        stream_port=config.stream_port,
        param_port=config.param_port,
    )
    ensure_connected!(client)

    return App() do session::Session
        sidebar, status_observable, status_class = build_sidebar(
            config.title,
            config.params,
            client;
            include_reset=config.include_reset,
            extra_params=config.extra_params,
            param_builder=config.param_builder,
            sidebar_width=config.sidebar_width,
        )

        panel_elements = Any[]
        panel_states = PlotlyPanelState[]
        for definition in config.plots
            element, state = build_plotly_panel(session, definition)
            push!(panel_elements, element)
            push!(panel_states, state)
        end
        plot_grid = DOM.div(panel_elements...; class="srt-plot-grid")

        interval_seconds = config.interval_ms / 1000.0
        Base.errormonitor(@async begin
            while !isready(session)
                sleep(0.05)
                session.status === Bonito.CLOSED && return
            end

            while isopen(session)
                try
                    sleep(interval_seconds)
                    ensure_connected!(client)
                    for panel in panel_states
                        update_plotly_panel!(
                            panel,
                            client;
                            maxpoints=config.plot_max_points,
                        )
                    end
                    update_status_obs!(client, status_observable, status_class)
                catch error
                    error isa EOFError && break
                    @warn "Dashboard update error" exception=(error, catch_backtrace())
                end
            end
        end)

        return DOM.div(
            PLOTLY_JS,
            dashboard_layout(sidebar, plot_grid),
        )
    end
end

"""Build and serve a dashboard. The returned server blocks when passed to `wait`."""
function serve_app(config::AppConfig)
    app = build_app(config)
    server = Bonito.Server(app, "0.0.0.0", config.port)
    @info "SRTBonito UI running" url="http://localhost:$(config.port)"
    return server
end
