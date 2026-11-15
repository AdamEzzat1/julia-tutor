#=
Differential test: the qsim reference vs Yao 0.9.3, a second independent
simulator, in Julia (no Python needed):

    julia --project=projects/qsim/crosscheck/yao projects/qsim/crosscheck/yao_diff.jl [N_RANDOM]

  A. N_RANDOM (default 500) seeded random circuits over the full gate set,
     the same distribution as qiskit_diff.py: identical statevectors,
     global phase included.
  B. Every lesson circuit, rebuilt from the current reference (lessons.jl):
     drift from lesson_circuits/ is a FAIL of its own, and each rebuilt
     circuit is still compared.

Each circuit is a text in the shared format. QSim reads it with its own
parse_circuit; Yao's circuit is built here by a separate tokenizer, from
Yao's own gate blocks, never from a QSim matrix. Yao numbers qubits from 1
and is little-endian like QSim (qubit 1 is the least significant bit), so
qubit q here is Yao's q+1 and the amplitudes line up index for index.

QSIM_REFERENCE: another copy of the reference project (a seeded mutant);
default ../reference. QSim needs only stdlibs, so it is included, not a
package of this environment.
=#
import Yao
using Random

const REF = get(ENV, "QSIM_REFERENCE", joinpath(@__DIR__, "..", "reference"))
include(joinpath(REF, "src", "QSim.jl"))
using .QSim          # Yao stays qualified (`import Yao`), so the names do not clash
include(joinpath(@__DIR__, "lessons.jl"))

const ATOL = 1e-10
const G = Yao.ConstGate          # Yao's fixed gates (S, Sdag, Tdag live only here)
const ONE_Q = ["id", "x", "y", "z", "h", "s", "sdg", "t", "tdg", "sx"]
const ONE_Q_PARAM = ["rx" => 1, "ry" => 1, "rz" => 1, "p" => 1, "u" => 3]
const ARITY = Dict("cx" => 2, "cz" => 2, "swap" => 2, "cp" => 2, "ccx" => 3)

"Yao's block for one gate: qubits are already 1-based."
function yao_gate(n, name, qs, ps)
    fixed = Dict("id" => G.I2, "x" => G.X, "y" => G.Y, "z" => G.Z, "h" => G.H,
                 "s" => G.S, "sdg" => G.Sdag, "t" => G.T, "tdg" => G.Tdag)
    haskey(fixed, name) && return Yao.put(n, qs[1] => fixed[name])
    q = qs[1]
    name == "sx" && return Yao.chain(n, Yao.put(q => Yao.Rx(π / 2)), Yao.put(q => Yao.phase(π / 4)))
    name == "rx" && return Yao.put(n, q => Yao.Rx(ps[1]))
    name == "ry" && return Yao.put(n, q => Yao.Ry(ps[1]))
    name == "rz" && return Yao.put(n, q => Yao.Rz(ps[1]))
    name == "p"  && return Yao.put(n, q => Yao.shift(ps[1]))
    # U(θ, φ, λ) = P(φ) RY(θ) P(λ): apply P(λ) first.
    name == "u"  && return Yao.chain(n, Yao.put(q => Yao.shift(ps[3])), Yao.put(q => Yao.Ry(ps[1])),
                                     Yao.put(q => Yao.shift(ps[2])))
    name == "cx" && return Yao.control(n, qs[1], qs[2] => Yao.X)
    name == "cz" && return Yao.control(n, qs[1], qs[2] => Yao.Z)
    name == "cp" && return Yao.control(n, qs[1], qs[2] => Yao.shift(ps[1]))
    name == "swap" && return Yao.swap(n, qs[1], qs[2])
    name == "ccx" && return Yao.control(n, (qs[1], qs[2]), qs[3] => Yao.X)
    error("unknown gate $name")
end

"Build a Yao circuit from the text format (its own tokenizer, not QSim's parser)."
function to_yao(text)
    n = 0; blocks = Any[]
    for raw in split(text, '\n')
        line = strip(first(split(raw, '#')))
        isempty(line) && continue
        tok = split(line)
        if tok[1] == "n"
            n = parse(Int, tok[2]); continue
        end
        name = String(tok[1])
        if name == "mcz"
            k = parse(Int, tok[2]); qs = [parse(Int, t) + 1 for t in tok[3:2+k]]
            push!(blocks, k == 1 ? Yao.put(n, qs[1] => Yao.Z) :
                                   Yao.control(n, Tuple(qs[1:end-1]), qs[end] => Yao.Z))
            continue
        end
        k = get(ARITY, name, 1)
        qs = [parse(Int, t) + 1 for t in tok[2:1+k]]
        ps = [parse(Float64, t) for t in tok[2+k:end]]
        push!(blocks, yao_gate(n, name, qs, ps))
    end
    return n, Yao.chain(n, blocks...)
