# `tutor serve`: a local HTTP server so the website's sandbox and practice pages
# can run code with the learner's own Julia. Stdlib only (Sockets).
#
# Running code on request is remote code execution by design, so the boundary
# is who may send a request:
#
# * It listens on 127.0.0.1 only, never on a public interface.
# * Every /api request except the CORS preflight needs `Authorization: Bearer
#   <token>`. The token is random, stored in .tutor/serve-token (readable only
#   by the learner's account in practice) and handed to the website through
#   the URL fragment that `tutor serve` prints (fragments are not sent to any
#   server). A page that does not know the token cannot run code.
# * The custom header makes every cross-origin request preflighted, and only
#   allowlisted origins get CORS approval, so even a page that guessed the
#   token could not read the response or send it from a browser elsewhere.
# * The Host header must be 127.0.0.1:<port> or localhost:<port>, which stops
#   DNS-rebinding pages from posing as same-origin.
# * Bodies are capped at 256 kB, one job runs at a time, and each job has a
#   timeout.
#
# And what the code can do once it runs: by default (`--sandbox=docker`) each
# job runs in a fresh container with no network, a read-only file system
# except its own work directory, no capabilities and memory/CPU/process limits
# (src/runner.jl, `run_contained`). `serve` refuses to start without the image
# unless given `--sandbox=none`, which runs plain processes as the learner.

module Server

using Sockets, Random, SHA, Base64
using ..JSON, ..Course, ..Practice, ..Runner

export serve, handle, Request, Response, ServerConfig, read_request

const MAX_BODY = 256 * 1024
const MAX_HEADER = 16 * 1024
const DEFAULT_PORT = 8749   # 8765 is a popular dev-tool port; the website defaults to this one too
const DEFAULT_ORIGINS = ["https://adamezzat1.github.io", "http://localhost:4322", "http://127.0.0.1:4322"]

struct Request
    method::String
    path::String
    headers::Dict{String,String}   # lower-case names
    body::String
end

struct Response
    status::Int
    headers::Vector{Pair{String,String}}
    body::String
end

struct ServerConfig
    port::Int
    token::String
    origins::Vector{String}
    units::Vector{Course.Unit}
    lock::ReentrantLock
end
ServerConfig(; port = DEFAULT_PORT, token, origins = DEFAULT_ORIGINS, units = Course.load_course()) =
    ServerConfig(port, token, origins, units, ReentrantLock())

const REASONS = Dict(200 => "OK", 204 => "No Content", 400 => "Bad Request", 401 => "Unauthorized",
                     403 => "Forbidden", 404 => "Not Found", 405 => "Method Not Allowed",
                     413 => "Payload Too Large", 421 => "Misdirected Request", 500 => "Internal Server Error")

new_token() = bytes2hex(rand(RandomDevice(), UInt8, 24))

"""Constant-time comparison (the token is a secret)."""
function secure_equal(a::AbstractString, b::AbstractString)
    x = codeunits(a); y = codeunits(b)
    length(x) == length(y) || return false
    acc = 0x00
    for i in eachindex(x)
        acc |= x[i] ⊻ y[i]
    end
    return acc == 0x00
end

function cors_headers(cfg::ServerConfig, req::Request)
    o = get(req.headers, "origin", "")
    o in cfg.origins || return Pair{String,String}[]
    return ["Access-Control-Allow-Origin" => o, "Vary" => "Origin"]
end

json_response(cfg, req, status, x) =
    Response(status, vcat(["Content-Type" => "application/json; charset=utf-8", "Cache-Control" => "no-store"],
                          cors_headers(cfg, req)), JSON.to_json_compact(x))
err(cfg, req, status, msg) = json_response(cfg, req, status, Dict("error" => msg))

envs() = sort!([d for d in readdir(joinpath(Course.COURSE_DIR, "envs")) if isdir(Course.env_dir(d))])

