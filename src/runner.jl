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
using ..JSON

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
# sharing setting is needed. Each image carries a hash of what it baked in;
# `sandbox_problem` reports a stale one.
#
# One image per course (docs/COURSES_PLAN.md, Phase 2): `base` holds Julia, the
# base environment and the child scripts, and Core Julia runs in it; a course
# with environments of its own gets an image with only those, built on base's
# `runtime` stage (sandbox/<course>.Dockerfile). An environment belongs to one
# course (Course.validate_courses), so the environment picks the image.

const SANDBOX_DIR = normpath(joinpath(@__DIR__, "..", "sandbox"))
const ENVS_DIR = normpath(joinpath(@__DIR__, "..", "course", "envs"))
const COURSES_DIR = normpath(joinpath(@__DIR__, "..", "course", "courses"))
const HASH_LABEL = "julia-tutor.inputs"
const IMAGE_PREFIX = "julia-tutor-sandbox"
"""Where published images live (GitHub Container Registry, pushed by CI)."""
const REGISTRY = "ghcr.io/adamezzat1"
"""The digests of the published images and the inputs they were built from."""
const IMAGES_FILE = joinpath(SANDBOX_DIR, "images.toml")
"""Where course code runs: `:none` (plain process) or `:docker` (`run_contained`)."""
const SANDBOX = Ref(:none)

# 6 GB: loading Makie, Turing or DifferentialEquations peaks above 2 GB, and
# compiling MLJ's `evaluate` inside a function peaks at 3.8 GB (mostly compiler
# memory, not the GC heap); a grade that also compiles a second path (fit! and
# predict_mode in a wrong answer) went past 4 GB and was killed (exit 137).
# The server runs one container at a time (`ServerConfig.lock`).
const CONTAINER_MEMORY = "6g"
# Per image, so a course that needs less can say so. Every image keeps 6 GB
# until its peak is measured in the container (`tutor sandbox measure`, and
# the peaks `tutor course verify --sandbox=docker` prints): docs/SANDBOX_IMAGES.md.
const IMAGE_MEMORY = Dict("base" => CONTAINER_MEMORY, "science" => CONTAINER_MEMORY,
                          "scicomp" => CONTAINER_MEMORY, "sciml" => CONTAINER_MEMORY)
# Julia 1.10's GC does not see the container's limit; the hint makes it collect
# before garbage piles up to it. A GC target only: the hard limit stays the
# image's memory. Two thirds of it, as 4G is of 6g.
heap_hint(memory::AbstractString) = string(parse(Int, chop(memory)) * 2 ÷ 3, "G")
const CONTAINER_HEAP_HINT = heap_hint(CONTAINER_MEMORY)
# `docker run` reports a container the kernel killed for memory as exit 137.
const OOM_EXIT = 137
const CONTAINER_PIDS = 512
const FILES_BEGIN = "<<<julia-tutor-files-begin>>>"
const FILES_END = "<<<julia-tutor-files-end>>>"
# contained.jl prints the container's cgroup memory peak after the files. A
# measurement only (`MEMORY_PEAKS`): the learner's code could print a fake one
# from an atexit hook, so nothing is decided by it.
const PEAK_PREFIX = "<<<julia-tutor-memory-peak>>> "

"""
Image => the environments it adds to the base environment, from the course
manifests (course/courses/*.toml, `envs`). A course whose only environment is
base (Core Julia) runs in the base image and has no entry of its own.
"""
function image_envs(dir::String = COURSES_DIR)
    d = Dict{String,Vector{String}}("base" => String[])
    for f in sort!(readdir(dir))
        endswith(f, ".toml") || continue
        m = TOML.parsefile(joinpath(dir, f))
        extra = sort!([String(e) for e in get(m, "envs", String[]) if e != "base"])
        isempty(extra) || (d[String(m["id"])] = extra)
    end
    return d
end

"""Every image: base first, then the course images in name order."""
images() = ["base"; sort!([i for i in keys(image_envs()) if i != "base"])]

"""The image a course's code runs in."""
course_image(course::AbstractString) = haskey(image_envs(), course) ? String(course) : "base"

"""The course an image is for, as `tutor sandbox pull|build` names it (base is Core Julia's)."""
image_course(img::AbstractString) = img == "base" ? "core" : String(img)

