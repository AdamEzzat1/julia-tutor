# Tests for programs (src/programs.jl, docs/PROGRAMS.md): the sealed bundle,
# the hint cap, the reveal gate and the course manifest's `programs`.
# Included from runtests.jl; nothing here runs student code.

using JuliaTutor: Programs, Guided, Course
using Random, TOML

@testset "programs: sealing" begin
    k = rand(Random.Xoshiro(7), UInt8, 32)          # a test key; the stream only has to be fixed here
    plain = Vector{UInt8}(codeunits("files = {\"a.jl\" = \"x = 1\\n\"}\n" ^ 40))
    sealed = Programs.encrypt(plain, k)
    @test startswith(sealed, Programs.MAGIC * "\n")
    @test Programs.decrypt(sealed, k) == plain
    @test Programs.encrypt(plain, k) == sealed                  # deterministic: `seal --check` can compare
    @test !occursin("x = 1", sealed)
    @test Programs.decrypt(replace(sealed, "\n" => "\r\n"), k) == plain   # a CRLF checkout still opens
    # Another key, or one changed character, is refused before anything is decrypted.
    k2 = copy(k); k2[1] ⊻= 0x01
    @test_throws ErrorException Programs.decrypt(sealed, k2)
    lines = split(sealed, '\n')
    lines[5] = (lines[5][1] == 'A' ? "B" : "A") * lines[5][2:end]
    @test_throws ErrorException Programs.decrypt(join(lines, "\n"), k)
    @test_throws ErrorException Programs.decrypt("not sealed\n", k)
    # The two streams for different nonces differ (the nonce is part of each block).
    @test Programs.keystream_xor(k, zeros(UInt8, 16), zeros(UInt8, 64)) !=
          Programs.keystream_xor(k, ones(UInt8, 16), zeros(UInt8, 64))
end

@testset "programs: the key" begin
    withenv(Programs.KEY_ENV => "zz") do
        @test_throws ErrorException Programs.key()
    end
    withenv(Programs.KEY_ENV => repeat("ab", 32)) do
        @test Programs.key() == fill(0xab, 32)
    end
    # The committed self-study key opens the committed bundles (self-study mode).
    withenv(Programs.KEY_ENV => nothing) do
        @test length(Programs.key()) == 32
        for n in Programs.program_names()
            files = Programs.unseal(n)
            @test haskey(files, "mutants.toml") && any(startswith("reference/src/"), keys(files))
            @test any(startswith("acceptance/"), keys(files))
        end
    end
end

@testset "programs: names, meta, hint cap" begin
    @test Programs.is_program("interval")
    @test !Programs.is_program("tidy") && !Programs.is_program("../interval") && !Programs.is_program("Interval")
    @test_throws ErrorException Programs.program_dir("../x")
    m = Programs.program_meta("interval")
    @test m.course == "core" && m.hint_cap == 1
    @test Programs.cap_levels(Dict("acc:a" => 3, "test:a" => 1, "acc:b" => 2), 1) == Dict("acc:a" => 1, "test:a" => 1, "acc:b" => 1)
    @test Programs.cap_levels(Dict("acc:a" => 3), 2) == Dict("acc:a" => 2)
    # No guided project shares a program's name (student folders record the name only).
    for n in Programs.program_names()
        @test !isfile(joinpath(Guided.GUIDED_DIR, n, "project.toml"))
    end
end

@testset "programs: the interval program loads as a guided project" begin
    p = Programs.load_program("interval")
    @test p.package == "TinyIntervals" && p.env == "base" && p.status == "ready"
    @test [m.id for m in p.milestones] == 0:4
    @test Guided.validate(p) == String[]
    @test length(p.mutants) >= 20
    @test all(m -> m.id == 0 || !isempty(m.must_cover), p.milestones)
    # The site data has the spec, never the sealed files.
    d = Guided.site_data(; programs = [p])
    e = only(x for x in d["projects"] if x["name"] == "interval")
    @test e["kind"] == "program"
    @test all(x -> x["kind"] == "guided", (x for x in d["projects"] if x["name"] != "interval"))
    txt = sprint(io -> TOML.print(io, Dict("x" => e)))
    @test !occursin("pow_down", txt) && !occursin("# Acceptance, milestone", txt)
end

@testset "programs: reveal only after every milestone" begin
    p = Programs.load_program("interval")
    mktempdir() do dir
        key = Guided.statekey(p, dir)
        none = Dict{String,Any}()
        ok, msg = Programs.reveal(p, dir, none)
        @test !ok && occursin("milestones 0, 1, 2, 3, 4", msg) && !isdir(joinpath(dir, "solution"))
        some = Dict{String,Any}("projects" => Dict{String,Any}(key => Dict{String,Any}("passed" => [0, 1, 2, 3])))
        ok, msg = Programs.reveal(p, dir, some)
        @test !ok && occursin("milestone 4 of interval has not passed", msg)
        # Passed in another folder does not count for this one.
        other = Dict{String,Any}("projects" => Dict{String,Any}(Guided.statekey(p, joinpath(dir, "x")) => Dict{String,Any}("passed" => collect(0:4))))
        @test !first(Programs.reveal(p, dir, other))
        all_ = Dict{String,Any}("projects" => Dict{String,Any}(key => Dict{String,Any}("passed" => collect(0:4))))
        ok, msg = Programs.reveal(p, dir, all_)
        @test ok
        @test isfile(joinpath(dir, "solution", "src", "TinyIntervals.jl"))
        @test isfile(joinpath(dir, "solution", "test", "m4.jl")) && isfile(joinpath(dir, "solution", "README.md"))
        @test !isdir(joinpath(dir, "solution", "acceptance"))        # the hidden tests stay hidden
        ok, msg = Programs.reveal(p, dir, all_)                       # never overwrites
        @test !ok && occursin("refusing", msg)
    end
end

@testset "programs: course manifests" begin
    courses = Course.load_courses()
    units = Course.load_course()
    core = only(c for c in courses if c.id == "core")
    @test core.programs == ["interval"]
    @test any(o -> "program:interval" in o.assessed_by, core.outcomes)
    @test !any(o -> "interval arithmetic program" in o.planned, core.outcomes)
    @test Course.validate_courses(courses, units) == String[]
    info = Dict("interval" => ("base", "science"))
    @test any(contains("program interval names course 'science'"), Course.validate_courses(courses, units; programs = info))
    # A manifest that names a missing program, and one that drops a program.
    c2 = Course.CourseInfo(core.id, core.title, core.order, core.status, core.summary, core.requires, core.envs, core.units,
                           core.projects, core.guided, core.outcomes, core.download, core.download_measured, core.status_note,
                           ["interval", "ghost"])
    cs = [c.id == "core" ? c2 : c for c in courses]
    @test any(contains("course core: no program ghost"), Course.validate_courses(cs, units))
    c3 = Course.CourseInfo(core.id, core.title, core.order, core.status, core.summary, core.requires, core.envs, core.units,
                           core.projects, core.guided, core.outcomes, core.download, core.download_measured, core.status_note)
    @test any(contains("program interval belongs to 0 courses"), Course.validate_courses([c.id == "core" ? c3 : c for c in courses], units))
end
