#=
The nine lesson circuits, rebuilt from the CURRENT reference's builders
(included by export.jl and yao_diff.jl, after QSim's names are in scope).

teleport_deferred and ansatz are copied from reference/test/runtests.jl.
lesson_drift compares each rebuilt circuit with the text the original lessons
exported (lesson_circuits/*.txt): a difference means the circuit the course
teaches is no longer the one that was checked. The diffs report drift as a
failure AND still compare the rebuilt circuits, so a changed builder is both
named and checked numerically.
=#
const GOLDEN = joinpath(@__DIR__, "lesson_circuits")

function teleport_deferred(ang)
    c = Circuit(3)
    add!(c, :u, 0; θ = ang[1], φ = ang[2], λ = ang[3])
    bell_pair!(c, 1, 2)
    add!(c, :cx, 0, 1); add!(c, :h, 0)
    add!(c, :cx, 1, 2); add!(c, :cz, 0, 2)
    return c
end

function ansatz(θ::AbstractVector, L::Integer)
    c = Circuit(2); i = 0
    for _ in 1:L
        add!(c, :ry, 0; t = θ[i+=1]); add!(c, :ry, 1; t = θ[i+=1]); add!(c, :cx, 0, 1)
    end
    add!(c, :ry, 0; t = θ[i+=1]); add!(c, :ry, 1; t = θ[i+=1])
    return c
end

lesson_circuits() = [
    "lesson01_rotations" => let c = Circuit(1)
        add!(c, :h, 0); add!(c, :t, 0); add!(c, :sx, 0)
        add!(c, :u, 0; θ = 0.3, φ = 1.1, λ = -0.4); c
    end,
    "lesson02_ghz5" => ghz_circuit(5),
    "lesson03_teleport_deferred" => teleport_deferred((1.234, 0.567, 2.89)),
    "lesson04_bv_s10110" => bv_circuit(5, 0b10110),
    "lesson05_grover_n4" => grover_circuit(4, [5], 3),
    "lesson05_grover_n5_M3" => grover_circuit(5, [3, 17, 30], grover_iterations(5, 3)),
    "lesson06_qft_n5" => let c = Circuit(5)
        add!(c, :x, 0); add!(c, :x, 2); qft!(c, collect(0:4)); c
    end,
    "lesson07_qpe_t5" => qpe_circuit(5, 0.3),
    "lesson09_ansatz" => ansatz([0.1, -0.7, 1.3, 2.2, -0.4, 0.9], 2),
]

"Names of the rebuilt circuits whose text differs from lesson_circuits/ (errors if the sets differ)."
function lesson_drift(lessons)
    goldens = sort(filter(endswith(".txt"), readdir(GOLDEN)))
    sort([n * ".txt" for (n, _) in lessons]) == goldens ||
        error("lesson_circuits/ and lessons.jl name different circuits")
    return [n for (n, c) in lessons if circuit_text(c) != read(joinpath(GOLDEN, n * ".txt"), String)]
end
