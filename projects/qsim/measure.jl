# Measurements for the qsim project (run in a fresh process by `tutor explain`).
# Usage: julia --project=<pkgdir> measure.jl <out.toml> [--jet]
#
# Measured, not guessed (invariant 8):
# * inferred return types of the hole functions at the argument types the
#   simulator and the circuit builders call them with (Base.return_types);
# * allocation counts of one call after a warm-up call (first-call
#   compilation excluded), single-threaded. Unlike odeint's kernels, apply!
#   is not specified to allocate nothing (it builds an offset table and a
#   small buffer per call), so the counts are recorded, not required to be 0:
#   the report puts the student's count next to the reference's.
# The benchmark inputs are fixed here, not built by the student's code, so
# the student's numbers are always comparable with the reference's.
# JET is not used by this project's measurements (`--jet` is accepted and
# ignored), so the report says so instead of running it.

using QSim, TOML, LinearAlgebra

const OUT = ARGS[1]
results = Dict{String,Any}()

const V = Vector{ComplexF64}
const M = Matrix{ComplexF64}
const IV = Vector{Int}
const INFERENCE_TARGETS = [
    ("basis_state", basis_state, (Int, Int)),
    ("bitstring", bitstring_of, (Int, Int)),
    ("kron_operator", full_operator_kron, (M, Int, Int)),
    ("ry", RY, (Float64,)),
    ("apply_gate", apply!, (V, M, IV)),
    ("apply_controlled", apply_controlled!, (V, M, IV, IV)),
    ("partial_trace", reduced_density, (V, IV)),
    ("bloch", bloch_vector, (M,)),
    ("sample_counts", sample_counts, (V, Int)),
    ("measure_qubit", measure!, (V, Int)),
    ("kraus", apply_kraus, (M, Vector{M}, Int)),
    ("grover", grover_circuit, (Int, IV, Int)),
    ("qft", qft!, (Circuit, IV)),
    ("iqft", iqft!, (Circuit, IV)),
    ("qpe", qpe_circuit, (Int, Float64)),
]
inferred = Dict{String,Any}()
for (id, f, types) in INFERENCE_TARGETS
    rts = Base.return_types(f, types)
    inferred[id] = isempty(rts) ? "no method" : replace(string(reduce(Union, rts)), "QSim." => "")
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

# A fixed 10-qubit state (normalised, every amplitude nonzero) and fixed gates.
const N = 10
const PSI = let v = ComplexF64[cis(0.1k) * (1 + k % 7) for k in 0:2^N-1]; v / norm(v) end
const CXM = ComplexF64[1 0 0 0; 0 0 0 1; 0 0 1 0; 0 1 0 0]
const QFT8 = qft_circuit(8)

allocs = Dict{String,Any}()
allocs["apply!(H, qubit 3 of 10)"] = measure_allocs(() -> apply!(copy(PSI), Matrix{ComplexF64}(H), [3]))
allocs["apply!(CX, qubits [7, 2] of 10)"] = measure_allocs(() -> apply!(copy(PSI), CXM, [7, 2]))
allocs["apply_controlled!(X, controls [0, 5], target [9], 10 qubits)"] =
    measure_allocs(() -> apply_controlled!(copy(PSI), Matrix{ComplexF64}(X), [0, 5], [9]))
allocs["run_circuit(qft_circuit(8))"] = measure_allocs(() -> run_circuit(QFT8))
results["allocations"] = allocs
results["jet"] = Dict{String,Any}("status" => "not used by this project's measurements")

open(OUT, "w") do io
    TOML.print(io, results; sorted = true)
end