"""The image an environment runs in."""
function env_image(env::AbstractString)
    env == "base" && return "base"
    for (img, es) in image_envs()
        env in es && return img
    end
    error("environment $env is in no course's image (course/courses/*.toml, envs)")
end

"""The local tag of an image (what `docker run` starts)."""
image_name(img::AbstractString) = "$IMAGE_PREFIX-$img:$VERSION"
"""The local tag of base.Dockerfile's `runtime` stage, which course images start from."""
const RUNTIME_IMAGE = "$IMAGE_PREFIX-runtime:$VERSION"
image_memory(img::AbstractString) = get(IMAGE_MEMORY, img, CONTAINER_MEMORY)

"""Files baked into an image: published path => host path."""
function sandbox_inputs(img::AbstractString = "base")
    files = Pair{String,String}["base.Dockerfile" => joinpath(SANDBOX_DIR, "base.Dockerfile")]
    img == "base" || push!(files, "$img.Dockerfile" => joinpath(SANDBOX_DIR, "$img.Dockerfile"))
    for f in sort!(readdir(CHILD_DIR))
        push!(files, "child/" * f => joinpath(CHILD_DIR, f))
    end
    envs = img == "base" ? ["base"] : ["base"; image_envs()[img]]
    for e in envs, (root, _, fs) in walkdir(joinpath(ENVS_DIR, e)), f in sort(fs)
        rel = replace(relpath(joinpath(root, f), ENVS_DIR), '\\' => '/')
        push!(files, "envs/" * rel => joinpath(root, f))
    end
    return sort!(files; by = first)
end

"""SHA-256 over an image's baked-in files (names and contents, line endings normalised)."""
function sandbox_hash(img::AbstractString = "base")
    io = IOBuffer()
    for (name, path) in sandbox_inputs(img)
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

image_label(ref::AbstractString) = try
    strip(read(pipeline(`docker image inspect --format "{{ index .Config.Labels \"$HASH_LABEL\" }}" $ref`; stderr = devnull), String))
catch
    ""
end

"""
`nothing` if the images are here and up to date, else a sentence saying what
is missing and the command that fixes it.
"""
function sandbox_problem(imgs::Vector{String} = images())
    Sys.which("docker") === nothing && return "Docker is not installed (no `docker` on PATH)."
    ok_cmd(`docker info`) || return "Docker is installed but not running (`docker info` failed or gave no answer within 30 s). Start or restart Docker Desktop or the daemon."
    for img in imgs
        c = image_course(img)
        ok_cmd(`docker image inspect $(image_name(img))`) ||
            return "The sandbox image $(image_name(img)) is not here yet. Run `./tutor sandbox pull $c` " *
                   "(the published image) or `./tutor sandbox build $c` (builds it from this checkout)."
        image_label(image_name(img)) == sandbox_hash(img) ||
            return "The sandbox image $(image_name(img)) is out of date (src/child, sandbox/ or the course's " *
                   "envs changed since it was made). Run `./tutor sandbox pull $c` or `./tutor sandbox build $c`."
    end
    return nothing
end

"""Build an image from a fresh context holding only its baked-in files."""
function build_sandbox(img::AbstractString)
    ctx = mktempdir()
    for (name, path) in sandbox_inputs(img)
        dest = joinpath(ctx, split(name, '/')...)
        mkpath(dirname(dest)); cp(path, dest)
    end
    label = "$HASH_LABEL=$(sandbox_hash(img))"
    base_df = joinpath(ctx, "base.Dockerfile")
    try
        if img == "base"
            run(`docker build -f $base_df --label $label -t $(image_name(img)) $ctx`)
        else
            run(`docker build -f $base_df --target runtime -t $RUNTIME_IMAGE $ctx`)
            run(`docker build -f $(joinpath(ctx, "$img.Dockerfile")) --build-arg RUNTIME=$RUNTIME_IMAGE --label $label -t $(image_name(img)) $ctx`)
        end
    finally
        rm(ctx; recursive = true, force = true)
    end
    return nothing
end

# ---- published images (GHCR) ----------------------------------------------------------
#
# CI pushes each image under a tag made from its input hash (`registry_tag`)
# and the digests go into sandbox/images.toml with the hash they were built
# from. `pull` fetches by that digest, never by tag, and then checks the label
# against this checkout's hash, so a learner gets exactly the image CI verified
# for these inputs, or a sentence saying to build it.

