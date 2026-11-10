# Runs a project's tests (or measurements) in a fresh Julia process.
#
# Two ways to run a child:
#
# * `run_julia_script`: a plain process. Process isolation (fresh process per
#   run, so no leftover methods, globals or world-age state), a timeout, pinned
#   thread counts and an offline package manager, but NOT containment: the code
#   can read and write the learner's files, open sockets, `run` programs and
#   `ccall` libc. Only for code the learner typed themselves (`tutor test`,
#   `tutor run`, `tutor practice`), like typing `julia file.jl`.
# * `run_contained`: the same child inside a Docker container (image built by
#   `tutor sandbox build`, see sandbox/Dockerfile): no network, a read-only root
#   file system, every capability dropped, no privilege escalation, an
#   unprivileged user, and memory, CPU and process-count limits. The only
#   writable places are the run's own work directory and a small /tmp. This is
#   what `tutor serve` uses by default, because there the code arrives over HTTP.

module Runner

using TOML, SHA, Base64

export TestReport, TestsetResult, run_tests, run_julia_script, julia_env, run_contained

const CHILD_DIR = joinpath(@__DIR__, "child")

struct TestsetResult
    name::String
    passed::Int
    failed::Int
    errored::Int
    todo_errors::Int             # how many of the errors are a hole's TODO(hole:...) error
    messages::Vector{String}
    holes::Vector{String}        # hole ids seen in TODO(hole:...) errors
end
ok(t::TestsetResult) = t.failed == 0 && t.errored == 0

struct TestReport
    testsets::Vector{TestsetResult}
    crash::String                # non-empty if the run died outside a testset
    timed_out::Bool
    log::String
end

