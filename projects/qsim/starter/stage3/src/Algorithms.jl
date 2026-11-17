#=
Circuit builders for the textbook algorithms (included into module QSim).

Each builder returns a gate-level `Circuit` (only gates QSim and Qiskit both
know), so the very same circuit can be exported and re-simulated in Qiskit by
the author-side cross-check. That separates two questions:
   1. does the SIMULATOR compute this circuit correctly?   (Qiskit diff)
   2. is the CIRCUIT the right algorithm?                    (analytic checks)
=#

"|Φ+> = (|00> + |11>)/√2 on qubits (a, b): H on a, then CNOT a → b."
function bell_pair!(c::Circuit, a::Integer, b::Integer)
    add!(c, :h, a); add!(c, :cx, a, b)
    return c
end

"GHZ state (|0...0> + |1...1>)/√2: one H, then a CNOT chain spreading the bit."
function ghz_circuit(n::Integer)
    c = Circuit(n); add!(c, :h, 0)
    for q in 1:n-1
        add!(c, :cx, q - 1, q)
    end
    return c
end

"""
    qft!(c, qubits)

Append the quantum Fourier transform on `qubits` (qubits[1] = least
significant) to circuit `c`, and return `c`:

    QFT |x> = (1/√N) Σ_y  e^{2πi·x·y/N} |y> ,   N = 2^m.

Construction (same as Qiskit's QFT with swaps): working from the most
significant qubit down, apply H, then controlled phases `:cp` with
λ = π/2^d from each lower qubit at distance d. This builds the product form

    QFT|x> = ⊗_j (|0> + e^{2πi·x/2^{j+1}} |1>)/√2 ,

but with the bit order reversed, hence a final layer of SWAPs.
"""
function qft!(c::Circuit, qubits::AbstractVector{<:Integer})
    error("TODO(hole:qft)")
end

"""
    iqft!(c, qubits)

Append the inverse QFT on `qubits` to `c`, and return `c`. QFT† is the same
gates in REVERSE order, each inverted. H and SWAP are their own inverses;
CP(λ)† = CP(-λ).
"""
function iqft!(c::Circuit, qubits::AbstractVector{<:Integer})
    error("TODO(hole:iqft)")
end

qft_circuit(n::Integer) = qft!(Circuit(n), collect(0:n-1))

"""
Optimal number of Grover iterations for M marked items out of N = 2^n:
the state rotates by angle 2θ per iteration, sin θ = √(M/N), starting at θ,
so we want (2k+1)θ ≈ π/2  ⇒  k = round(π/(4θ) - 1/2).
"""
function grover_iterations(n::Integer, M::Integer=1)
    θ = asin(sqrt(M / 2^n))
    return max(0, round(Int, π / (4θ) - 1 / 2))
end

"Phase-flip one basis state w: conjugate an all-qubit MCZ with X on the 0 bits of w."
function _flip_basis_state!(c::Circuit, w::Integer)
    zeros_of_w = [q for q in 0:c.n-1 if (w >> q) & 1 == 0]
    for q in zeros_of_w; add!(c, :x, q); end
    push!(c.gates, Gate(:mcz, collect(0:c.n-1), Float64[]))
    for q in zeros_of_w; add!(c, :x, q); end
end

"""
    grover_circuit(n, marked, k)

Grover search on n qubits: the uniform superposition, then k rounds of
   oracle   O = I - 2 Σ_{w∈marked} |w><w|         (flip the marked phases)
   diffuser D = 2|s><s| - I                        (inversion about the mean)
Returns the `Circuit`. D can be built as H^n · (flip of |0...0>) · H^n, which
equals -(2|s><s| - I); the overall -1 is a global phase and changes no
probability. `_flip_basis_state!(c, w)` appends the phase flip of |w>.
"""
function grover_circuit(n::Integer, marked::AbstractVector{<:Integer}, k::Integer)
    error("TODO(hole:grover)")
end

"""
    bv_circuit(n, s)

Bernstein-Vazirani: find the hidden string s of f(x) = s·x mod 2 in ONE query.
Phase oracle: (-1)^{s·x} = Π_{q: s_q=1} (-1)^{x_q}, which is just a Z gate on
every qubit where s has a 1. H^n before and after maps |0> to exactly |s>.
"""
function bv_circuit(n::Integer, s::Integer)
    c = Circuit(n)
    for q in 0:n-1; add!(c, :h, q); end
    for q in 0:n-1
        (s >> q) & 1 == 1 && add!(c, :z, q)
    end
    for q in 0:n-1; add!(c, :h, q); end
    return c
end

"""
    qpe_circuit(t, φ)

Quantum phase estimation of U = P(2πφ) on its eigenstate |1> (U|1> = e^{2πiφ}|1>),
returned as a `Circuit` on t + 1 qubits: counting qubits 0...t-1, eigenstate
qubit t.
  1. X on qubit t prepares the eigenstate.
  2. H on each counting qubit j, then controlled-U^{2^j} = CP(2πφ·2^j).
     Phase kickback leaves the counting register in (1/√N)Σ_x e^{2πiφx}|x>,
     which is exactly QFT|φN> when φN is an integer.
  3. Inverse QFT on the counting register → read out y ≈ φ·2^t.
"""
function qpe_circuit(t::Integer, φ::Real)
    error("TODO(hole:qpe)")
end
