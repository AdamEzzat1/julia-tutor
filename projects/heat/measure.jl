# Measurements for the heat project (run in a fresh process by `tutor explain`).
# Usage: julia --project=<pkgdir> measure.jl <out.toml> [--jet]
#
# Measured, not guessed (invariant 8):
# * inferred return types of the hole functions at the argument types the
#   solver calls them with (Base.return_types);
# * allocation counts of one call after a warm-up call (first-call
#   compilation excluded), single-threaded. The kernels (the second
#   difference, a step, the tridiagonal solve) work in place and are
#   specified to allocate nothing; solve_heat allocates its grid, two
#   solution vectors and the work arrays.
# The benchmark inputs are fixed here, not built by the student's code.
# JET is not used by this project's measurements (`--jet` is accepted and
# ignored), so the report says so instead of running it.

using Heat1D, TOML

const OUT = ARGS[1]
results = Dict{String,Any}()

const P, _EX = mms_problem(1.0)
const PT = typeof(P)
const V = Vector{Float64}
const INFERENCE_TARGETS = [
    ("second_difference", second_difference!, (V, V, Float64, Float64, Float64)),
    ("ftcs_step", ftcs_step!, (V, V, PT, Float64, Float64, Float64, V)),
    ("thomas", thomas!, (V, V, V, V, V)),
    # mms_problem is not listed: its return type names compiler-generated
    # closure types (var"#12#17"...), which differ for any correct code.
    ("theta_step", theta_step!, (V, V, PT, Float64, Float64, Float64, Float64, ThetaWork)),
    ("solve_heat", solve_heat, (PT, Int, Int, Float64)),
    ("fit_order", fit_order, (V, V)),
]
inferred = Dict{String,Any}()
for (id, f, types) in INFERENCE_TARGETS
    rts = Base.return_types(f, types)
    inferred[id] = isempty(rts) ? "no method" : replace(string(reduce(Union, rts)), "Heat1D." => "")
end
results["inferred"] = inferred

function measure_allocs(f)
    try
        f()                                   # warm-up: compile outside the measurement
        return Base.@allocations f()
    catch err
        msg = sprint(showerror, err)
        m = match(r"TODO\(hole:([a-z0-9_]+)\)", msg)
        return m === nothing ? "error: " * first(split(msg, '\n')) : "hole not implemented: " * m[1]
    end
end

const N = 63
const DX = 1 / (N + 1)
const X = grid(N)
const U = P.u0.(X)
const UNEW = zeros(N)
const D2 = zeros(N)
const W = ThetaWork(N)
const A, B, C, D = fill(-1.0, N), fill(4.0, N), fill(-1.0, N), ones(N)
const C0, D0 = copy(C), copy(D)          # thomas! overwrites c and d: restored from these, without allocating

allocs = Dict{String,Any}()
allocs["second_difference!(63 points)"] = measure_allocs(() -> second_difference!(D2, U, 0.0, 1.0, DX))
allocs["ftcs_step!(63 points)"] = measure_allocs(() -> ftcs_step!(UNEW, U, P, 0.1, 1e-4, DX, D2))
allocs["thomas!(63 unknowns)"] = measure_allocs(() -> thomas!(UNEW, A, B, copyto!(C, C0), copyto!(D, D0)))
allocs["theta_step!(63 points, Crank-Nicolson)"] = measure_allocs(() -> theta_step!(UNEW, U, P, 0.1, 1e-3, DX, 0.5, W))
allocs["solve_heat(63 points, 100 CN steps)"] = measure_allocs(() -> solve_heat(P, N, 100, 0.1))
results["allocations"] = allocs
results["jet"] = Dict{String,Any}("status" => "not used by this project's measurements")

open(OUT, "w") do io
    TOML.print(io, results; sorted = true)
end