"""Environment for child processes: pinned threads, offline Pkg, inherited depot."""
function julia_env(; extra_load_path::Vector{String} = String[])
    env = Dict{String,String}()
    for k in ("JULIA_DEPOT_PATH", "PATH", "SYSTEMROOT", "HOME", "USERPROFILE", "TMP", "TEMP", "LOCALAPPDATA", "APPDATA")
        haskey(ENV, k) && (env[k] = ENV[k])
    end
    env["JULIA_NUM_THREADS"] = "1"
    env["OPENBLAS_NUM_THREADS"] = "1"
    env["JULIA_PKG_OFFLINE"] = "true"
    env["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
    # PythonCall (course env `python`): use the Python on PATH, never let
    # CondaPkg download one; GR (Plots) draws to files only, no window.
    env["JULIA_CONDAPKG_BACKEND"] = "Null"
    # (on Windows `python3` is usually the Microsoft Store stub, not Python)
    py = something(Sys.which(Sys.iswindows() ? "python" : "python3"), "")
    isempty(py) || (env["JULIA_PYTHONCALL_EXE"] = get(ENV, "JULIA_PYTHONCALL_EXE", py))
    env["GKSwstype"] = "100"
    if !isempty(extra_load_path)
        sep = Sys.iswindows() ? ";" : ":"
        env["JULIA_LOAD_PATH"] = join(["@"; extra_load_path; "@stdlib"], sep)
    end
    return env
end

"""
    run_julia_script(script, args; project, timeout, env) -> (exitcode, timed_out, log)

Run `script` in a fresh process of the *same* Julia binary as the caller (so the
pinned release), on `threads` threads (1 unless a problem asks for more), with
bounds checks forced on.
"""
function run_julia_script(script::String, args::Vector{String}; project::String,
                          timeout::Real = 600, env = julia_env(), check_bounds::Bool = true,
                          threads::Int = 1, dir::Union{Nothing,String} = nothing)
    # Project tests force bounds checks on (a test must not pass by reading out of
    # bounds). Course code runs with Julia's defaults, so `@inbounds` means what it
    # says and the packages precompiled by `tutor course setup` (default flags)
    # are reused instead of being recompiled on every run.
    cb = check_bounds ? `--check-bounds=yes` : ``
    cmd = `$(Base.julia_cmd()) --startup-file=no --history-file=no --threads=$threads
           $cb --project=$project $script $args`
    dir === nothing || (cmd = Cmd(cmd; dir))   # files the code writes land in `dir`, not our cwd
    # A private, writable first depot entry per run: the student package's
    # compile cache goes there (and is deleted), so concurrent runs never contend
    # for the shared depot's pidfile lock on the same package, and the shared
    # depot stays read-only in spirit (the M3 sandbox will make it read-only).
    private = mktempdir()
    env = copy(env)
    env["JULIA_NUM_THREADS"] = string(threads)
    shared = get(env, "JULIA_DEPOT_PATH", get(ENV, "JULIA_DEPOT_PATH", join(DEPOT_PATH, Sys.iswindows() ? ";" : ":")))
    env["JULIA_DEPOT_PATH"] = private * (Sys.iswindows() ? ";" : ":") * shared
    # Output goes to a file, not an IOBuffer: an IOBuffer needs an async copy
    # task, and reading it right after the process exits races that task
    # (observed: an empty capture). A file is an OS stream, so nothing races.
    logfile = joinpath(private, "child.log")
    proc = open(logfile, "w") do io
        run(pipeline(setenv(cmd, env); stdout = io, stderr = io); wait = false)
    end
    status = timedwait(() -> process_exited(proc), float(timeout); pollint = 0.1)
    timed_out = status === :timed_out
    timed_out && kill(proc)
    wait(proc)
    log = isfile(logfile) ? read(logfile, String) : ""
    # Windows may still hold a lock on a file the child loaded; a leftover temp
    # directory must not turn a finished run into an error.
    try rm(private; recursive = true, force = true) catch end
    return (timed_out ? -1 : proc.exitcode, timed_out, log)
end

"""
    run_tests(pkgdir; timeout = 600) -> TestReport

Run `pkgdir/test/runtests.jl` under a root testset that records results instead
of throwing, then read them back (one entry per testset with direct results).
"""
function run_tests(pkgdir::AbstractString; timeout::Real = 600)
    pkgdir = abspath(pkgdir)
    out = tempname() * ".toml"
    _, timed_out, log = run_julia_script(joinpath(CHILD_DIR, "run_tests.jl"), [pkgdir, out];
                                         project = pkgdir, timeout)
    if !isfile(out)
        return TestReport(TestsetResult[], timed_out ? "timed out after $(timeout)s" :
                          "test process died before reporting (see log)", timed_out, log)
    end
    d = TOML.parsefile(out)
    rm(out; force = true)
    sets = [TestsetResult(t["name"], t["passed"], t["failed"], t["errored"], t["todo_errors"],
                          String.(t["messages"]), String.(t["holes"])) for t in d["testsets"]]
    return TestReport(sets, d["crash"], timed_out, log)
end

# ---- containment -------------------------------------------------------------------
#
# Nothing of the host is mounted: the child scripts and the course environments
# are baked into the image (`tutor sandbox build`), the job goes in on stdin and
# the files the child writes come back on stdout between two marker lines. So
# the container cannot see or touch a single host file, and no Docker file
# sharing setting is needed. The image carries a hash of what it baked in;
# `sandbox_problem` reports a stale image.

const SANDBOX_IMAGE = "julia-tutor-sandbox:1.10.13"
const SANDBOX_DIR = normpath(joinpath(@__DIR__, "..", "sandbox"))
const ENVS_DIR = normpath(joinpath(@__DIR__, "..", "course", "envs"))
const HASH_LABEL = "julia-tutor.inputs"
"""Where course code runs: `:none` (plain process) or `:docker` (`run_contained`)."""
const SANDBOX = Ref(:none)

# 6 GB: loading Makie, Turing or DifferentialEquations peaks above 2 GB, and
# compiling MLJ's `evaluate` inside a function peaks at 3.8 GB (mostly compiler
# memory, not the GC heap); a grade that also compiles a second path (fit! and
# predict_mode in a wrong answer) went past 4 GB and was killed (exit 137).
# The server runs one container at a time (`ServerConfig.lock`).
const CONTAINER_MEMORY = "6g"
# Julia 1.10's GC does not see the container's limit; the hint makes it collect
# before garbage piles up to it. A GC target only: the hard limit stays
# CONTAINER_MEMORY.
const CONTAINER_HEAP_HINT = "4G"
# `docker run` reports a container the kernel killed for memory as exit 137.
const OOM_EXIT = 137
const CONTAINER_PIDS = 512
const FILES_BEGIN = "<<<julia-tutor-files-begin>>>"
const FILES_END = "<<<julia-tutor-files-end>>>"

"""Files baked into the image: published path => host path."""
function sandbox_inputs()
    files = Pair{String,String}["Dockerfile" => joinpath(SANDBOX_DIR, "Dockerfile")]
    for f in sort!(readdir(CHILD_DIR))
        push!(files, "child/" * f => joinpath(CHILD_DIR, f))
    end
    for (root, _, fs) in walkdir(ENVS_DIR), f in sort(fs)
        rel = replace(relpath(joinpath(root, f), ENVS_DIR), '\\' => '/')
        push!(files, "envs/" * rel => joinpath(root, f))
    end
    return sort!(files; by = first)
end

"""SHA-256 over the baked-in files (names and contents, line endings normalised)."""
function sandbox_hash()
    io = IOBuffer()
    for (name, path) in sandbox_inputs()
        print(io, name, '\0', replace(read(path, String), "\r\n" => "\n"), '\0')
    end
    return bytes2hex(SHA.sha256(take!(io)))
end

"""
Run `cmd` quietly: true if it succeeds within `timeout` seconds. A hung Docker
engine never answers `docker info`, so without the limit every command that
checks for the sandbox (the test suite included) would wait forever.
"""
function ok_cmd(cmd; timeout = 30)
    p = run(pipeline(ignorestatus(cmd); stdout = devnull, stderr = devnull); wait = false)
    timedwait(() -> process_exited(p), timeout) === :ok || (kill(p); return false)
    return success(p)
end

"""`nothing` if the sandbox image is usable, else a sentence saying what is missing."""
function sandbox_problem()
    Sys.which("docker") === nothing && return "Docker is not installed (no `docker` on PATH)."
    ok_cmd(`docker info`) || return "Docker is installed but not running (`docker info` failed or gave no answer within 30 s). Start or restart Docker Desktop or the daemon."
    ok_cmd(`docker image inspect $SANDBOX_IMAGE`) ||
        return "The sandbox image $SANDBOX_IMAGE is not built yet. Run `./tutor sandbox build` (downloads julia:1.10.13 and the course packages once)."
    label = try
        strip(read(`docker image inspect --format "{{ index .Config.Labels \"$HASH_LABEL\" }}" $SANDBOX_IMAGE`, String))
    catch
        ""
    end
    label == sandbox_hash() ||
        return "The sandbox image is out of date (src/child or course/envs changed since it was built). Run `./tutor sandbox build`."
    return nothing
end

"""Build the image from a fresh context holding only the baked-in files."""
function build_sandbox()
    ctx = mktempdir()
    for (name, path) in sandbox_inputs()
        dest = joinpath(ctx, split(name, '/')...)
        mkpath(dirname(dest)); cp(path, dest)
    end
    run(`docker build --label $HASH_LABEL=$(sandbox_hash()) -t $SANDBOX_IMAGE $ctx`)
    rm(ctx; recursive = true, force = true)
    return nothing
end

container_user() = Sys.iswindows() ? "1000:1000" :
    string(ccall(:getuid, Cuint, ()), ":", ccall(:getgid, Cuint, ()))

# CPUs Docker can hand out (Docker Desktop's VM may have fewer than the host);
# `--cpus` above it is an error. Asked once.
const DOCKER_CPUS = Ref(0)
function docker_cpus()
    if DOCKER_CPUS[] == 0
        DOCKER_CPUS[] = something(tryparse(Int, strip(try read(`docker info --format "{{.NCPU}}"`, String) catch; "" end)), 1)
    end
    return DOCKER_CPUS[]
end

"""
The `docker run` argument list (no I/O, so it is unit-tested). `cpus` caps
CPU time: one per thread plus one for the GC and the runtime, at most `maxcpus`.
"""
function docker_args(; project_env::String, threads::Int = 1, name::String, maxcpus::Int = threads + 1)
    return String["run", "--rm", "-i", "--name", name,
        "--network=none", "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges",
        "--pids-limit=$CONTAINER_PIDS", "--memory=$CONTAINER_MEMORY", "--memory-swap=$CONTAINER_MEMORY",
        "--cpus=$(clamp(threads + 1, 1, max(maxcpus, 1)))", "--user", container_user(),
        "--tmpfs", "/tmp:rw,exec,size=512m,mode=1777",
        "-e", "HOME=/tmp", "-e", "JULIA_DEPOT_PATH=/tmp/depot:/depot", "-e", "JULIA_PKG_OFFLINE=true",
        "-e", "JULIA_PKG_PRECOMPILE_AUTO=0", "-e", "JULIA_NUM_THREADS=$threads", "-e", "OPENBLAS_NUM_THREADS=1",
        SANDBOX_IMAGE, "julia", "--startup-file=no", "--history-file=no", "--threads=$threads",
        "--heap-size-hint=$CONTAINER_HEAP_HINT",
        "--project=/tutor/envs/$project_env", "/tutor/child/contained.jl"]
end

"""
Split the container's output into the log (what the code printed) and the files
the child wrote (between the marker lines, which `contained.jl` prints last,
base64-encoded so figures survive).
"""
function split_files(out::AbstractString)
    none = Dict{String,Vector{UInt8}}()
    i = findlast(FILES_BEGIN, out)
    i === nothing && return (String(out), none)
    j = findnext(FILES_END, out, last(i))
    j === nothing && return (String(out), none)
    files = try
        Dict{String,Vector{UInt8}}(String(k) => base64decode(v)
                                   for (k, v) in TOML.parse(out[nextind(out, last(i)):prevind(out, first(j))]))
    catch
        none
    end
    # contained.jl prints exactly one newline before the marker
    log = out[1:prevind(out, first(i))]
    return (String(endswith(log, "\n") ? chop(log) : log), files)
end

"""
    run_contained(files, args; project_env, timeout, threads) -> (exitcode, timed_out, log, outfiles)

Run the sandbox child in a fresh container. `files` (name => content) are
written to its work directory, `args` refer to them by name; `outfiles` are the
files the child created there. On a timeout the container is killed (killing
the `docker run` client alone would leave it running).
"""
function run_contained(files::Dict{String,String}, args::Vector{String}; project_env::String,
                       timeout::Real = 600, threads::Int = 1)
    name = "julia-tutor-" * string(rand(UInt64); base = 16)
    cmd = Cmd(["docker"; docker_args(; project_env, threads, name, maxcpus = docker_cpus())])
    dir = mktempdir()
    reqfile = joinpath(dir, "request.toml"); logfile = joinpath(dir, "child.log")
    open(io -> TOML.print(io, Dict("files" => files, "args" => args)), reqfile, "w")
    proc = open(logfile, "w") do io
        run(pipeline(ignorestatus(cmd); stdin = reqfile, stdout = io, stderr = io); wait = false)
    end
    status = timedwait(() -> process_exited(proc), float(timeout); pollint = 0.1)
    timed_out = status === :timed_out
    if timed_out
        run(pipeline(ignorestatus(`docker kill $name`); stdout = devnull, stderr = devnull))
        kill(proc)
    end
    wait(proc)
    out = isfile(logfile) ? read(logfile, String) : ""
    try rm(dir; recursive = true, force = true) catch end
    log, outfiles = split_files(out)
    return (timed_out ? -1 : proc.exitcode, timed_out, log, outfiles)
end

end # module Runner
