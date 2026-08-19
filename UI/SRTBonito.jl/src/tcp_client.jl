"""
TCP client for SystemSimulator TcpMonitor binary protocol.

Connects to a Julia SystemSimulator runtime over two TCP ports:
  - stream port: receives all simulator data (inputs, outputs, params)
  - param port: sends tunable parameter updates

Wire protocol is raw binary Float64 frames with a handshake header.
This is a direct Julia port of the original simulator client used by the web UI.
"""

"""Fixed-capacity signal history with monotonically increasing sample sequence."""
mutable struct HistoryBuffer <: AbstractVector{Float64}
    data::Vector{Float64}
    first::Int
    count::Int
    total::UInt64
end

HistoryBuffer(capacity::Int) = begin
    capacity > 0 || throw(ArgumentError("history capacity must be positive"))
    HistoryBuffer(Vector{Float64}(undef, capacity), 1, 0, UInt64(0))
end

Base.IndexStyle(::Type{HistoryBuffer}) = IndexLinear()
Base.size(history::HistoryBuffer) = (history.count,)
Base.length(history::HistoryBuffer) = history.count

function Base.getindex(history::HistoryBuffer, index::Int)
    checkbounds(history, index)
    physical = mod1(history.first + index - 1, length(history.data))
    return @inbounds history.data[physical]
end

function Base.push!(history::HistoryBuffer, value::Float64)
    capacity = length(history.data)
    if history.count < capacity
        physical = mod1(history.first + history.count, capacity)
        @inbounds history.data[physical] = value
        history.count += 1
    else
        @inbounds history.data[history.first] = value
        history.first = mod1(history.first + 1, capacity)
    end
    history.total += UInt64(1)
    return history
end

mutable struct TcpClient
    host::String
    stream_port::Int
    param_port::Int

    signal_names::Vector{String}
    param_names::Vector{String}

    # History: ring buffer via Vector + manual truncation
    history::Dict{String, HistoryBuffer}
    maxlen::Int
    lock::ReentrantLock
    running::Bool

    stream_sock::Union{Sockets.TCPSocket, Nothing}
    param_sock::Union{Sockets.TCPSocket, Nothing}
    reader_task::Union{Task, Nothing}
end

function TcpClient(; host="localhost", stream_port=9101, param_port=9100, maxlen=3000)
    return TcpClient(
        host, stream_port, param_port,
        String[], String[],
        Dict{String,HistoryBuffer}(), maxlen,
        ReentrantLock(), false,
        nothing, nothing, nothing,
    )
end

"""Connect to the stream port, read handshake, start reader task. (Deprecated: use ensure_connected!)"""
function connect_stream!(client::TcpClient)
    ensure_connected!(client)
    return nothing
end

"""Connect to the param port and read handshake. (Deprecated: use ensure_connected!)"""
function connect_params!(client::TcpClient)
    ensure_connected!(client)
    return nothing
end

"""Ensure both stream and param connections are active, reconnecting if needed."""
function ensure_connected!(client::TcpClient)
    # Fast path: check without lock
    if client.stream_sock !== nothing && isopen(client.stream_sock) && client.running &&
       client.param_sock !== nothing && isopen(client.param_sock)
        return true
    end

    lock(client.lock) do
        # 1. Check/reconnect Stream
        if client.stream_sock === nothing || !isopen(client.stream_sock) || !client.running
            client.running = false
            if client.stream_sock !== nothing
                try close(client.stream_sock); catch; end
                client.stream_sock = nothing
            end
            try
                sock = Sockets.connect(client.host, client.stream_port)
                names = _read_handshake(sock)
                client.stream_sock = sock
                client.signal_names = names
                for name in names
                    if !haskey(client.history, name)
                        client.history[name] = HistoryBuffer(client.maxlen)
                    end
                end
                client.running = true
                client.reader_task = @async _reader_loop!(client)
                @info "Stream connected" signals=length(names)
            catch e
                # Avoid spamming logs, just quiet warning
                @debug "Stream connection attempt failed" exception=e
            end
        end

        # 2. Check/reconnect Params
        if client.param_sock === nothing || !isopen(client.param_sock)
            if client.param_sock !== nothing
                try close(client.param_sock); catch; end
                client.param_sock = nothing
            end
            try
                sock = Sockets.connect(client.host, client.param_port)
                names = _read_handshake(sock)
                client.param_sock = sock
                client.param_names = names
                @info "Params connected" params=length(names)
            catch e
                @debug "Params connection attempt failed" exception=e
            end
        end
    end

    return client.stream_sock !== nothing && client.param_sock !== nothing