registry_repo(img::AbstractString) = "$REGISTRY/$IMAGE_PREFIX-$img"
"""The tag CI pushes an image under: the Julia version and the first 16 hex digits of its input hash."""
registry_tag(img::AbstractString, hash::AbstractString = sandbox_hash(img)) =
    "$(registry_repo(img)):$VERSION-$(hash[1:16])"

"""sandbox/images.toml: image => (inputs = hash, digest = "sha256:...")."""
published(file::String = IMAGES_FILE) = isfile(file) ? TOML.parsefile(file) : Dict{String,Any}()

valid_digest(d) = d isa AbstractString && occursin(r"^sha256:[0-9a-f]{64}$", d)

"""
Where the published image for `img` is, or a sentence saying why there is
none for this checkout. Pure (no Docker), so it is unit-tested.
"""
function published_ref(img::AbstractString; record = published(), hash = sandbox_hash(img))
    rec = get(record, img, nothing)
    c = image_course(img)
    rec isa AbstractDict ||
        return (nothing, "No published image for $c is recorded in sandbox/images.toml. Run `./tutor sandbox build $c`.")
    valid_digest(get(rec, "digest", nothing)) ||
        return (nothing, "sandbox/images.toml has no valid digest for $img.")
    get(rec, "inputs", "") == hash ||
        return (nothing, "The published $c image was built from other inputs than this checkout (src/child, sandbox/ " *
                         "or the course's envs differ). Run `./tutor sandbox build $c`.")
    return ("$(registry_repo(img))@$(rec["digest"])", nothing)
end

"""Pull an image by its recorded digest and tag it locally; `nothing` or a sentence."""
function pull_image(img::AbstractString)
    ref, why = published_ref(img)
    ref === nothing && return why
    ok_cmd(`docker pull $ref`; timeout = 3600) ||
        return "`docker pull $ref` failed (no network, or the package is not public yet)."
    run(`docker tag $ref $(image_name(img))`)
    return sandbox_problem([String(img)])
end

"""The registry digest Docker recorded for a local image of `img`, or nothing."""
function local_digest(img::AbstractString)
    out = try
        read(pipeline(`docker image inspect --format "{{range .RepoDigests}}{{println .}}{{end}}" $(image_name(img))`; stderr = devnull), String)
    catch
        return nothing
    end
    for l in split(out, '\n')
        p = split(strip(l), '@')
        length(p) == 2 && p[1] == registry_repo(img) && valid_digest(p[2]) && return String(p[2])
    end
    return nothing
end

"""Bytes of a registry manifest's layers and config (what a pull downloads), or nothing."""
function manifest_bytes(m)
    m isa AbstractDict || return nothing
    if haskey(m, "layers")
        return sum(Int(l["size"]) for l in m["layers"]; init = 0) + Int(get(get(m, "config", Dict()), "size", 0))
    end
    return nothing
end

"""
(uncompressed size on disk, compressed bytes a pull downloads) of a local
image; the second is nothing when the image was not published.
"""
function image_sizes(img::AbstractString)
    disk = tryparse(Int, strip(try read(pipeline(`docker image inspect --format "{{.Size}}" $(image_name(img))`; stderr = devnull), String) catch; "" end))
    d = local_digest(img)
    d === nothing && return (disk, nothing)
    ref = "$(registry_repo(img))@$d"
    m = try JSON.parse_json(read(`docker manifest inspect $ref`, String)) catch; nothing end
    # a multi-platform index: measure the linux/amd64 image in it
    if m isa AbstractDict && haskey(m, "manifests")
        i = findfirst(x -> get(get(x, "platform", Dict()), "architecture", "") == "amd64", m["manifests"])
        m = i === nothing ? nothing :
            try JSON.parse_json(read(`docker manifest inspect $(registry_repo(img))@$(m["manifests"][i]["digest"])`, String)) catch; nothing end
    end
    return (disk, manifest_bytes(m))
end

