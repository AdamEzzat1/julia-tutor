# Entry point inside the sandbox container (src/runner.jl, `run_contained`).
#
# stdin: TOML with `files` (name => content) and `args` (sandbox.jl's
# arguments, naming those files). The files are written to a fresh directory
# under /tmp (the only writable place), sandbox.jl's `main` runs there, and
# afterwards the files it created are printed between two marker lines, after
# everything the code printed, base64-encoded (a figure is binary, and TOML
# strings must be UTF-8). Nothing is mounted from the host.

const FILES_BEGIN = "<<<julia-tutor-files-begin>>>"
const FILES_END = "<<<julia-tutor-files-end>>>"

import Base64     # `import`, not `using`: nothing exported lands in the learner's Main
include(joinpath(@__DIR__, "sandbox.jl"))   # defines `TutorChild`; does not run it (not the program file)

# A function, so its variables are locals: the learner's code runs in Main
# (REPL semantics) and must not be able to rebind them.
function contained_main()
    req = TutorChild.TOML.parse(read(stdin, String))
    work = mkpath(joinpath(tempdir(), "work"))
    given = Set{String}()
    for (name, content) in req["files"]
        name == basename(name) || error("bad file name $name")
        write(joinpath(work, name), content)
        push!(given, name)
    end
    cd(work)
    rc = try
        TutorChild.main(String.(req["args"]))
    catch e
        e isa InterruptException && rethrow()
        println("ERROR: the sandbox child failed: ", sprint(showerror, e))
        2
    end
    out = Dict(n => Base64.base64encode(read(n)) for n in readdir(work) if !(n in given) && isfile(n))
    flush(stdout); flush(stderr)
    print(stdout, "\n", FILES_BEGIN, "\n")
    TutorChild.TOML.print(stdout, out)
    print(stdout, FILES_END, "\n")
    flush(stdout)
    return rc
end

exit(contained_main())
