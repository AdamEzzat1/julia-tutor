# Behavioural specification of QSim.
#
# Two kinds of test, both from the original simulator (projects/qsim/README.md):
#
# * unit and property tests. The central idea is REDUNDANCY: gate application is
#   implemented three ways that share no code (fast in-place `apply!`, the
#   element-by-element `full_operator`, the textbook `full_operator_kron`), and
#   thousands of random cases must agree. A bug would have to be made
#   identically in independent code paths to slip through.
# * the lesson checks: each lesson computes something and compares it with what
#   theory says it must be (a closed form, a bound, an independent method).
#   They were the lesson scripts' `check` calls; here each is a `@test`, so the
#   test-to-hole map and the mutants see them.
#
# Randomness is always seeded (MersenneTwister), so every run draws the same
# cases. Statistical tests state their tolerance: 5 standard errors, so a
# correct implementation fails with probability ~1e-6 for a fresh seed (and
# never for these fixed seeds, which were run).

using Test
using QSim
using LinearAlgebra, Random

"Haar-ish random unitary: QR of a complex Gaussian matrix, phases fixed."
function rand_unitary(rng, d)
    Q, R = qr(randn(rng, ComplexF64, d, d))
    return Matrix(Q) * Diagonal(sign.(diag(R)))
end
rand_state(rng, n) = normalize_state!(randn(rng, ComplexF64, 2^n))

# ---- helpers of the lesson checks ---------------------------------------------

"von Neumann entropy S(ρ) = -Σ λ log₂ λ over the eigenvalues of ρ (in bits)."
entropy(ρ) = -sum(λ * log2(λ) for λ in eigvals(Hermitian(ρ)) if λ > 1e-12; init=0.0)

"The four Bell states, built from |Φ+> by local Paulis: X gives Ψ, Z the minus sign."
function bell(kind)
    c = Circuit(2)
    kind in (:Ψp, :Ψm) && add!(c, :x, 1)       # prepare a |01>-type input first
    kind in (:Φm, :Ψm) && add!(c, :x, 0)       # |1> on the H qubit → minus sign
    bell_pair!(c, 0, 1)
    return run_circuit(c)
end

"Measurement along angle θ in the x-z plane: A(θ) = cos θ Z + sin θ X (eigenvalues ±1)."
tilted(θ) = cos(θ) * Z + sin(θ) * X
"Joint correlator: qubit 1 gets b, qubit 0 gets a, so kron(B, A) (little-endian!)."
correlator(ψ, a, b) = expectation(ψ, kron(tilted(b), tilted(a)))

"Estimate a correlator the way an experiment does: rotate by RY(-θ), measure Z, E = P(same) - P(different)."
function sampled_correlator(a, b, shots, rng)
    c = Circuit(2); bell_pair!(c, 0, 1)
    add!(c, :ry, 0; θ = -a); add!(c, :ry, 1; θ = -b)
    cnt = sample_counts(run_circuit(c), shots; rng = rng)
    same = get(cnt, "00", 0) + get(cnt, "11", 0)
    return (2same - shots) / shots
end

"Random angles for U(θ,φ,λ)|0>: an arbitrary single-qubit message."
random_angles(rng) = (π * rand(rng), 2π * rand(rng), 2π * rand(rng))

"Teleport U(angles)|0> from qubit 0 to qubit 2 with mid-circuit measurement."
function teleport_once(angles, rng; correct=true)
    c = Circuit(3)
    add!(c, :u, 0; θ = angles[1], φ = angles[2], λ = angles[3])   # the message
    bell_pair!(c, 1, 2)                                            # shared pair
    add!(c, :cx, 0, 1); add!(c, :h, 0)                             # Alice's step 1
    ψ = run_circuit(c)
    m0 = measure!(ψ, 0; rng = rng)                                 # step 2
    m1 = measure!(ψ, 1; rng = rng)
    if correct                                                     # step 3
        m1 == 1 && apply!(ψ, X, 2)
        m0 == 1 && apply!(ψ, Z, 2)
    end
    return ψ, (m0, m1)
end

"Deferred measurement: X^{m1} becomes CX(1→2), Z^{m0} becomes CZ(0,2)."
function teleport_deferred(ang)
    c = Circuit(3)
    add!(c, :u, 0; θ = ang[1], φ = ang[2], λ = ang[3])
    bell_pair!(c, 1, 2)
    add!(c, :cx, 0, 1); add!(c, :h, 0)
    add!(c, :cx, 1, 2); add!(c, :cz, 0, 2)
    return c
end

"Run H^n · O_f · H^n on |0...0>, with the phase oracle given by its truth table f[x+1] ∈ {0,1}."
function hadamard_sandwich(f::AbstractVector{<:Integer})
    n = trailing_zeros(length(f))
    ψ = zero_state(n)
    for q in 0:n-1; apply!(ψ, H, q); end
    oracle = Matrix(Diagonal(ComplexF64[(-1)^fx for fx in f]))
    apply!(ψ, oracle, collect(0:n-1))          # the oracle acts on all n qubits
    for q in 0:n-1; apply!(ψ, H, q); end
    return ψ
