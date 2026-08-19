const _MAX_SIGNAL_COUNT = 10_000
const _MAX_SIGNAL_NAME_LEN = 256

function _send_header(sock::Sockets.TCPSocket, names::Vector{String})
    write(sock, htol(UInt32(length(names))))
    for name in names
        encoded = Vector{UInt8}(name)
        write(sock, htol(UInt16(length(encoded))))
        write(sock, encoded)
    end
    flush(sock)
    return nothing
end

"""Read TcpMonitor handshake: UInt32 count + (UInt16 name_len + UTF-8 name) per signal."""
function _read_handshake(sock::Sockets.TCPSocket)
    raw = read(sock, 4)
    n = ltoh(reinterpret(UInt32, raw)[1])
    n > _MAX_SIGNAL_COUNT && error("Handshake signal count $n exceeds limit $_MAX_SIGNAL_COUNT")
    names = String[]
    sizehint!(names, n)
    for _ in 1:n
        slen_raw = read(sock, 2)
        slen = ltoh(reinterpret(UInt16, slen_raw)[1])
        slen > _MAX_SIGNAL_NAME_LEN && error("Signal name length $slen exceeds limit $_MAX_SIGNAL_NAME_LEN")
        name = String(read(sock, Int(slen)))
        push!(names, name)
    end
    return names
end