"""
CI: make `img` present and current, from the registry when an image for these
inputs was pushed before (by tag), else by building it and, with `push`,
pushing it. Returns its digest (nothing when built but not pushed).
"""
function publish_image(img::AbstractString; push::Bool)
    tag = registry_tag(img)
    if ok_cmd(`docker pull $tag`; timeout = 3600) && image_label(tag) == sandbox_hash(img)
        println("  $img: pulled $tag (built before from the same inputs)")
        run(`docker tag $tag $(image_name(img))`)
    else
        println("  $img: no image for these inputs in the registry; building")
        build_sandbox(img)
        run(`docker tag $(image_name(img)) $tag`)
        push && run(`docker push $tag`)
    end
    return local_digest(img)
end

"""The text of sandbox/images.toml for these digests (image => digest)."""
function images_toml(digests::AbstractDict)
    io = IOBuffer()
    println(io, "# Published sandbox images, written from CI's `tutor sandbox publish` (see")
    println(io, "# docs/SANDBOX_IMAGES.md). `tutor sandbox pull <course>` fetches by digest and")
    println(io, "# refuses when `inputs` is not this checkout's hash. Never edit by hand.")
    for img in images()
        haskey(digests, img) || continue
        println(io, "\n[", img, "]")
        println(io, "inputs = \"", sandbox_hash(img), "\"")
        println(io, "digest = \"", digests[img], "\"")
    end
    return String(take!(io))
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
The image is the one `project_env` belongs to; only the image and its memory
limit differ between courses, every other flag is the same for all of them.
"""
function docker_args(; project_env::String, threads::Int = 1, name::String, maxcpus::Int = threads + 1)
    img = env_image(project_env)
    mem = image_memory(img)
    return String["run", "--rm", "-i", "--name", name,
        "--network=none", "--read-only", "--cap-drop=ALL", "--security-opt=no-new-privileges",
        "--pids-limit=$CONTAINER_PIDS", "--memory=$mem", "--memory-swap=$mem",
        "--cpus=$(clamp(threads + 1, 1, max(maxcpus, 1)))", "--user", container_user(),
        "--tmpfs", "/tmp:rw,exec,size=512m,mode=1777",
        "-e", "HOME=/tmp", "-e", "JULIA_DEPOT_PATH=/tmp/depot:/depot", "-e", "JULIA_PKG_OFFLINE=true",
        "-e", "JULIA_PKG_PRECOMPILE_AUTO=0", "-e", "JULIA_NUM_THREADS=$threads", "-e", "OPENBLAS_NUM_THREADS=1",
        image_name(img), "julia", "--startup-file=no", "--history-file=no", "--threads=$threads",
        "--heap-size-hint=$(heap_hint(mem))",
        "--project=/tutor/envs/$project_env", "/tutor/child/contained.jl"]
end

"""
Largest memory peak seen per environment in this process: (bytes, source),
source "cgroup" (memory.peak) or "maxrss" (Julia's peak resident set, on
kernels without memory.peak), from the line contained.jl prints last.
`tutor course verify --sandbox=docker` and `tutor sandbox measure` print
them; nothing else reads them.
"""
const MEMORY_PEAKS = Dict{String,Tuple{Int,String}}()

"""Remove the memory-peak line from the container's output; returns (rest, (bytes, source) or nothing)."""
function split_peak(out::AbstractString)
    # only after the files block, which contained.jl prints after the code ran,
    # so a learner who prints the prefix does not lose the rest of their output
    e = findlast(FILES_END, out)
    e === nothing && return (String(out), nothing)
    i = findnext(PEAK_PREFIX, out, last(e))
    i === nothing && return (String(out), nothing)
    j = something(findnext('\n', out, last(i)), lastindex(out) + 1)
    m = match(r"^([0-9]+) (cgroup|maxrss)$", strip(out[nextind(out, last(i)):prevind(out, j)]))
    rest = String(out[1:prevind(out, first(i))])
    return (rest, m === nothing ? nothing : (parse(Int, m[1]), String(m[2])))
end

"""Keep the larger peak per environment."""
note_peak!(env, p) = (p === nothing || p[1] <= get(MEMORY_PEAKS, env, (0, ""))[1] || (MEMORY_PEAKS[env] = p); nothing)

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
    out, peak = split_peak(out)
    note_peak!(project_env, peak)
    log, outfiles = split_files(out)
    return (timed_out ? -1 : proc.exitcode, timed_out, log, outfiles)
end

end # module Runner