end

"Closed-form amplitude a_y = 2^{-n} Σ_x (-1)^{f(x)+x·y}."
amplitude_formula(f, y) = sum((-1)^(f[x+1] + count_ones(x & y)) for x in 0:length(f)-1) / length(f)

"Balanced functions on N inputs: choose which N/2 inputs map to 1."
function balanced_tables(N)
    tabs = Vector{Vector{Int}}()
    for mask in 0:2^N-1
        count_ones(mask) == N ÷ 2 || continue
        push!(tabs, [(mask >> x) & 1 for x in 0:N-1])
    end
    return tabs
end

success_prob(ψ, marked) = sum(probabilities(ψ)[w+1] for w in marked)

"The DFT matrix straight from the definition F[y,x] = ω^{xy}/√N."
dft_matrix(N) = [cis(2π * x * y / N) for y in 0:N-1, x in 0:N-1] / sqrt(N)

"Classical radix-2 FFT with the QFT's sign convention (e^{+2πi...}), normalised by 1/√N; shares nothing with the circuit."
function fft_plus(v::AbstractVector)
    N = length(v)
    N == 1 && return ComplexF64.(v)
    ev, od = fft_plus(v[1:2:end]), fft_plus(v[2:2:end])   # √(N/2)-normalised
    tw = [cis(2π * k / N) for k in 0:N÷2-1]
    return vcat(ev .+ tw .* od, ev .- tw .* od) ./ sqrt(2)
end

"QPE: the distribution over the counting register (the eigen-qubit traced out)."
counting_distribution(t, φ) = real.(diag(reduced_density(run_circuit(qpe_circuit(t, φ)), collect(0:t-1))))
qpe_formula(t, φ) = [abs2(sum(cis(2π * x * (φ - y / 2^t)) for x in 0:2^t-1) / 2^t) for y in 0:2^t-1]

depolarizing(p)  = [sqrt(1 - 3p / 4) * I2, sqrt(p / 4) * X, sqrt(p / 4) * Y, sqrt(p / 4) * Z]
amp_damping(γ)   = [ComplexF64[1 0; 0 sqrt(1 - γ)], ComplexF64[0 sqrt(γ); 0 0]]
phase_damping(λ) = [ComplexF64[1 0; 0 sqrt(1 - λ)], ComplexF64[0 0; 0 sqrt(λ)]]
is_valid_density(ρ) = ishermitian(round.(ρ, digits=13)) && isapprox(tr(ρ), 1, atol=1e-12) &&
                      minimum(eigvals(Hermitian(ρ))) > -1e-12
purity(ρ) = real(tr(ρ * ρ))
chsh(ρ) = real(tr(ρ * (kron(tilted(π/4), tilted(0)) + kron(tilted(-π/4), tilted(0)) +
                       kron(tilted(π/4), tilted(π/2)) - kron(tilted(-π/4), tilted(π/2)))))

"Monte-Carlo trajectory: at each channel pick K_i with probability ‖K_i ψ‖², renormalise."
function trajectory(ψ0, steps, rng)
    ψ = copy(ψ0)
    for (K, q) in steps
        cand = [apply!(copy(ψ), k, q) for k in K]
        w = [norm(c)^2 for c in cand]
        i = searchsortedfirst(cumsum(w), rand(rng) * sum(w))
        ψ = normalize_state!(cand[i])
    end
    return ψ
end

# VQE: the 2-qubit transverse-field Ising model H = Z⊗Z + h (X⊗I + I⊗X).
const TFIM_H = 0.5
const TFIM = kron(Z, Z) + TFIM_H * (kron(X, I2) + kron(I2, X))

"Hardware-efficient ansatz, L layers: [RY q0, RY q1, CX 0→1] × L, then a final RY layer."
function ansatz(θ::AbstractVector, L::Integer)
    c = Circuit(2); i = 0
    for _ in 1:L
        add!(c, :ry, 0; t = θ[i+=1]); add!(c, :ry, 1; t = θ[i+=1]); add!(c, :cx, 0, 1)
    end
    add!(c, :ry, 0; t = θ[i+=1]); add!(c, :ry, 1; t = θ[i+=1])
    return c
end
nparams(L) = 2L + 2
energy(θ, L) = expectation(run_circuit(ansatz(θ, L)), TFIM)

"Parameter-shift gradient: two circuit evaluations per parameter, no step size."
function grad_shift(θ, L)
    g = similar(θ)
    for k in eachindex(θ)
        e = zeros(length(θ)); e[k] = π / 2
        g[k] = (energy(θ + e, L) - energy(θ - e, L)) / 2
    end
    return g