"""The whole request policy; no sockets, so it is unit-tested directly."""
function handle(cfg::ServerConfig, req::Request; run = Practice.run_code, gradefn = Practice.grade)
    host = get(req.headers, "host", "")
    host in ("127.0.0.1:$(cfg.port)", "localhost:$(cfg.port)") ||
        return err(cfg, req, 421, "unexpected Host header")
    origin = get(req.headers, "origin", "")
    !isempty(origin) && !(origin in cfg.origins) &&
        return err(cfg, req, 403, "origin $origin is not allowed (start the server with --allow-origin=$origin)")
    if req.method == "OPTIONS"
        isempty(origin) && return err(cfg, req, 403, "preflight without an Origin")
        h = vcat(cors_headers(cfg, req),
                 ["Access-Control-Allow-Methods" => "GET, POST, OPTIONS",
                  "Access-Control-Allow-Headers" => "Authorization, Content-Type",
                  "Access-Control-Max-Age" => "600"])
        # Chrome's Private/Local Network Access: a public page asking a loopback server.
        get(req.headers, "access-control-request-private-network", "") == "true" &&
            push!(h, "Access-Control-Allow-Private-Network" => "true")
        return Response(204, h, "")
    end
    auth = get(req.headers, "authorization", "")
    (startswith(auth, "Bearer ") && secure_equal(chop(auth; head = 7, tail = 0), cfg.token)) ||
        return err(cfg, req, 401, "missing or wrong token: open the link `tutor serve` printed")
    if req.path == "/api/health"
        req.method == "GET" || return err(cfg, req, 405, "use GET")
        return json_response(cfg, req, 200, Dict("ok" => true, "julia" => string(VERSION), "envs" => envs(),
                                                    "sandbox" => string(Runner.SANDBOX[])))
    end
    req.path in ("/api/run", "/api/grade") || return err(cfg, req, 404, "no such endpoint")
    req.method == "POST" || return err(cfg, req, 405, "use POST")
    body = try
        JSON.parse_json(req.body)
    catch e
        return err(cfg, req, 400, sprint(showerror, e))
    end
    body isa AbstractDict && get(body, "code", nothing) isa String ||
        return err(cfg, req, 400, "body must be a JSON object with a string field `code`")
    code = body["code"]
    if req.path == "/api/run"
        env = get(body, "env", "base")
        env isa String && env in envs() || return err(cfg, req, 400, "unknown environment")
        mode = get(body, "mode", "repl")
        mode in ("repl", "file") || return err(cfg, req, 400, "mode must be repl or file")
        r = lock(cfg.lock) do
            run(code; env, mode, timeout = Practice.run_timeout(env))
        end
        images = Any[Dict("name" => i.name, "mime" => i.mime, "data" => base64encode(i.data)) for i in r.images]
        return json_response(cfg, req, 200, Dict("output" => r.output, "ok" => r.ok, "timed_out" => r.timed_out,
                                                 "seconds" => round(r.seconds; digits = 2), "images" => images))
    else
        pid = get(body, "problem", nothing)
        found = pid isa String ? Course.find_problem(cfg.units, pid) : nothing
        found === nothing && return err(cfg, req, 404, "unknown problem")
        u, p = found
        r = lock(cfg.lock) do
            gradefn(p, code; env = u.env)
        end
        return json_response(cfg, req, 200, r)
    end
end

# ---- HTTP/1.1, just enough --------------------------------------------------------------

struct BadRequest <: Exception
    status::Int
    msg::String
end

function read_request(io::IO)
    head = IOBuffer()
    while true
        line = readline(io; keep = true)
        isempty(line) && throw(BadRequest(400, "connection closed"))
        write(head, line)
        head.size > MAX_HEADER && throw(BadRequest(413, "headers too large"))
        line in ("\r\n", "\n") && break
    end
    lines = split(String(take!(head)), r"\r?\n")
    parts = split(lines[1], ' ')
    length(parts) == 3 || throw(BadRequest(400, "bad request line"))
    method, target = String(parts[1]), String(parts[2])
    headers = Dict{String,String}()
    for l in lines[2:end]
        isempty(l) && continue
        i = findfirst(':', l)
        i === nothing && throw(BadRequest(400, "bad header"))
        headers[lowercase(strip(l[1:i-1]))] = String(strip(l[i+1:end]))
    end
    haskey(headers, "transfer-encoding") && throw(BadRequest(400, "chunked bodies are not supported"))
    n = something(tryparse(Int, get(headers, "content-length", "0")), -1)
    (0 <= n <= MAX_BODY) || throw(BadRequest(413, "body too large"))
    body = n == 0 ? "" : String(read(io, n))
    sizeof(body) == n || throw(BadRequest(400, "short body"))
    path = String(first(split(target, '?')))
    return Request(method, path, headers, body)
