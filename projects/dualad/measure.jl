# Measurements for the dualad project (run in a fresh process by `tutor explain`).
# Usage: julia --project=<pkgdir> measure.jl <out.toml> [--jet]
#
# Measured, not guessed (invariant 8):
# * inferred return types of the hole functions at Float64 duals
#   (Base.return_types): a dual operation that infers `Any` or a Union
#   makes every derivative slow;
# * allocation counts of one call after a warm-up call (first-call
#   compilation excluded), single-threaded. `Dual{Float64}` is an
#   immutable isbits struct, so the arithmetic and `derivative` allocate
#   nothing; `gradient` allocates its seeded vectors and the result.
# The benchmark inputs are fixed here, not built by the student's code.
# JET is not used by this project's measurements (`--jet` is accepted and
# ignored), so the report says so instead of running it.

using DualAD, TOML

const OUT = ARGS[1]
results = Dict{String,Any}()

const D = Dual{Float64}
f(x) = exp(x) * sin(x)
g(x) = x[1] * x[2] + sin(x[3])
const INFERENCE_TARGETS = [
    ("mul", *, (D, D)),
    ("div", /, (D, D)),
    ("chain", lift, (typeof(sin), typeof(cos), D)),
    ("power", ^, (D, Int)),
    ("derivative", derivative, (typeof(f), Float64)),
    ("gradient", gradient, (typeof(g), Vector{Float64})),
    ("central_diff", central_diff, (typeof(f), Float64, Float64)),
    ("fit_order", fit_order, (Vector{Float64}, Vector{Float64})),
]
inferred = Dict{String,Any}()
for (id, fn, types) in INFERENCE_TARGETS
    rts = Base.return_types(fn, types)
    inferred[id] = isempty(rts) ? "no method" : replace(string(reduce(Union, rts)), "DualAD." => "")
end
results["inferred"] = inferred

function measure_allocs(fn)
    try
        fn()                                  # warm-up: compile outside the measurement
        return Base.@allocations fn()
    catch err
        msg = sprint(showerror, err)
        m = match(r"TODO\(hole:([a-z0-9_]+)\)", msg)
        return m === nothing ? "error: " * first(split(msg, '\n')) : "hole not implemented: " * m[1]
    end
end

const A, B = Dual(0.7, 1.0), Dual(1.3, 0.5)
const X3 = [0.1, 0.2, 0.3]
allocs = Dict{String,Any}()
allocs["a * b (Float64 duals)"] = measure_allocs(() -> A * B)
allocs["a / b (Float64 duals)"] = measure_allocs(() -> A / B)
allocs["derivative(exp(x) sin(x), 0.7)"] = measure_allocs(() -> derivative(f, 0.7))
allocs["gradient(3 variables)"] = measure_allocs(() -> gradient(g, X3))
allocs["central_diff(exp(x) sin(x), 0.7, 1e-5)"] = measure_allocs(() -> central_diff(f, 0.7, 1e-5))
results["allocations"] = allocs
results["jet"] = Dict{String,Any}("status" => "not used by this project's measurements")

open(OUT, "w") do io
    TOML.print(io, results; sorted = true)
end