end
"Central finite difference: the approximate method the shift rule is checked against."
grad_fd(θ, L; ϵ=1e-6) = [(energy(θ + ϵ * (eachindex(θ) .== k), L) - energy(θ - ϵ * (eachindex(θ) .== k), L)) / 2ϵ
                         for k in eachindex(θ)]
function vqe(L, rng; steps=400, lr=0.2)
    θ = 2π * rand(rng, nparams(L))
    for _ in 1:steps
        θ .-= lr * grad_shift(θ, L)
    end
    return θ, energy(θ, L)
end

@testset "QSim" begin

@testset "basics" begin
    @test nqubits(zero_state(5)) == 5
    @test_throws ArgumentError nqubits(zeros(ComplexF64, 6))
    @test basis_state(3, 0b110)[7] == 1
    @test basis_state(2, 0) == ComplexF64[1, 0, 0, 0]
    @test_throws ArgumentError basis_state(2, 4)
    @test bitstring_of(6, 3) == "110"          # qubit 0 is the RIGHTMOST char
    @test bitstring_of(1, 4) == "0001"
end

@testset "all fixed and parametrised gates are unitary" begin
    for U in (I2, X, Y, Z, H, S, Sdg, T, Tdg, SX, CX, CZ, SWAP)
        @test is_unitary(U)
    end
    rng = MersenneTwister(1)
    for _ in 1:50
        a, b, c = 2π .* rand(rng, 3)
        @test is_unitary(RX(a)) && is_unitary(RY(a)) && is_unitary(RZ(a)) && is_unitary(P(a))
        @test is_unitary(U3(a, b, c)) && is_unitary(CP(a))
    end
    @test S * Sdg ≈ I2 && T * Tdg ≈ I2
    # SX is Qiskit's √X: e^{iπ/4} RX(π/2), not its inverse (whose square is also X).
    # Added in the port: only the Qiskit cross-check caught SX† before.
    @test SX ≈ cis(π / 4) * RX(π / 2)
end

@testset "little-endian convention, concretely" begin
    # X on qubit 0 of |000> → |001> = index 1;  X on qubit 2 → |100> = index 4
    @test apply!(zero_state(3), X, 0) == basis_state(3, 1)
    @test apply!(zero_state(3), X, 2) == basis_state(3, 4)
    # CX(control 0, target 1) on |01> (q0 = 1) gives |11>
    @test apply!(basis_state(2, 0b01), CX, [0, 1]) ≈ basis_state(2, 0b11)
    # ...and with the roles reversed nothing happens to |01> (control q1 = 0)
    @test apply!(basis_state(2, 0b01), CX, [1, 0]) ≈ basis_state(2, 0b01)
    @test full_operator_kron(X, 0, 2) ≈ kron(I2, X)  # qubit 0 = RIGHT factor
end

@testset "three independent gate-application paths agree (property test)" begin
    rng = MersenneTwister(2)
    for _ in 1:400
        n = rand(rng, 1:5)
        k = rand(rng, 1:min(n, 3))
        qs = randperm(rng, n)[1:k] .- 1
        U = rand_unitary(rng, 2^k)
        ψ = rand_state(rng, n)
        fast = apply!(copy(ψ), U, qs)
        @test fast ≈ full_operator(U, qs, n) * ψ
        if k == 1
            @test full_operator_kron(U, qs[1], n) ≈ full_operator(U, qs, n)
        end
    end
end

