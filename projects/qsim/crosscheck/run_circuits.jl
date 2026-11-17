#=
Simulate every *.txt circuit in a directory with the reference QSim and write
its final statevector next to it as *.state ("re im" per line, `repr` floats):

    julia --project=projects/qsim/reference projects/qsim/crosscheck/run_circuits.jl DIR

A circuit the simulator throws on gets no .state file (the error is printed);
qiskit_diff.py counts it as a mismatch rather than stopping.
=#
using QSim

dir = length(ARGS) == 1 ? ARGS[1] : error("usage: run_circuits.jl DIR")
for f in filter(endswith(".txt"), readdir(dir; join=true))
    ψ = try
        run_circuit(parse_circuit(read(f, String)))
    catch err
        println(stderr, basename(f), ": ", sprint(showerror, err))
        continue
    end
    open(replace(f, r"\.txt$" => ".state"), "w") do io
        for a in ψ
            println(io, repr(real(a)), ' ', repr(imag(a)))
        end
    end
end
