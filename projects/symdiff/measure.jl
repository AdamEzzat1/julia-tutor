# Measurements for the symdiff project (run in a fresh process by `tutor explain`).
# Usage: julia --project=<pkgdir> measure.jl <out.toml>
#
# Measured, not guessed (invariant 8):
# * inferred return types of hole functions, from the compiler (Base.return_types);
# * allocation counts after a warm-up call (first-call compilation excluded),
#   single-threaded;
# * JET's optimisation report (runtime-dispatch count) for `evaluate`, if the
#   pinned JET loads. JET is tied to compiler internals: on failure we report
#   "unavailable" instead of guessing.

using SymDiff, TOML
using SymDiff: Bindings, mk_add, rewrite_budgeted!, Rule, Term, Mul, Sym, PVar, Fn

const OUT = ARGS[1]
results = Dict{String,Any}()

typestr(T) = replace(string(T), "SymDiff." => "")

# hole id => (function, argument types)
const INFERENCE_TARGETS = [
    ("product_rule", deriv, (Mul, Sym)),
    ("pvar_binding", match_pattern, (PVar, Term, Bindings)),
    ("size_measure", is_size_decreasing, (Rule,)),
    ("canonical_sum", mk_add, (Vector{Term},)),
    ("chain_rule", deriv, (Fn{typeof(sin)}, Sym)),
    ("rewrite_innermost", rewrite_budgeted!, (Base.RefValue{Int}, Term, Vector{Rule})),
]
inferred = Dict{String,Any}()
for (id, f, types) in INFERENCE_TARGETS
    rts = Base.return_types(f, types)
    inferred[id] = isempty(rts) ? "no method" : typestr(reduce(Union, rts))
end
results["inferred"] = inferred

# A fresh bench for every call: a student's aliasing bug (e.g. writing into
# `t.args` in product_rule) would otherwise corrupt a shared bench, and every
# later measurement would run on a different tree (observed in the explain test).
# The bench is built by the student's own `simplify`, so explain only compares
# allocations with the reference when `bench_nodecount` matches the baseline.
make_bench() = simplify(@term (x + 1) * (x + 2) * (x + 3) * sin(x^2) + exp(3x) * cos(x))

function measure_allocs(f)
    try
        f(make_bench())                       # warm-up: compile outside the measurement
        b = make_bench()
        return Base.@allocations f(b)
    catch err
        msg = sprint(showerror, err)
        m = match(r"TODO\(hole:([a-z0-9_]+)\)", msg)
        return m === nothing ? "error: " * first(split(msg, '\n')) : "hole not implemented: " * m[1]
    end
end

const BENCH = try make_bench() catch; nothing end   # nothing if simplify is still a hole
allocs = Dict{String,Any}()
allocs["derivative(bench)"] = measure_allocs(b -> derivative(b, :x))
allocs["simplify(bench)"] = measure_allocs(b -> simplify(b))
allocs["evaluate(bench, Float64)"] = measure_allocs(b -> evaluate(b, Dict(:x => 0.7)))
results["allocations"] = allocs
BENCH === nothing || (results["bench_nodecount"] = nodecount(BENCH))

jet = Dict{String,Any}()
try
    @eval using JET
    BENCH === nothing && error("bench could not be built (simplify raised)")
    rep = JET.report_opt(evaluate, (typeof(BENCH), Dict{Symbol,Float64}))
    jet["evaluate_runtime_dispatch_reports"] = length(JET.get_reports(rep))
    jet["status"] = "ok (JET $(pkgversion(JET)))"
catch err
    jet["status"] = "unavailable: " * first(split(sprint(showerror, err), '\n'))
end
results["jet"] = jet

open(OUT, "w") do io
    TOML.print(io, results; sorted = true)
end