@testset "unitarity preserves the norm; inverse undoes" begin
    rng = MersenneTwister(3)
    for _ in 1:200
        n = rand(rng, 1:6); qs = randperm(rng, n)[1:rand(rng, 1:min(n, 3))] .- 1
        U = rand_unitary(rng, 2^length(qs)); ψ = rand_state(rng, n)
        φ = apply!(copy(ψ), U, qs)
        @test norm(φ) ≈ 1
        @test apply!(φ, U', qs) ≈ ψ
    end
end

@testset "controlled gates" begin
    # apply_controlled!(X, [c], [t]) must equal the CX matrix
    rng = MersenneTwister(4)
    for _ in 1:50
        ψ = rand_state(rng, 3)
        @test apply_controlled!(copy(ψ), X, [0], [2]) ≈ apply!(copy(ψ), CX, [0, 2])
        @test apply_controlled!(copy(ψ), Z, [1], [0]) ≈ apply!(copy(ψ), CZ, [1, 0])
        @test apply_controlled!(copy(ψ), X, [0, 1], [2]) ≈
              apply!(copy(ψ), gate_matrix(Gate(:ccx, [0, 1, 2])), [0, 1, 2])
    end
    # Toffoli truth table: flips target iff both controls are 1
    for k in 0:7
        out = apply!(basis_state(3, k), gate_matrix(Gate(:ccx, [0, 1, 2])), [0, 1, 2])
        expected = (k & 0b011) == 0b011 ? k ⊻ 0b100 : k
        @test out ≈ basis_state(3, expected)
    end
    # CX = (I⊗H) CZ (I⊗H) with H on the target
    @test full_operator(CX, [0, 1], 2) ≈ kron(H, I2) * CZ * kron(H, I2)
    # SWAP = three CNOTs
    c = Circuit(2); add!(c, :cx, 0, 1); add!(c, :cx, 1, 0); add!(c, :cx, 0, 1)
    @test circuit_unitary(c) ≈ SWAP
end

@testset "partial trace and Bloch vectors" begin
    rng = MersenneTwister(5)
    for _ in 1:100
        a, b = rand_state(rng, 1), rand_state(rng, 1)
        ψ = kron(b, a)                          # qubit 1 = b, qubit 0 = a
        @test reduced_density(ψ, 0) ≈ a * a'
        @test reduced_density(ψ, 1) ≈ b * b'
        @test norm(bloch_vector(ψ, 0)) ≈ 1      # product ⇒ each part pure
    end
    for _ in 1:50
        ψ = rand_state(rng, 4)
        ρ = reduced_density(ψ, [2, 0])
        @test tr(ρ) ≈ 1 && ishermitian(round.(ρ, digits=12))
        # brute-force partial trace from the definition, sharing no code
        ρbf = zeros(ComplexF64, 4, 4)
        for i in 0:15, j in 0:15
            rest_i = ((i >> 1) & 1) | (((i >> 3) & 1) << 1)
            rest_j = ((j >> 1) & 1) | (((j >> 3) & 1) << 1)
            rest_i == rest_j || continue
            li = ((i >> 2) & 1) | ((i & 1) << 1)     # keep = [2, 0]: q2 is LSB
            lj = ((j >> 2) & 1) | ((j & 1) << 1)
            ρbf[li+1, lj+1] += ψ[i+1] * conj(ψ[j+1])
        end
        @test ρ ≈ ρbf
    end
end

@testset "measurement: sampler is statistically correct (chi-square)" begin
    rng = MersenneTwister(6)
    ψ = rand_state(rng, 3)
    p = probabilities(ψ)
    N = 200_000
    counts = sample_counts(ψ, N; rng = MersenneTwister(60))
    obs = [get(counts, bitstring_of(k, 3), 0) for k in 0:7]
    χ2 = sum((obs .- N .* p) .^ 2 ./ (N .* p))
    # 7 degrees of freedom: P(χ² > 24.3) ≈ 0.001. A biased sampler blows far past this.
    @test χ2 < 24.3
    # measure! must also follow the Born rule. (Added after mutation testing:
    # a measure! that reported the FLIPPED outcome but collapsed consistently
    # passed every other check, because teleportation only ever measures
    # qubits with P = ½, where a flip is invisible. Use a lopsided P(1) = 0.9.)
    θ = 2asin(sqrt(0.9))                      # RY(θ)|0> has P(1) = sin²(θ/2) = 0.9
    for q in 0:2
        ψq = apply!(zero_state(3), RY(θ), q)
        mrng = MersenneTwister(61 + q)
        ones_ = sum(measure!(copy(ψq), q; rng = mrng) for _ in 1:20_000)
        @test abs(ones_ / 20_000 - 0.9) < 5 * sqrt(0.9 * 0.1 / 20_000)
    end
    # collapse: after measuring, the qubit is definite and the state normalised
    for _ in 1:100
        φ = rand_state(rng, 3); m = measure!(φ, 1; rng = rng)
        @test norm(φ) ≈ 1
        @test bloch_vector(φ, 1)[3] ≈ (m == 0 ? 1 : -1)
    end
end

@testset "circuit text format round-trips exactly" begin
    rng = MersenneTwister(7)
    c = Circuit(4)
    add!(c, :h, 0); add!(c, :cx, 0, 3); add!(c, :rz, 2; θ = rand(rng))
    add!(c, :u, 1; a = rand(rng), b = rand(rng), d = rand(rng)); add!(c, :cp, 3, 1; λ = π / 7)
    push!(c.gates, Gate(:mcz, [0, 1, 2, 3], Float64[]))
    c2 = parse_circuit(circuit_text(c))
    @test c2.n == c.n
    @test all(g1.name == g2.name && g1.qubits == g2.qubits && g1.params == g2.params  # bitwise
              for (g1, g2) in zip(c.gates, c2.gates))
end

@testset "algorithms (structural)" begin
    for n in 1:6
        N = 2^n
        @test circuit_unitary(qft_circuit(n)) ≈ [cis(2π * x * y / N) for y in 0:N-1, x in 0:N-1] / √N
    end
    @test grover_iterations(10) == 25          # round(π/4·32 - 1/2) = 25
    @test probabilities(run_circuit(bv_circuit(4, 0b1011)))[0b1011+1] ≈ 1
end

# ---- the lesson checks ----------------------------------------------------------

@testset "lesson 1: one qubit, gates, the Bloch sphere" begin
    @testset "every gate is unitary" begin
        for U in (X, Y, Z, H, S, T, SX, RX(0.7), RY(1.3), RZ(2.1), U3(0.3, 1.1, -0.4))
            @test is_unitary(U)
        end
    end
    @testset "gate identities" begin
        @test H * X * H ≈ Z                      # H swaps the x and z axes
        @test H * Z * H ≈ X
        @test S * S ≈ Z                          # two quarter turns = half turn
        @test T * T ≈ S
        @test SX * SX ≈ X                        # √X really is a square root of X
        @test X * Y ≈ im * Z                     # Pauli algebra
        @test RX(π) ≈ -im * X                    # X up to the global phase -i
        @test RZ(2π) ≈ -I2                       # a full turn gives -1
        @test P(0.9) ≈ cis(0.9 / 2) * RZ(0.9)    # same gate up to global phase
        # U(θ,φ,λ) = RZ(φ) RY(θ) RZ(λ) up to global phase (ZYZ Euler angles)
        @test equal_up_to_global_phase(vec(U3(0.3, 1.1, -0.4)), vec(RZ(1.1) * RY(0.3) * RZ(-0.4)))
    end
    @testset "Bloch vectors of the six cardinal states" begin
        cardinal = [(ComplexF64[1, 0], [0, 0, 1]), (ComplexF64[0, 1], [0, 0, -1]),
                    (ComplexF64[1, 1] / √2, [1, 0, 0]), (ComplexF64[1, -1] / √2, [-1, 0, 0]),
                    (ComplexF64[1, im] / √2, [0, 1, 0]), (ComplexF64[1, -im] / √2, [0, -1, 0])]
        for (ψ, r) in cardinal
            @test isapprox(bloch_vector(ψ, 0), r, atol=1e-12)
        end
        @test run_circuit(add!(Circuit(1), :h, 0)) ≈ cardinal[3][1]                       # H|0> = |+>
        @test run_circuit(add!(add!(Circuit(1), :h, 0), :s, 0)) ≈ cardinal[5][1]          # S H|0> = |+i>
    end
    @testset "rotations rotate the Bloch vector by the stated angle" begin
        # RY(θ)|0> points at polar angle θ in the x-z plane; RZ(φ) spins it about z.
        rng = MersenneTwister(1)
        for _ in 1:5
            θ, φ = π * rand(rng), 2π * rand(rng)
            c = Circuit(1); add!(c, :ry, 0; θ = θ); add!(c, :rz, 0; φ = φ)
            @test isapprox(bloch_vector(run_circuit(c), 0), [sin(θ) * cos(φ), sin(θ) * sin(φ), cos(θ)], atol=1e-12)
        end
    end
    @testset "measurement statistics follow the Born rule" begin
        # RY(θ)|0> has P(1) = sin²(θ/2); standard error √(p(1-p)/N), 5σ allowed.
        θ = 2π / 3
        ψ = run_circuit(add!(Circuit(1), :ry, 0; θ = θ))
        p1 = sin(θ / 2)^2
        N = 200_000
        f1 = get(sample_counts(ψ, N; rng = MersenneTwister(42)), "1", 0) / N
        @test abs(f1 - p1) < 5 * sqrt(p1 * (1 - p1) / N)
    end
end

@testset "lesson 2: entanglement, Bell states, CHSH, GHZ" begin
    @testset "the four Bell states" begin
        # Little-endian: index k = 2·q1 + q0. |01> means q1=0, q0=1, so k=1.
        expected = Dict(:Φp => [1, 0, 0, 1] / √2, :Φm => [1, 0, 0, -1] / √2,
                        :Ψp => [0, 1, 1, 0] / √2, :Ψm => [0, -1, 1, 0] / √2)
        for kind in (:Φp, :Φm, :Ψp, :Ψm)
            @test equal_up_to_global_phase(bell(kind), ComplexF64.(expected[kind]))
        end
        B = reduce(hcat, bell.((:Φp, :Φm, :Ψp, :Ψm)))
        @test B' * B ≈ I                         # an orthonormal basis
    end
    @testset "half of a Bell pair is maximally mixed" begin
        ψ = bell(:Φp)
        ρ0 = reduced_density(ψ, 0)
        @test ρ0 ≈ I2 / 2
        @test norm(bloch_vector(ψ, 0)) < 1e-12
        @test isapprox(entropy(ρ0), 1, atol=1e-12)             # exactly 1 bit
        prod_state = kron(ComplexF64[cos(0.4), sin(0.4)], ComplexF64[1, im] / √2)
        @test entropy(reduced_density(prod_state, 0)) < 1e-10  # control: product state
        counts = sample_counts(ψ, 10_000; rng = MersenneTwister(7))
        @test Set(keys(counts)) ⊆ Set(["00", "11"])            # perfect correlation
    end
    @testset "CHSH: classical bound 2 vs quantum 2√2" begin
        ψ = bell(:Φp)
        a, a′, b, b′ = 0.0, π / 2, π / 4, -π / 4             # the optimal angles
        # S = E(a,b) + E(a,b′) + E(a′,b) - E(a′,b′). Which term carries the minus
        # sign must match the angle choice; with these angles each term
        # contributes +1/√2, giving 4/√2 = 2√2.
        S_quantum = correlator(ψ, a, b) + correlator(ψ, a, b′) + correlator(ψ, a′, b) - correlator(ψ, a′, b′)
        @test isapprox(S_quantum, 2√2, atol=1e-12)
        @test all(isapprox(correlator(ψ, x, y), cos(x - y), atol=1e-12) for x in 0:0.5:3, y in 0:0.7:3)
        # Classical: 16 deterministic local strategies; shared randomness only mixes them.
        S_classical = maximum(α * β + α * β′ + α′ * β - α′ * β′
                              for (α, α′, β, β′) in Iterators.product((-1, 1), (-1, 1), (-1, 1), (-1, 1)))
        @test S_classical == 2
        rng = MersenneTwister(2026)
        shots = 100_000
        S_sampled = sampled_correlator(a, b, shots, rng) + sampled_correlator(a, b′, shots, rng) +
                    sampled_correlator(a′, b, shots, rng) - sampled_correlator(a′, b′, shots, rng)
        σS = 2 / sqrt(shots)                  # four correlators, each variance ≤ 1/shots
        @test abs(S_sampled - 2√2) < 5σS && S_sampled > 2 + 5σS
    end
    @testset "GHZ states on 3-6 qubits" begin
        for n in 3:6
            ψ = run_circuit(ghz_circuit(n))
            p = probabilities(ψ)
            @test isapprox(p[1], 0.5, atol=1e-12) && isapprox(p[end], 0.5, atol=1e-12) &&
                  isapprox(sum(p[2:end-1]), 0, atol=1e-12)
            @test isapprox(expectation(ψ, reduce(kron, fill(X, n))), 1, atol=1e-12)   # parity +1
            @test all(norm(bloch_vector(ψ, q)) < 1e-12 for q in 0:n-1)
        end
    end
end

@testset "lesson 3: teleportation" begin
    @testset "with mid-circuit measurement" begin
        rng = MersenneTwister(11)
        trials = 2000
        fids = Float64[]
        outcomes = Dict{Tuple{Int,Int},Int}()
        for _ in 1:trials
            ang = random_angles(rng)
            φ = U3(ang...) * ComplexF64[1, 0]                # what Bob should receive
            ψ, m = teleport_once(ang, rng)
            push!(fids, real(φ' * reduced_density(ψ, 2) * φ))
            outcomes[m] = get(outcomes, m, 0) + 1
        end
        @test minimum(fids) > 1 - 1e-12
        σ = sqrt(0.25 * 0.75 / trials)
        for m in [(0, 0), (0, 1), (1, 0), (1, 1)]
            @test abs(get(outcomes, m, 0) / trials - 0.25) < 5σ   # each outcome ¼
        end
    end
    @testset "control: skipping Bob's corrections must fail" begin
        rng = MersenneTwister(12)
        bad = [begin
                   ang = random_angles(rng)
                   φ = U3(ang...) * ComplexF64[1, 0]
                   ψ, _ = teleport_once(ang, rng; correct = false)
                   real(φ' * reduced_density(ψ, 2) * φ)
               end for _ in 1:500]
        @test sum(bad) / length(bad) < 0.9
    end
    @testset "deferred-measurement version" begin
        rng = MersenneTwister(13)
        @test all(begin
                      ang = random_angles(rng)
                      φ = U3(ang...) * ComplexF64[1, 0]
                      isapprox(reduced_density(run_circuit(teleport_deferred(ang)), 2), φ * φ', atol=1e-12)
                  end for _ in 1:200)
    end
end

@testset "lesson 4: Deutsch-Jozsa and Bernstein-Vazirani" begin
    @testset "all 72 constant and balanced functions on 3 qubits" begin
        N = 8
        bal = balanced_tables(N)
        @test length(bal) == 70                   # C(8,4)
        consts = [zeros(Int, N), ones(Int, N)]
        @test all(isapprox(probabilities(hadamard_sandwich(f))[1], 1, atol=1e-12) for f in consts)
        @test all(probabilities(hadamard_sandwich(f))[1] < 1e-24 for f in bal)
        @test all(isapprox(real.(hadamard_sandwich(f)), [amplitude_formula(f, y) for y in 0:N-1], atol=1e-12)
                  for f in vcat(consts, bal))
    end
    @testset "random balanced functions on 4 and 5 qubits" begin
        rng = MersenneTwister(5)
        for n in (4, 5)
            N = 2^n
            @test all(probabilities(hadamard_sandwich(shuffle(rng, vcat(zeros(Int, N ÷ 2), ones(Int, N ÷ 2)))))[1] < 1e-24
                      for _ in 1:300)
        end
    end
    @testset "every hidden string s, n = 1...5" begin
        for n in 1:5
            @test all(probabilities(run_circuit(bv_circuit(n, s)))[s+1] > 1 - 1e-12 for s in 0:2^n-1)
        end
        s = 0b10110                               # the Z-gate oracle equals the truth-table oracle
        @test run_circuit(bv_circuit(5, s)) ≈ hadamard_sandwich([count_ones(x & s) % 2 for x in 0:31])
    end
end

@testset "lesson 5: Grover search" begin
    @testset "success probability = sin²((2k+1)θ) for every k" begin
        rng = MersenneTwister(3)
        for n in 2:8, M in (1, 2, 3)
            M < 2^(n - 1) || continue
            marked = sort(randperm(rng, 2^n)[1:M] .- 1)
            θ = asin(sqrt(M / 2^n))
            worst = maximum(abs(success_prob(run_circuit(grover_circuit(n, marked, k)), marked) - sin((2k + 1) * θ)^2)
                            for k in 0:max(2grover_iterations(n, M), 1))
            @test worst < 1e-10
        end
    end
    @testset "the state never leaves the plane span{|α>, |β>}" begin
        n, marked = 6, [9, 40]
        unmarked = setdiff(0:2^n-1, marked)
        for k in 0:8
            ψ = run_circuit(grover_circuit(n, marked, k))
            a_m = ψ[marked .+ 1]; a_u = ψ[unmarked .+ 1]
            @test all(≈(a_m[1]; atol=1e-12), a_m) && all(≈(a_u[1]; atol=1e-12), a_u)
        end
    end
    @testset "small cases you can check by hand" begin
        @test isapprox(probabilities(run_circuit(grover_circuit(2, [3], 1)))[4], 1, atol=1e-12)   # 3θ = 90°
        @test grover_iterations(4) == 3 && grover_iterations(6) == 6 && grover_iterations(8) == 12
        P16 = [success_prob(run_circuit(grover_circuit(4, [5], k)), [5]) for k in 0:6]
        @test argmax(P16) - 1 == 3 && P16[7] < P16[4]      # overshooting hurts
    end
end

@testset "lesson 6: the quantum Fourier transform" begin
    @testset "the circuit's unitary is exactly the DFT matrix" begin
        for n in 1:7
            @test maximum(abs.(circuit_unitary(qft_circuit(n)) - dft_matrix(2^n))) < 1e-12
        end
    end
    @testset "inverse QFT undoes it" begin
        for n in (3, 5)
            c = qft_circuit(n); iqft!(c, collect(0:n-1))
            @test circuit_unitary(c) ≈ I
        end
    end
    @testset "agreement with an independent classical FFT" begin
        rng = MersenneTwister(8)
        for n in (4, 6)
            v = normalize_state!(randn(rng, ComplexF64, 2^n))
            @test isapprox(run_circuit(qft_circuit(n), v), fft_plus(v), atol=1e-12)
        end
    end
    @testset "periodic input gives peaks at multiples of N/r" begin
        n, r, x0 = 6, 8, 3
        N = 2^n
        v = zeros(ComplexF64, N); v[(x0:r:N-1) .+ 1] .= 1; normalize_state!(v)
        p = probabilities(run_circuit(qft_circuit(n), v))
        peaks = findall(>(1e-12), p) .- 1
        @test peaks == collect(0:N÷r:N-1)
        @test all(isapprox(p[y+1], 1 / r, atol=1e-12) for y in peaks)
    end
end

@testset "lesson 7: quantum phase estimation" begin
    @testset "exact phases j/2^t are read out with certainty" begin
        for t in 2:6
            @test all(isapprox(counting_distribution(t, j / 2^t)[j+1], 1, atol=1e-12) for j in 0:2^t-1)
        end
    end
    @testset "non-dyadic phases: distribution matches the closed form" begin
        rng = MersenneTwister(21)
        for t in (3, 5, 7), _ in 1:3
            φ = rand(rng)
            d = counting_distribution(t, φ)
            ybest = round(Int, φ * 2^t) % 2^t
            @test maximum(abs.(d - qpe_formula(t, φ))) < 1e-12 && d[ybest+1] ≥ 4 / π^2 - 1e-12
        end
    end
    @testset "more counting qubits give a sharper estimate" begin
        φ = 1 / 3                                 # 0.010101... in binary: never exact
        errs = [abs(argmax(counting_distribution(t, φ)) - 1 - φ * 2^t) / 2^t for t in 2:7]
        @test all(errs[i] ≤ 1 / 2^(i + 2) + 1e-12 for i in eachindex(errs))
    end
end

@testset "lesson 8: noise, density matrices, channels" begin
    @testset "each channel moves the Bloch vector as predicted" begin
        rng = MersenneTwister(4)
        for _ in 1:5
            ang = (π * rand(rng), 2π * rand(rng), 0.0)
            ρ = density_matrix(U3(ang...) * ComplexF64[1, 0]); r = bloch_vector(ρ)
            p, γ, λ = rand(rng), rand(rng), rand(rng)
            @test bloch_vector(apply_kraus(ρ, depolarizing(p), 0)) ≈ (1 - p) * r
            @test bloch_vector(apply_kraus(ρ, amp_damping(γ), 0)) ≈ [sqrt(1 - γ) * r[1], sqrt(1 - γ) * r[2], γ + (1 - γ) * r[3]]
            @test bloch_vector(apply_kraus(ρ, phase_damping(λ), 0)) ≈ [sqrt(1 - λ) * r[1], sqrt(1 - λ) * r[2], r[3]]
        end
    end
    @testset "channels keep ρ physical and lower the purity of a pure state" begin
        ρ = density_matrix(run_circuit(ghz_circuit(3)))
        for K in (depolarizing(0.3), amp_damping(0.4), phase_damping(0.5))
            ρ′ = apply_kraus(ρ, K, 1)
            @test is_valid_density(ρ′)
            @test purity(ρ′) < 1 - 1e-6
        end
        @test_throws ArgumentError apply_kraus(ρ, [0.5 * I2], 0)   # not trace preserving
    end
    @testset "entanglement under noise: Bell fidelity and CHSH" begin
        # Depolarizing half of |Φ+>: F = 1 - 3p/4 and CHSH = 2√2(1-p).
        bellψ = run_circuit(bell_pair!(Circuit(2), 0, 1))
        for p in (0.0, 0.1, 0.25, 0.3, 0.6)
            ρp = apply_kraus(density_matrix(bellψ), depolarizing(p), 0)
            @test isapprox(real(bellψ' * ρp * bellψ), 1 - 3p / 4, atol=1e-12) && isapprox(chsh(ρp), 2√2 * (1 - p), atol=1e-12)
        end
        # threshold 1 - 1/√2 ≈ 0.2929
        @test chsh(apply_kraus(density_matrix(bellψ), depolarizing(0.29), 0)) > 2 &&
              chsh(apply_kraus(density_matrix(bellψ), depolarizing(0.30), 0)) < 2
    end
    @testset "independent method: Monte-Carlo quantum trajectories" begin
        ψ = run_circuit(ghz_circuit(3))
        steps = [(amp_damping(0.3), 1), (depolarizing(0.2), 2)]
        ρ_exact = apply_kraus(apply_kraus(density_matrix(ψ), steps[1]...), steps[2]...)
        rng = MersenneTwister(99)
        R = 40_000
        ρ_mc = sum(density_matrix(trajectory(ψ, steps, rng)) for _ in 1:R) / R
        @test maximum(abs.(ρ_mc - ρ_exact)) < 5 / sqrt(R)
    end
    @testset "T1 decay: repeated damping relaxes exponentially" begin
        γ = 0.05
        ρ1 = density_matrix(ComplexF64[0, 1])
        pops = Float64[]
        for _ in 1:40
            ρ1 = apply_kraus(ρ1, amp_damping(γ), 0)
            push!(pops, real(ρ1[2, 2]))
        end
        @test all(isapprox(pops[k], (1 - γ)^k, atol=1e-12) for k in 1:40)
    end
end

@testset "lesson 9: VQE and the parameter-shift rule" begin
    E0 = minimum(eigvals(Hermitian(TFIM)))
    @testset "the Hamiltonian and its exact ground state" begin
        @test ishermitian(TFIM)
        @test isapprox(E0, -sqrt(1 + 4TFIM_H^2), atol=1e-12)
    end
    rng = MersenneTwister(17)
    L = 2
    @testset "parameter-shift rule == finite differences" begin
        for _ in 1:5
            θ = 2π * rand(rng, nparams(L))
            @test maximum(abs.(grad_shift(θ, L) - grad_fd(θ, L))) < 1e-8
        end
    end
    @testset "variational principle: E(θ) ≥ E₀ for any θ" begin
        @test all(energy(2π * rand(rng, nparams(L)), L) ≥ E0 - 1e-12 for _ in 1:10_000)
    end
    @testset "gradient descent reaches the ground energy" begin
        best = minimum(last(vqe(L, rng)) for _ in 1:5)         # 5 random restarts
        @test abs(best - E0) < 1e-8
        # Control: without an entangling gate only product states are reachable,
        # and the ground state is entangled, so this must stay above E₀.
        prod_energy(θ) = expectation(kron(RY(θ[2]) * ComplexF64[1, 0], RY(θ[1]) * ComplexF64[1, 0]), TFIM)
        @test minimum(prod_energy([a, b]) for a in range(0, 2π, 400), b in range(0, 2π, 400)) > E0 + 0.01
    end
end

end # testset
