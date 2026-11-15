#=
QSim: a small, readable state-vector quantum simulator in plain Julia.

Only the standard library is used (LinearAlgebra, Random). Every function is
written to be read: the comments explain the physics and maths the code encodes.

Lines starting with `# HOLE:` mark functions the scaffolder can open. They are
the functions you write in the starter stages; their docstrings stay, so the
docstring is the specification.

------------------------------------------------------------------------------
 THE ONE CONVENTION YOU MUST KNOW: qubit ordering (little-endian, like Qiskit)
------------------------------------------------------------------------------
An n-qubit state is a vector of 2^n complex amplitudes. Each basis state is an
integer k written in binary, k = b_{n-1} ... b_1 b_0, and we decide that

        qubit q  <->  bit q of k      (qubit 0 = least significant bit)

So for 3 qubits, |q2 q1 q0> = |110> means qubit 1 and qubit 2 are 1: k = 6.
This is exactly Qiskit's convention, so bitstrings printed here read like
Qiskit's: the rightmost character is qubit 0.

Consequences (keep these in mind when reading textbooks, which usually use the
opposite, "big-endian" order):

  * Full operator for a gate U on qubit q:
        I ⊗ ... ⊗ U ⊗ ... ⊗ I   with U in slot (n-1-q) counting from the LEFT,
    i.e. kron(op_{n-1}, ..., op_1, op_0).
  * Julia stores arrays column-major (first index varies fastest). Reshaping
    ψ into an n-dimensional 2×2×...×2 array therefore gives A[b0+1, b1+1, ...]:
    dimension 1 is qubit 0. Little-endian and column-major fit together
    naturally, which makes partial traces simple (see `reduced_density`).
  * Julia indexes from 1, so the amplitude of basis state k lives at ψ[k+1].
=#
module QSim

using LinearAlgebra
using Random

export State, zero_state, basis_state, nqubits, normalize_state!,
       I2, X, Y, Z, H, S, Sdg, T, Tdg, SX, RX, RY, RZ, P, U3,
       CX, CZ, SWAP, CP,
       apply!, apply_controlled!, full_operator, full_operator_kron,
       Gate, Circuit, add!, run_circuit, gate_matrix, circuit_unitary,
       probabilities, sample_counts, measure!, bitstring_of,
       reduced_density, bloch_vector, density_matrix, apply_kraus,
       expectation, fidelity, equal_up_to_global_phase,
       parse_circuit, circuit_text, is_unitary,
       bell_pair!, ghz_circuit, qft!, iqft!, qft_circuit,
       grover_circuit, grover_iterations, bv_circuit, qpe_circuit

const C64 = ComplexF64

# -----------------------------------------------------------------------------
# 1. States
# -----------------------------------------------------------------------------

"""
A state vector is just a `Vector{ComplexF64}` of length 2^n. We do not wrap it
in a struct: keeping it a plain vector means every LinearAlgebra tool (`norm`,
`dot`, `kron`, `'` for the conjugate transpose) works on it directly.
"""
const State = Vector{C64}

"Number of qubits encoded by a state of length 2^n (errors if not a power of 2)."
function nqubits(ψ::AbstractVector)
    L = length(ψ)
    ispow2(L) || throw(ArgumentError("state length $L is not a power of 2"))
    return trailing_zeros(L)          # log2 of a power of two
end

"|0...0> on n qubits: amplitude 1 on basis state k = 0, zero elsewhere."
function zero_state(n::Integer)
    ψ = zeros(C64, 2^n)
    ψ[1] = 1                           # k = 0 lives at index 1 (Julia is 1-based)
    return ψ
end

# HOLE: basis_state
"""
    basis_state(n, k)

Computational basis state |k> for integer k (0 ≤ k < 2^n): amplitude 1 on basis
state k, zero elsewhere. Example: `basis_state(3, 0b110)` is |110> = qubits 1
and 2 set, qubit 0 clear. Throws `ArgumentError` if k is out of range.
"""
function basis_state(n::Integer, k::Integer)
    0 ≤ k < 2^n || throw(ArgumentError("basis index $k out of range for $n qubits"))
    ψ = zeros(C64, 2^n)
    ψ[k+1] = 1                         # basis state k lives at index k + 1
    return ψ
end

"Rescale to unit length. Physical states always satisfy <ψ|ψ> = 1 (Born rule)."
normalize_state!(ψ) = (ψ ./= norm(ψ); ψ)