end

function write_response(io::IO, r::Response)
    print(io, "HTTP/1.1 ", r.status, " ", get(REASONS, r.status, ""), "\r\n")
    for (k, v) in r.headers
        print(io, k, ": ", v, "\r\n")
    end
    print(io, "Content-Length: ", sizeof(r.body), "\r\nConnection: close\r\n\r\n", r.body)
end

function serve_client(cfg::ServerConfig, sock)
    try
        req = try
            read_request(sock)
        catch e
            e isa BadRequest || rethrow()
            write_response(sock, Response(e.status, Pair{String,String}[], e.msg))
            return
        end
        resp = try
            handle(cfg, req)
        catch e
            @error "request failed" exception = (e, catch_backtrace())
            err(cfg, req, 500, "internal error: " * sprint(showerror, e))
        end
        println(stdout, rpad(req.method, 8), rpad(req.path, 14), resp.status); flush(stdout)
        write_response(sock, resp)
    catch e
        e isa Base.IOError || @error "connection error" exception = e
    finally
        close(sock)
    end
end

const TOKEN_FILE = joinpath(".tutor", "serve-token")

function load_or_create_token(path = TOKEN_FILE)
    isfile(path) && (t = strip(read(path, String)); occursin(r"^[0-9a-f]{48}$", t)) && return String(t)
    mkpath(dirname(path))
    t = new_token()
    write(path, t)
    return t
end

"""Serve until interrupted. Prints the link that hands the token to the website."""
function serve(; port::Int = DEFAULT_PORT, origins = DEFAULT_ORIGINS, site::String = "https://adamezzat1.github.io/julia-tutor/",
               token_file::String = TOKEN_FILE, sandbox::Symbol = :docker)
    if sandbox === :docker
        why = Runner.sandbox_problem()
        if why !== nothing
            println(stderr, "Cannot start the sandbox: ", why, "

",
                    "`tutor serve` runs code that arrives over HTTP, so by default it runs it in a container with no ",
                    "network and a read-only file system. To run it as plain processes with your account's full access ",
                    "instead, start it with `tutor serve --sandbox=none`.")
            return 1
        end
    elseif sandbox !== :none
        println(stderr, "--sandbox must be docker or none"); return 2
    end
    Runner.SANDBOX[] = sandbox
    cfg = ServerConfig(; port, token = load_or_create_token(token_file), origins)
    server = try
        listen(Sockets.localhost, port)
    catch e
        e isa Base.IOError && e.code == Base.UV_EADDRINUSE || rethrow()
        println(stderr, "Port $port on 127.0.0.1 is already in use by another program. ",
                "Pick another one with `tutor serve --port=<n>` (the website asks for the port when you connect by hand).")
        return 1
    end
    println("julia-tutor sandbox server: http://127.0.0.1:$port  (Julia $(VERSION), loopback only)")
    println("Allowed origins: ", join(cfg.origins, ", "))
    println(sandbox === :docker ?
            "Sandbox: each run in a fresh container ($(Runner.SANDBOX_IMAGE)): no network, read-only files, $(Runner.CONTAINER_MEMORY) memory" :
            "Sandbox: NONE. Code runs as plain processes with your account's access to files and the network (--sandbox=none).")
    println()
    println("Open this link to connect the website (the token stays in the URL fragment, never sent anywhere):")
    println("  ", rstrip(site, '/'), "/sandbox.html#connect=", port, ".", cfg.token)
    println()
    println("Press Ctrl-C to stop.")
    flush(stdout)   # the link must appear even when stdout is a pipe or a file
    try
        while true
            sock = accept(server)
            @async serve_client(cfg, sock)
        end
    catch e
        e isa InterruptException || rethrow()
    finally
        close(server)
    end
    return 0
end

end # module Server
