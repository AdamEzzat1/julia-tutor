#=
Export what the Qiskit diff compares, built from the CURRENT reference:

    julia --project=projects/qsim/reference projects/qsim/crosscheck/export.jl OUT

writes OUT/circuits/<lesson circuit>.txt and .state (QSim's final statevector),
OUT/drift.txt (the lesson circuits that differ from lesson_circuits/, one per
line; empty when none do, see lessons.jl), OUT/qft/qft<n>.txt for n = 1..6,
and OUT/noise_ghz3_rho.txt (lesson 8's density matrix, row-major "re im" per
line).
=#
using QSim, LinearAlgebra

out = length(ARGS) == 1 ? ARGS[1] : error("usage: export.jl OUTDIR")
include(joinpath(@__DIR__, "lessons.jl"))

function write_state(path, ψ)
    open(path, "w") do io
        for a in ψ
            println(io, repr(real(a)), ' ', repr(imag(a)))
        end
    end
end

mkpath(joinpath(out, "circuits")); mkpath(joinpath(out, "qft"))
lessons = lesson_circuits()
for (name, c) in lessons
    write(joinpath(out, "circuits", name * ".txt"), circuit_text(c))
    write_state(joinpath(out, "circuits", name * ".state"), run_circuit(c))
end
drift = lesson_drift(lessons)
write(joinpath(out, "drift.txt"), join(drift .* "\n"))

for n in 1:6
    write(joinpath(out, "qft", "qft$n.txt"), circuit_text(qft_circuit(n)))
end

# Lesson 8: GHZ(3), amplitude damping γ = 0.3 on qubit 1, depolarizing p = 0.2 on qubit 2.
depolarizing(p) = [sqrt(1 - 3p / 4) * I2, sqrt(p / 4) * X, sqrt(p / 4) * Y, sqrt(p / 4) * Z]
amp_damping(γ)  = [ComplexF64[1 0; 0 sqrt(1 - γ)], ComplexF64[0 sqrt(γ); 0 0]]
ρ = density_matrix(run_circuit(ghz_circuit(3)))
ρ = apply_kraus(apply_kraus(ρ, amp_damping(0.3), 1), depolarizing(0.2), 2)
write_state(joinpath(out, "noise_ghz3_rho.txt"), vec(permutedims(ρ)))   # row-major

println("exported $(length(lessons)) lesson circuits ($(length(drift)) differ from lesson_circuits/), qft1..6, noise_ghz3_rho")