# -----------------------------------------------------------------------------
# 2. Gate matrices
# -----------------------------------------------------------------------------
# Single-qubit gates are 2×2 unitaries written in the basis (|0>, |1>):
# column j is the image of basis state |j>. E.g. X maps |0>→|1> and |1>→|0>,
# so its columns are (0,1) and (1,0).

const I2  = C64[1 0; 0 1]
const X   = C64[0 1; 1 0]                       # bit flip (NOT)
const Y   = C64[0 -im; im 0]                    # bit + phase flip, Y = iXZ
const Z   = C64[1 0; 0 -1]                      # phase flip: |1> → -|1>
const H   = C64[1 1; 1 -1] / sqrt(2)            # |0>→|+>, |1>→|->
const S   = C64[1 0; 0 im]                      # √Z: quarter turn about z
const Sdg = C64[1 0; 0 -im]                     # S† (inverse of S)
const T   = C64[1 0; 0 cis(π/4)]                # √S: eighth turn about z
const Tdg = C64[1 0; 0 cis(-π/4)]
const SX  = C64[1+im 1-im; 1-im 1+im] / 2       # √X (Qiskit's `sx`)

# Rotations. The Pauli matrices generate rotations of the Bloch sphere:
#     R_a(θ) = exp(-i θ a/2) = cos(θ/2) I - i sin(θ/2) a     (a ∈ {X, Y, Z})
# The factor 1/2 is why a full 2π rotation gives -I (spinor double cover).
RX(θ) = C64[cos(θ/2) -im*sin(θ/2); -im*sin(θ/2) cos(θ/2)]

# HOLE: ry
"""
    RY(θ)

Rotation of the Bloch sphere by angle θ about the y axis:

    RY(θ) = exp(-i θ Y/2) = cos(θ/2) I - i sin(θ/2) Y

Applied to |0>, it gives cos(θ/2)|0> + sin(θ/2)|1>: the Bloch vector tips from
the north pole towards +x by θ. Its entries are real.
"""
function RY(θ)
    c, s = cos(θ / 2), sin(θ / 2)      # the half angle: RY(2π) = -I, not I
    return C64[c -s; s c]
end

RZ(θ) = C64[cis(-θ/2) 0; 0 cis(θ/2)]

# Phase gate P(λ) = diag(1, e^{iλ}). Differs from RZ(λ) only by the global phase
# e^{iλ/2}. Global phases are unobservable for a whole state, but they DO
# matter once the gate is controlled (CP vs CRZ), a classic exam trap.
P(λ) = C64[1 0; 0 cis(λ)]

# General single-qubit gate, Qiskit's U(θ, φ, λ) definition:
#     U = [ cos(θ/2)          -e^{iλ} sin(θ/2)
#           e^{iφ} sin(θ/2)    e^{i(φ+λ)} cos(θ/2) ]
# Every 2×2 unitary equals U(θ,φ,λ) up to a global phase.
U3(θ, φ, λ) = C64[cos(θ/2)          -cis(λ)*sin(θ/2);
                  cis(φ)*sin(θ/2)    cis(φ+λ)*cos(θ/2)]

# Two-qubit gates as 4×4 matrices. Local index convention (matches Qiskit):
# for a gate applied to qubits (a, b), the local basis index is  b_b b_a  in
# binary, i.e. the FIRST listed qubit is the least significant bit.
# For CX(control=a, target=b): local states |b a> = |00>,|01>,|10>,|11>
# (indices 0..3). The target flips when control a = 1, i.e. indices 1 ↔ 3.
const CX = C64[1 0 0 0;
               0 0 0 1;
               0 0 1 0;
               0 1 0 0]
const CZ   = Diagonal(C64[1, 1, 1, -1]) |> Matrix   # symmetric in its qubits
const SWAP = C64[1 0 0 0; 0 0 1 0; 0 1 0 0; 0 0 0 1]
CP(λ) = Diagonal(C64[1, 1, 1, cis(λ)]) |> Matrix     # controlled phase (symmetric)