end

function yao_state(text)
    n, c = to_yao(text)
    reg = Yao.apply!(Yao.zero_state(n), c)
    return vec(Yao.state(reg))
end

# A circuit QSim throws on counts as a mismatch (Inf), not a crash of this script.
function qsim_state(text)
    try
        QSim.run_circuit(QSim.parse_circuit(text))
    catch err
        println(stderr, "  QSim threw: ", sprint(showerror, err))
        fill(complex(Inf), 0)
    end
end
maxdiff(a, b) = size(a) == size(b) ? maximum(abs.(a .- b)) : Inf

function random_circuit_text(rng)
    n = rand(rng, 1:6)
    lines = ["n $n"]
    for _ in 1:rand(rng, 5:59)
        kinds = ["1q", "1qp"]
        n ≥ 2 && append!(kinds, ["2q", "cp"])
        n ≥ 3 && append!(kinds, ["ccx", "mcz"])
        kind = rand(rng, kinds)
        if kind == "1q"
            push!(lines, "$(rand(rng, ONE_Q)) $(rand(rng, 0:n-1))")
        elseif kind == "1qp"
            g, np = rand(rng, ONE_Q_PARAM)
            ps = join((repr(4π * rand(rng) - 2π) for _ in 1:np), ' ')
            push!(lines, "$g $(rand(rng, 0:n-1)) $ps")
        elseif kind == "2q"
            a, b = randperm(rng, n)[1:2] .- 1
            push!(lines, "$(rand(rng, ["cx", "cz", "swap"])) $a $b")
        elseif kind == "cp"
            a, b = randperm(rng, n)[1:2] .- 1
            push!(lines, "cp $a $b $(repr(4π * rand(rng) - 2π))")
        elseif kind == "ccx"
            a, b, c = randperm(rng, n)[1:3] .- 1
            push!(lines, "ccx $a $b $c")
        else
            k = rand(rng, 1:n)
            push!(lines, "mcz $k " * join(randperm(rng, n)[1:k] .- 1, ' '))
        end
    end
    return join(lines, '\n') * '\n'
end

failures = String[]
function report(label, ok, detail = "")
    println("  [", ok ? "PASS" : "FAIL", "] ", label, isempty(detail) ? "" : "  ($detail)")
    ok || push!(failures, label)
end

nrandom = isempty(ARGS) ? 500 : parse(Int, ARGS[1])
println("Yao ", pkgversion(Yao), ", Julia ", VERSION)

println("-- A. random circuits ---------------------------------")
rng = MersenneTwister(1234)
worst, nbad, ngates = 0.0, 0, 0
for i in 1:nrandom
    t = random_circuit_text(rng)
    err = maxdiff(yao_state(t), qsim_state(t))
    global worst = max(worst, err)
    global ngates += count(==('\n'), t) - 1
    if err > ATOL
        global nbad += 1
        nbad ≤ 3 && println("    mismatch:\n", t)
    end
end
report("$nrandom random circuits ($ngates gates) match Yao amplitude-for-amplitude", nbad == 0,
       "worst |d| = $(round(worst; sigdigits=2)), mismatches = $nbad")

println("-- B. lesson circuits ----------------------------------")
lessons = lesson_circuits()
drift = lesson_drift(lessons)
report("lesson circuits rebuilt from the reference equal lesson_circuits/", isempty(drift),
       isempty(drift) ? "" : "differ: " * join(drift, ", "))
for (name, c) in lessons
    err = maxdiff(yao_state(circuit_text(c)), qsim_state(circuit_text(c)))
    report(name, err < ATOL, "|d| = $(round(err; sigdigits=2))")
end

println()
println(isempty(failures) ? "ALL YAO CROSS-CHECKS PASSED" : "$(length(failures)) CROSS-CHECKS FAILED")
exit(isempty(failures) ? 0 : 1)
