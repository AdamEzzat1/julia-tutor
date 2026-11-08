# Runs a project's tests (or measurements) in a fresh Julia process.
#
# THIS IS NOT A SANDBOX. It gives process isolation (fresh process per run, so
# no leftover methods, globals or world-age state), a timeout, pinned thread
# counts and an offline package manager. It does NOT stop student code from
# reading/writing files, opening sockets, `run`ning programs or `ccall`ing libc.
# That containment must come from the OS and is milestone M3 (see CLAUDE.md).
# Until then the runner is only for code the student wrote themselves on their
# own machine (equivalent to them typing `julia test/runtests.jl`).

module Runner

using TOML

export TestReport, TestsetResult, run_tests, run_julia_script, julia_env

const CHILD_DIR = joinpath(@__DIR__, "child")

struct TestsetResult
    name::String
    passed::Int
    failed::Int
    errored::Int
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
    if !isempty(extra_load_path)
        sep = Sys.iswindows() ? ";" : ":"
        env["JULIA_LOAD_PATH"] = join(["@"; extra_load_path; "@stdlib"], sep)
    end
    return env
end

"""
    run_julia_script(script, args; project, timeout, env) -> (exitcode, timed_out, log)

Run `script` in a fresh process of the *same* Julia binary as the caller (so the
pinned release), single-threaded, with bounds checks forced on.
"""
function run_julia_script(script::String, args::Vector{String}; project::String,
                          timeout::Real = 600, env = julia_env())
    cmd = `$(Base.julia_cmd()) --startup-file=no --history-file=no --threads=1
           --check-bounds=yes --project=$project $script $args`
    # A private, writable first depot entry per run: the student package's
    # compile cache goes there (and is deleted), so concurrent runs never contend
    # for the shared depot's pidfile lock on the same package, and the shared
    # depot stays read-only in spirit (the M3 sandbox will make it read-only).
    private = mktempdir()
    env = copy(env)
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
    rm(private; recursive = true, force = true)
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
    sets = [TestsetResult(t["name"], t["passed"], t["failed"], t["errored"],
                          String.(t["messages"]), String.(t["holes"])) for t in d["testsets"]]
    return TestReport(sets, d["crash"], timed_out, log)
end

end # module Runner