"Check U†U = I to tolerance: the defining property of a quantum gate."
is_unitary(U; atol=1e-12) = isapprox(U' * U, I, atol=atol)

# -----------------------------------------------------------------------------
# 3. Applying gates: the FAST way (in place, never builds 2^n × 2^n matrices)
# -----------------------------------------------------------------------------

# HOLE: apply_gate
"""
    apply!(ψ, U, qubits)

Apply a k-qubit unitary `U` (2^k × 2^k) to the listed `qubits` of state ψ,
in place, and return ψ. `qubits[1]` is the least significant bit of U's local
index (Qiskit convention), so `apply!(ψ, CX, [c, t])` is CNOT with control c.
Throws `DimensionMismatch` if `U` has the wrong size and `ArgumentError` for a
repeated or out-of-range qubit.

How it works: the gate only mixes amplitudes whose indices agree on every
qubit *not* in `qubits`. So iterate over all settings of the other n-k bits
("spectator" bits); for each, gather the 2^k amplitudes it touches, multiply
by U, and scatter them back. Cost: O(2^n · 2^k), memory O(2^k).
"""
function apply!(ψ::AbstractVector, U::AbstractMatrix, qubits::AbstractVector{<:Integer})
    n = nqubits(ψ)
    k = length(qubits)
    size(U) == (2^k, 2^k) || throw(DimensionMismatch("gate is $(size(U)), expected $(2^k)×$(2^k)"))
    allunique(qubits)     || throw(ArgumentError("repeated qubit in $qubits"))
    all(q -> 0 ≤ q < n, qubits) || throw(ArgumentError("qubit out of range in $qubits for n=$n"))

    # offsets[j+1] = the bits that local index j sets in the global index.
    # Example: qubits = [2, 0] → local bit 0 ↦ global bit 2, local bit 1 ↦ bit 0.
    offsets = zeros(Int, 2^k)
    for j in 0:2^k-1, (pos, q) in enumerate(qubits)
        if (j >> (pos - 1)) & 1 == 1
            offsets[j+1] |= 1 << q
        end
    end
    mask = sum(1 << q for q in qubits)   # global bits owned by the gate

    buf = similar(ψ, 2^k)
    for base in 0:2^n-1
        base & mask == 0 || continue      # visit each spectator setting once
        for j in 1:2^k
            buf[j] = ψ[base + offsets[j] + 1]
        end
        out = U * buf
        for j in 1:2^k
            ψ[base + offsets[j] + 1] = out[j]
        end
    end
    return ψ
end

apply!(ψ::AbstractVector, U::AbstractMatrix, q::Integer) = apply!(ψ, U, [q])

# HOLE: apply_controlled
"""
    apply_controlled!(ψ, U, controls, targets)

Apply U to `targets` only on the branch where every control qubit is |1>, in
place, and return ψ. Mathematically: C-U = |0><0| ⊗ I + |1><1| ⊗ U
(generalised to many controls). Toffoli = `apply_controlled!(ψ, X, [c1, c2], [t])`.
Hint: build one matrix on the targets and the controls together and hand it
to `apply!`.
"""
function apply_controlled!(ψ::AbstractVector, U::AbstractMatrix,
                           controls::AbstractVector{<:Integer},
                           targets::AbstractVector{<:Integer})
    # Build the controlled matrix on (targets ∪ controls) with targets as the
    # low bits: it is identity everywhere except the block where all
    # control bits are 1, which is U.
    k_t, k_c = length(targets), length(controls)
    d = 2^(k_t + k_c)
    CU = Matrix{C64}(I, d, d)
    lo = (2^k_c - 1) * 2^k_t            # first local index with all controls = 1
    CU[lo+1:lo+2^k_t, lo+1:lo+2^k_t] = U
    return apply!(ψ, CU, vcat(targets, controls))
end

# -----------------------------------------------------------------------------
# 4. Applying gates: the OBVIOUS way (full matrices). Used as a reference.
# -----------------------------------------------------------------------------
# Two independent constructions of the 2^n × 2^n operator. The test suite
# checks that fast `apply!`, `full_operator` and `full_operator_kron` all agree.
# If they disagreed, at least one of them would have to be wrong.

# HOLE: kron_operator
"""
    full_operator_kron(U, q, n)

Textbook construction for a SINGLE-qubit gate on qubit q of n:
I ⊗ ... ⊗ U ⊗ ... ⊗ I, as a 2^n × 2^n matrix. In little-endian order the
leftmost kron factor is qubit n-1, so U sits in slot n-1-q from the left.
Throws `ArgumentError` if U is not 2×2.
"""
function full_operator_kron(U::AbstractMatrix, q::Integer, n::Integer)
    size(U) == (2, 2) || throw(ArgumentError("kron path is for single-qubit gates"))
    ops = [i == q ? U : I2 for i in n-1:-1:0]   # ops[1] is qubit n-1
    return reduce(kron, ops)
end

"""
    full_operator(U, qubits, n)

Build the 2^n × 2^n operator *straight from the definition*:

    <out| O |in> = U[local(out), local(in)]  if out and in agree on all
                                             spectator qubits, else 0.

This shares no code with `apply!`, which is why it makes a good cross-check.
"""
function full_operator(U::AbstractMatrix, qubits::AbstractVector{<:Integer}, n::Integer)
    local_index(k) = sum(((k >> q) & 1) << (pos - 1) for (pos, q) in enumerate(qubits); init=0)
    mask = sum(1 << q for q in qubits)
    O = zeros(C64, 2^n, 2^n)
    for kin in 0:2^n-1, kout in 0:2^n-1
        if (kin & ~mask) == (kout & ~mask)      # spectators untouched
            O[kout+1, kin+1] = U[local_index(kout)+1, local_index(kin)+1]
        end
    end
    return O
end

# -----------------------------------------------------------------------------
# 5. Circuits: a list of gates, plus a tiny text format shared with Qiskit
# -----------------------------------------------------------------------------

"One instruction: gate name, the qubits it acts on, and its real parameters."
struct Gate
    name::Symbol
    qubits::Vector{Int}
    params::Vector{Float64}
end
Gate(name::Symbol, qubits::Vector{Int}) = Gate(name, qubits, Float64[])

"A circuit is an ordered list of gates on a fixed number of qubits."
mutable struct Circuit
    n::Int
    gates::Vector{Gate}
end
Circuit(n::Integer) = Circuit(n, Gate[])

"Append a gate: `add!(c, :cx, 0, 1)` or `add!(c, :rz, 2; θ=0.3)`."
function add!(c::Circuit, name::Symbol, qubits::Integer...; params...)
    push!(c.gates, Gate(name, collect(Int, qubits), Float64[values(params)...]))
    return c
end

"""
Map a gate name (same names as Qiskit's methods) to its matrix, in the order
of `g.qubits`. For controlled gates the control comes first in `g.qubits`,
again matching Qiskit (`qc.cx(control, target)`).
"""
function gate_matrix(g::Gate)
    p = g.params
    fixed = Dict(:id => I2, :x => X, :y => Y, :z => Z, :h => H, :s => S,
                 :sdg => Sdg, :t => T, :tdg => Tdg, :sx => SX,
                 :cx => CX, :cz => CZ, :swap => SWAP)
    haskey(fixed, g.name) && return fixed[g.name]
    g.name === :rx && return RX(p[1])
    g.name === :ry && return RY(p[1])
    g.name === :rz && return RZ(p[1])
    g.name === :p  && return P(p[1])
    g.name === :u  && return U3(p[1], p[2], p[3])
    g.name === :cp && return CP(p[1])
    # Multi-controlled Z on k qubits: diag(1, ..., 1, -1). It flips the sign of
    # |11...1> only, and is symmetric: there is no real "target" qubit.
    g.name === :mcz && return begin
        d = 2^length(g.qubits)
        M = Matrix{C64}(I, d, d); M[d, d] = -1; M
    end
    g.name === :ccx && return begin            # Toffoli on (c1, c2, target)
        M = Matrix{C64}(I, 8, 8)
        # local index bits: c1 = bit0, c2 = bit1, target = bit2.
        # flip target when c1 = c2 = 1: local 3 (011) ↔ 7 (111)
        M[4, 4] = M[8, 8] = 0; M[4, 8] = M[8, 4] = 1
        M
    end
    throw(ArgumentError("unknown gate $(g.name)"))
end

"Run a circuit from |0...0> (or from a given initial state)."
function run_circuit(c::Circuit, ψ0::AbstractVector=zero_state(c.n))
    ψ = State(copy(ψ0))
    nqubits(ψ) == c.n || throw(DimensionMismatch("state has $(nqubits(ψ)) qubits, circuit has $(c.n)"))
    for g in c.gates
        apply!(ψ, gate_matrix(g), g.qubits)
    end
    return ψ
end

"""
The whole circuit as one 2^n × 2^n unitary, built by running it on every basis
state: column k of the unitary is the circuit applied to |k>.
"""
circuit_unitary(c::Circuit) = reduce(hcat, (run_circuit(c, basis_state(c.n, k)) for k in 0:2^c.n-1))

"""
    parse_circuit(text)

Read the plain-text circuit format used for differential testing with Qiskit:

    n 3
    h 0
    cx 0 1
    rz 2 0.7853981633974483        # qubits first, then parameters
    u 1 0.1 0.2 0.3

Gate arity is fixed by name, so the parser knows where qubits stop.
"""
function parse_circuit(text::AbstractString)
    arity = Dict(:cx => 2, :cz => 2, :swap => 2, :cp => 2, :ccx => 3)
    c = nothing
    for raw in split(text, '\n')
        line = strip(first(split(raw, '#')))
        isempty(line) && continue
        tok = split(line)
        if tok[1] == "n"
            c = Circuit(parse(Int, tok[2])); continue
        end
        name = Symbol(tok[1])
        if name === :mcz                       # variable arity: "mcz k q1 ... qk"
            k = parse(Int, tok[2])
            push!(c.gates, Gate(name, parse.(Int, tok[3:2+k]), Float64[]))
            continue
        end
        k = get(arity, name, 1)
        qs = parse.(Int, tok[2:1+k])
        ps = parse.(Float64, tok[2+k:end])
        push!(c.gates, Gate(name, qs, ps))
    end
    return c
end

"""
Write a circuit in the same text format. Floats are printed with `repr`,
which in Julia is the shortest string that parses back to the identical
Float64, so nothing is lost in the round trip to Python.
"""
function circuit_text(c::Circuit)
    io = IOBuffer()
    println(io, "n ", c.n)
    for g in c.gates
        qs = join(g.qubits, ' ')
        g.name === :mcz && (qs = "$(length(g.qubits)) " * qs)
        ps = isempty(g.params) ? "" : " " * join(repr.(g.params), ' ')
        println(io, g.name, ' ', qs, ps)
    end
    return String(take!(io))
end

# -----------------------------------------------------------------------------
# 6. Measurement (Born rule)
# -----------------------------------------------------------------------------

"Probability of each basis outcome: P(k) = |<k|ψ>|² = |ψ[k+1]|²."
probabilities(ψ::AbstractVector) = abs2.(ψ)

# HOLE: bitstring
"""
    bitstring_of(k, n)

The n-character bitstring of basis index k, qubit n-1 on the LEFT and qubit 0
on the right (Qiskit's display order): `bitstring_of(6, 3) == "110"`,
`bitstring_of(1, 4) == "0001"`.
"""
function bitstring_of(k::Integer, n::Integer)
    return join(((k >> q) & 1 for q in n-1:-1:0))   # most significant qubit first
end

# HOLE: sample_counts
"""
    sample_counts(ψ, shots; rng)

Simulate `shots` measurements of all qubits and return a `Dict` from bitstring
(as `bitstring_of` writes it) to count. Each shot draws k with probability
|ψ_k|² by inverse-CDF sampling: pick u ~ Uniform(0,1) and return the first k
whose cumulative probability exceeds u. A seeded `rng` makes the counts
reproducible.
"""
function sample_counts(ψ::AbstractVector, shots::Integer; rng::AbstractRNG=Random.default_rng())
    n = nqubits(ψ)
    cdf = cumsum(probabilities(ψ))
    cdf ./= cdf[end]                        # guard against rounding drift
    counts = Dict{String,Int}()
    for _ in 1:shots
        k = searchsortedfirst(cdf, rand(rng)) - 1
        key = bitstring_of(k, n)
        counts[key] = get(counts, key, 0) + 1
    end
    return counts
end

# HOLE: measure_qubit
"""
    measure!(ψ, q; rng) -> outcome::Int

Projective measurement of ONE qubit, with collapse:
  P(1) = Σ_{k with bit q = 1} |ψ_k|².
Draw the outcome (1 with probability P(1)), zero every amplitude inconsistent
with it, renormalise ψ in place, and return the outcome. This is what makes
mid-circuit measurement (e.g. teleportation) work.
"""
function measure!(ψ::AbstractVector, q::Integer; rng::AbstractRNG=Random.default_rng())
    p1 = sum(abs2(ψ[k+1]) for k in 0:length(ψ)-1 if (k >> q) & 1 == 1; init=0.0)
    outcome = rand(rng) < p1 ? 1 : 0
    for k in 0:length(ψ)-1
        if (k >> q) & 1 != outcome
            ψ[k+1] = 0
        end
    end
    normalize_state!(ψ)
    return outcome
end

# -----------------------------------------------------------------------------
# 7. Density matrices, partial trace, Bloch sphere, noise
# -----------------------------------------------------------------------------

"ρ = |ψ><ψ| for a pure state. Mixed states are convex sums of these."
density_matrix(ψ::AbstractVector) = ψ * ψ'

# HOLE: partial_trace
"""
    reduced_density(ψ, keep)

Reduced density matrix (2^|keep| × 2^|keep|) of the qubits in `keep`
(keep[1] = least significant), obtained by tracing out all the others.

Trick: reshape ψ to a 2×2×...×2 tensor (dimension d ↔ qubit d-1, thanks to
column-major + little-endian), permute so the kept qubits come first, then
flatten to a matrix M of size 2^|keep| × 2^(rest). Then ρ_keep = M M†,
because summing over the traced-out index is exactly the matrix product.
"""
function reduced_density(ψ::AbstractVector, keep::AbstractVector{<:Integer})
    n = nqubits(ψ)
    rest = [q for q in 0:n-1 if q ∉ keep]
    A = reshape(ψ, ntuple(_ -> 2, n))
    A = permutedims(A, vcat(keep, rest) .+ 1)
    # n is only known at run time, so inference cannot know A's number of
    # dimensions; the assertion restores what is always true (permutedims
    # returns an Array, reshaped to 2-D it is a Matrix) and keeps the result
    # type-stable (measured: `tutor baseline qsim`, inferred.partial_trace).
    M = reshape(A, 2^length(keep), :)::Matrix{eltype(ψ)}
    return M * M'                       # ' is the conjugate transpose
end
reduced_density(ψ::AbstractVector, q::Integer) = reduced_density(ψ, [q])

# HOLE: bloch
"""
    bloch_vector(ρ)
    bloch_vector(ψ, q)

Bloch vector r = (<X>, <Y>, <Z>) of a single-qubit density matrix, a real
3-vector, using ρ = (I + r·σ)/2. |r| = 1 for a pure qubit; |r| < 1 means the
qubit is mixed, e.g. because it is entangled with others (|r| = 0 for half a
Bell pair). The second form is the Bloch vector of qubit q of state ψ.
"""
function bloch_vector(ρ::AbstractMatrix)
    return real.([tr(ρ * X), tr(ρ * Y), tr(ρ * Z)])   # <σ> = tr(ρσ)
end
bloch_vector(ψ::AbstractVector, q::Integer) = bloch_vector(reduced_density(ψ, q))

"<ψ|O|ψ> for an operator on the full register (real for Hermitian O)."
expectation(ψ::AbstractVector, O::AbstractMatrix) = real(dot(ψ, O * ψ))

# HOLE: kraus
"""
    apply_kraus(ρ, kraus, q)

Apply a single-qubit noise channel, given by its Kraus operators (2×2
matrices), to qubit q of an n-qubit density matrix, and return the new ρ:
    ρ ↦ Σ_i K_i ρ K_i†,   with Σ_i K_i† K_i = I (trace preservation).
Throws `ArgumentError` if the Kraus operators are not trace preserving.
"""
function apply_kraus(ρ::AbstractMatrix, kraus::AbstractVector, q::Integer)
    n = nqubits(view(ρ, :, 1))
    isapprox(sum(K' * K for K in kraus), I2, atol=1e-12) ||
        throw(ArgumentError("Kraus operators are not trace preserving"))
    out = zeros(C64, size(ρ))
    for K in kraus
        Kf = full_operator(K, [q], n)
        out .+= Kf * ρ * Kf'
    end
    return out
end

"Fidelity between pure states, |<ψ|φ>|² (1 = identical up to global phase)."
fidelity(ψ::AbstractVector, φ::AbstractVector) = abs2(dot(ψ, φ))

"""
True if ψ = e^{iα} φ for some real α. Global phase is unobservable, so this is
the right notion of 'same state'. We fix α using the largest amplitude of φ.
"""
function equal_up_to_global_phase(ψ, φ; atol=1e-10)
    j = argmax(abs.(φ))
    abs(φ[j]) < atol && return norm(ψ) < atol
    phase = ψ[j] / φ[j]
    isapprox(abs(phase), 1, atol=atol) || return false
    return isapprox(ψ, phase * φ, atol=atol)
end

include("Algorithms.jl")

end # module