end

"""Background task: read Float64 frames, append to history."""
function _reader_loop!(client::TcpClient)
    n = length(client.signal_names)
    frame_size = n * sizeof(Float64)
    buf = Vector{UInt8}(undef, frame_size)
    while client.running
        try
            nread = 0
            while nread < frame_size
                chunk = read(client.stream_sock, frame_size - nread)
                isempty(chunk) && error("Socket closed")
                copyto!(buf, nread + 1, chunk, 1, length(chunk))
                nread += length(chunk)
            end
            values = reinterpret(Float64, buf)
            lock(client.lock) do
                for (i, name) in enumerate(client.signal_names)
                    h = client.history[name]
                    push!(h, ltoh(values[i]))
                end
            end
        catch e
            if client.running
                @warn "Stream connection lost" exception=(e, catch_backtrace())
            end
            client.running = false
            lock(client.lock) do
                try close(client.stream_sock); catch; end
                client.stream_sock = nothing
            end
            break
        end
    end
    return nothing
end

"""Send parameter values in declared order. Returns true on success."""
function send_params!(client::TcpClient, param_dict::Dict{String,Float64})
    # Ensure connection is established
    ensure_connected!(client)

    client.param_sock === nothing && return false
    isempty(client.param_names) && return false
    values = [get(param_dict, name, 0.0) for name in client.param_names]
    le_values = htol.(values)
    payload = reinterpret(UInt8, le_values)

    lock(client.lock) do
        try
            if client.param_sock !== nothing && isopen(client.param_sock)
                write(client.param_sock, payload)
                flush(client.param_sock)
                return true
            end
        catch e
            @warn "Param send failed" exception=(e, catch_backtrace())
            try close(client.param_sock); catch; end
            client.param_sock = nothing
        end
        return false
    end
end

"""Return a copy of the history buffer for a signal."""
function get_history(client::TcpClient, name::String)
    lock(client.lock) do
        buf = get(client.history, name, nothing)
        buf === nothing && return Float64[]
        return collect(buf)
    end
end

"""
    get_history_since(client, name, cursor) -> (samples, next_cursor)

Return only samples appended after `cursor`. If the cursor predates the retained
ring-buffer window, return the complete retained window.
"""
function get_history_since(client::TcpClient, name::String, cursor::UInt64)
    lock(client.lock) do
        history = get(client.history, name, nothing)
        history === nothing && return Float64[], cursor

        retained_start = history.total - UInt64(history.count)
        effective_cursor = max(cursor, retained_start)
        new_count = Int(history.total - effective_cursor)
        new_count == 0 && return Float64[], history.total

        first_logical = history.count - new_count + 1
        samples = Vector{Float64}(undef, new_count)
        for output_index in eachindex(samples)
            samples[output_index] = history[first_logical + output_index - 1]
        end
        return samples, history.total
    end
end

"""Return the latest value of a signal, or nothing."""
function get_latest(client::TcpClient, name::String)
    lock(client.lock) do
        buf = get(client.history, name, nothing)
        (buf === nothing || isempty(buf)) && return nothing
        return buf[end]
    end
end

"""Close all connections and stop the reader task."""
function close!(client::TcpClient)
    client.running = false
    lock(client.lock) do
        for s in (client.stream_sock, client.param_sock)
            s !== nothing && try; close(s); catch; end
        end
        client.stream_sock = nothing
        client.param_sock = nothing
    end
    if client.reader_task !== nothing
        try; wait(client.reader_task); catch; end
    end
    return nothing
end
