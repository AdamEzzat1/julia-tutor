# Measurements for the robertson project (run in a fresh process by `tutor explain`).
# Usage: julia --project=<pkgdir> measure.jl <out.toml> [--jet]
#
# Measured, not guessed (invariant 8):
# * inferred return types of the hole functions at the argument types the
#   integrators call them with (Base.return_types);
# * allocation counts of one call after a warm-up call (first-call
#   compilation excluded), single-threaded. The functions return fresh
#   vectors (three components: clarity over in-place kernels), so the
#   counts are not zero; they are compared with the reference's.
# The benchmark inputs are fixed here, not built by the student's code.
# JET is not used by this project's measurements (`--jet` is accepted and
# ignored), so the report says so instead of running it.

using StiffKin, TOML

const OUT = ARGS[1]
results = Dict{String,Any}()

const P = ROBERTSON
const Y = [0.7, 3e-5, 0.3]
const V = Vector{Float64}
const M = Matrix{Float64}
f(y) = rhs(y, P)
jac(y) = jacobian(y, P)
bs(y, h) = bs32_step(f, y, h)
ro(y, h) = ros2_step(f, jac, y, h)

const INFERENCE_TARGETS = [
    ("rhs", rhs, (V, Kinetics)),
    ("jacobian", jacobian, (V, Kinetics)),
    ("solve_pivot", solve_pivot, (M, V)),
    ("bs32_step", bs32_step, (typeof(f), V, Float64)),
    ("ros2_step", ros2_step, (typeof(f), typeof(jac), V, Float64)),
    ("fit_order", fit_order, (V, V)),
]
inferred = Dict{String,Any}()
for (id, fn, types) in INFERENCE_TARGETS
    rts = Base.return_types(fn, types)
    inferred[id] = isempty(rts) ? "no method" : replace(string(reduce(Union, rts)), "StiffKin." => "")
end
results["inferred"] = inferred

function measure_allocs(g)
    try
        g()                                   # warm-up: compile outside the measurement
        return Base.@allocations g()
    catch err
        msg = sprint(showerror, err)
        m = match(r"TODO\(hole:([a-z0-9_]+)\)", msg)
        return m === nothing ? "error: " * first(split(msg, '\n')) : "hole not implemented: " * m[1]
    end
end

const A = [2.0 -1.0 0.5; 4.0 1.0 -1.0; -1.0 3.0 2.0]
const B = [1.0, 2.0, 3.0]

allocs = Dict{String,Any}()
allocs["rhs(3 species)"] = measure_allocs(() -> rhs(Y, P))
allocs["jacobian(3 species)"] = measure_allocs(() -> jacobian(Y, P))
allocs["solve_pivot(3x3)"] = measure_allocs(() -> solve_pivot(A, B))
allocs["bs32_step(Robertson)"] = measure_allocs(() -> bs32_step(f, Y, 1e-4))
allocs["ros2_step(Robertson)"] = measure_allocs(() -> ros2_step(f, jac, Y, 1e-2))
results["allocations"] = allocs
results["jet"] = Dict{String,Any}("status" => "not used by this project's measurements")

open(OUT, "w") do io
    TOML.print(io, results; sorted = true)
end
