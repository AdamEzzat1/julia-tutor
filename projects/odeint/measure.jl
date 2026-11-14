# Measurements for the odeint project (run in a fresh process by `tutor explain`).
# Usage: julia --project=<pkgdir> measure.jl <out.toml> [--jet]
#
# Measured, not guessed (invariant 8):
# * inferred return types of the hole functions at the argument types the
#   solvers call them with (Base.return_types);
# * allocation counts of one call after a warm-up call (first-call
#   compilation excluded), single-threaded. The kernels (a step, the error
#   norm, a Verlet step) are specified to allocate nothing.
# The benchmark inputs are fixed here, not built by the student's code, so
# the student's numbers are always comparable with the reference's: the
# bench is the same, which `bench_nodecount` is not needed to establish.
# JET is not used by this project's measurements (`--jet` is accepted and
# ignored), so the report says so instead of running it.

using ODEInt, TOML

const OUT = ARGS[1]
results = Dict{String,Any}()

const F = typeof(kepler_rhs!)
const A = typeof(kepler_accel!)
const V = Vector{Float64}
const INFERENCE_TARGETS = [
    ("dp54_step", dp54_step!, (DP54Cache, F, Float64, V, Float64)),
    ("error_norm", error_norm, (V, V, V, Float64, Float64)),
    ("kepler_exact", kepler_exact, (Float64, Float64)),
    ("verlet_step", verlet_step!, (V, V, V, Float64, A)),
    ("propose_step", propose_step, (Float64, Float64)),
    ("initial_step", initial_step, (F, Float64, V, V, Float64, Float64)),
    ("solve_adaptive", solve_adaptive, (F, V, Tuple{Float64,Float64})),
    ("fit_order", fit_order, (V, V)),
]
inferred = Dict{String,Any}()
for (id, f, types) in INFERENCE_TARGETS
    rts = Base.return_types(f, types)
    inferred[id] = isempty(rts) ? "no method" : replace(string(reduce(Union, rts)), "ODEInt." => "")
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

const U0 = kepler_initial(0.5)
const CACHE = let c = DP54Cache(4); kepler_rhs!(c.k1, U0, 0.0); c end
const Q, P, ACC = U0[1:2], U0[3:4], zeros(2)
kepler_accel!(ACC, Q)

allocs = Dict{String,Any}()
allocs["dp54_step!(kepler, h = 0.01)"] = measure_allocs(() -> dp54_step!(CACHE, kepler_rhs!, 0.0, U0, 0.01))
allocs["error_norm(4 components)"] = measure_allocs(() -> error_norm(CACHE.err, U0, CACHE.ynew, 1e-6, 1e-6))
allocs["verlet_step!(kepler, h = 0.01)"] = measure_allocs(() -> verlet_step!(Q, P, ACC, 0.01, kepler_accel!))
allocs["solve_adaptive(kepler, one period, tol 1e-8)"] =
    measure_allocs(() -> solve_adaptive(kepler_rhs!, U0, (0.0, 2pi); rtol = 1e-8, atol = 1e-8))
results["allocations"] = allocs
results["jet"] = Dict{String,Any}("status" => "not used by this project's measurements")

open(OUT, "w") do io
    TOML.print(io, results; sorted = true)
end
