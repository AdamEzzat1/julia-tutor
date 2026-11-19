# Programs (docs/PROGRAMS.md): guided-format projects the learner builds
# alone after a course. They differ from guided projects in two ways:
#
# * The reference, the acceptance tests, the mutants and the fixtures are
#   sealed in `projects/programs/<p>/sealed.txt` (an encrypted bundle), so
#   browsing the repository does not show the solution. `reveal` writes the
#   reference into the learner's folder once their last milestone passed.
# * A check shows at most `[program] hint_cap` hint levels (1 by default).
#
# The lock is a speed bump against accidental spoilers, not security: in
# self-study mode the key is in the repository (`self-study.key`) because the
# tutor on the learner's machine needs the reference to run their tests
# against it. Cohort mode seals with a key given in JULIA_TUTOR_PROGRAM_KEY
# and kept out of the learner's copy (docs/PROGRAMS.md, "Modes").
#
# Cipher, stdlib only: keystream block i = SHA-256(key || nonce || i), XORed
# with the plaintext; tag = HMAC-SHA-256(key, nonce || ciphertext), checked
# before anything is decrypted. The nonce is the first 16 bytes of the
# plaintext's SHA-256, so sealing the same files twice gives the same bytes
# and `seal --check` can compare.

module Programs

using TOML, SHA, Base64
using ..Guided

export load_program, load_all_programs, is_program, seal, unseal, reveal

const PROGRAMS_DIR = normpath(joinpath(@__DIR__, "..", "projects", "programs"))
const KEY_FILE = joinpath(PROGRAMS_DIR, "self-study.key")
const KEY_ENV = "JULIA_TUTOR_PROGRAM_KEY"
const SEALED = "sealed.txt"
const PRIVATE = "private"
const MAGIC = "julia-tutor sealed program v1"
# What a bundle holds, relative to the program folder (and to private/).
const SEALED_PATHS = ("reference", "acceptance", "fixtures", "mutants.toml", "fixtures.toml")

# ---- the cipher ----------------------------------------------------------------------

"""The sealing key: JULIA_TUTOR_PROGRAM_KEY (64 hex digits) if set, else self-study.key."""
function key()
    s = haskey(ENV, KEY_ENV) ? ENV[KEY_ENV] : (isfile(KEY_FILE) ? read(KEY_FILE, String) : "")
    s = strip(s)
    occursin(r"^[0-9a-f]{64}$", s) ||
        error(isempty(s) ? "no program key: neither $KEY_ENV nor $KEY_FILE is set" :
                           "the program key must be 64 lowercase hex digits")
    return hex2bytes(s)
end

function keystream_xor(k::Vector{UInt8}, nonce::Vector{UInt8}, data::Vector{UInt8})
    out = similar(data)
    block = UInt8[]
    for i in eachindex(data)
        j = i - firstindex(data)
        j % 32 == 0 && (block = sha256(vcat(k, nonce, reinterpret(UInt8, [htol(UInt64(j ÷ 32))]))))
        out[i] = data[i] ⊻ block[j % 32 + 1]
    end
    return out
end

"""Encrypt `plain` to the sealed text format."""
function encrypt(plain::Vector{UInt8}, k::Vector{UInt8} = key())
    nonce = sha256(plain)[1:16]
    ct = keystream_xor(k, nonce, plain)
    tag = hmac_sha256(k, vcat(nonce, ct))
    b64 = base64encode(ct)
    lines = [b64[i:min(i + 75, end)] for i in 1:76:length(b64)]
    return join(vcat(MAGIC, "nonce: " * bytes2hex(nonce), "tag: " * bytes2hex(tag), lines), "\n") * "\n"
end

"""Decrypt a sealed text; errors when the tag does not match (wrong key or edited file)."""
function decrypt(text::AbstractString, k::Vector{UInt8} = key())
    ls = split(replace(text, "\r\n" => "\n"), '\n'; keepempty = false)
    (length(ls) >= 3 && ls[1] == MAGIC && startswith(ls[2], "nonce: ") && startswith(ls[3], "tag: ")) ||
        error("not a sealed program file")
    nonce = hex2bytes(ls[2][8:end]); tag = hex2bytes(ls[3][6:end])
    ct = base64decode(join(ls[4:end]))
    hmac_sha256(k, vcat(nonce, ct)) == tag ||
        error("the sealed file does not match the key (sealed with another key, or edited)")
    return keystream_xor(k, nonce, ct)
end

# ---- bundles -------------------------------------------------------------------------

program_dir(name) = (occursin(r"^[a-z][a-z0-9_-]*$", name) || error("not a program name: $(repr(name))");
                     joinpath(PROGRAMS_DIR, name))
is_program(name) = occursin(r"^[a-z][a-z0-9_-]*$", name) && isfile(joinpath(PROGRAMS_DIR, name, "project.toml"))

"""The author's plain files under private/ (relative path => text), or `nothing` without private/."""
function private_files(name)
    base = joinpath(program_dir(name), PRIVATE)
    isdir(base) || return nothing
    out = Dict{String,String}()
    for top in SEALED_PATHS
        p = joinpath(base, top)
        if isfile(p)
            out[top] = replace(read(p, String), "\r\n" => "\n")
        elseif isdir(p)
            for (r, _, fs) in walkdir(p), f in fs
                rel = replace(relpath(joinpath(r, f), base), '\\' => '/')
                out[rel] = replace(read(joinpath(r, f), String), "\r\n" => "\n")
            end
        end
    end
    return out
end

function pack(files::Dict{String,String})
    io = IOBuffer()
    TOML.print(io, Dict("files" => files); sorted = true)
    return take!(io)
end

"""The sealed text for `name` from its private/ files."""
function sealed_text(name)
    files = private_files(name)
    files === nothing && error("$name has no $(PRIVATE)/ folder to seal (only the author has it)")
    return encrypt(pack(files))
end

"""Write projects/programs/<name>/sealed.txt from private/. Returns the path."""
function seal(name)
    path = joinpath(program_dir(name), SEALED)
    write(path, sealed_text(name))
    return path
end

"""Whether sealed.txt holds exactly private/ (true when there is no private/ to compare)."""
function seal_current(name)
    private_files(name) === nothing && return true
    path = joinpath(program_dir(name), SEALED)
    return isfile(path) && replace(read(path, String), "\r\n" => "\n") == sealed_text(name)
end

"""The sealed files of `name` (relative path => text)."""
function unseal(name)
    path = joinpath(program_dir(name), SEALED)
    isfile(path) || error("program $name has no $SEALED")
    d = TOML.parse(String(decrypt(read(path, String))))
    return Dict{String,String}(String(k) => String(v) for (k, v) in d["files"])
end

# ---- loading as a guided project -------------------------------------------------------

const ROOTS = Dict{String,String}()

"""
A temporary folder laid out like projects/guided/ with `name` unsealed in it
(project.toml, data/ and the sealed files), once per process.
"""
function materialize(name)
    get!(ROOTS, name) do
        root = mktempdir()
        dir = joinpath(root, name)
        mkpath(dir)
        src = program_dir(name)
        cp(joinpath(src, "project.toml"), joinpath(dir, "project.toml"))
        isdir(joinpath(src, "data")) && cp(joinpath(src, "data"), joinpath(dir, "data"))
        for (rel, text) in unseal(name)
            p = joinpath(dir, rel)
            mkpath(dirname(p)); write(p, text)
        end
        root
    end
end

"""Load program `name` as a `Guided.GuidedProject` (reference unsealed into a temp folder)."""
load_program(name) = Guided.load_guided(name; root = materialize(name))

program_names() = isdir(PROGRAMS_DIR) ? sort!([n for n in readdir(PROGRAMS_DIR) if is_program(n)]) : String[]
load_all_programs() = [load_program(n) for n in program_names()]

"""The `[program]` table and `course` of a program's project.toml."""
function program_meta(name)
    d = TOML.parsefile(joinpath(program_dir(name), "project.toml"))
    t = get(d, "program", Dict{String,Any}())
    return (course = String(get(d, "course", "")), follows = String(get(t, "follows", "")),
            hint_cap = Int(get(t, "hint_cap", 1)))
end

"""Hint levels capped at the program's `hint_cap` (pure)."""
cap_levels(levels::AbstractDict, cap::Integer) = Dict{String,Int}(k => min(v, cap) for (k, v) in levels)

"""
`Guided.check` for a program: the same check, with hint levels (from the
state and from `--hints`) capped at `hint_cap`.
"""
function check(p::Guided.GuidedProject, dir::String, m::Int; levels = Dict{String,Int}(), hints::Int = 0)
    cap = program_meta(p.name).hint_cap
    r, findings = Guided.check(p, dir, m; levels = cap_levels(levels, cap), hints = min(hints, cap))
    return r, findings
end

# ---- reveal ----------------------------------------------------------------------------

"""
Write the reference into `dir/solution/` when the state records every
milestone of `p` as passed for `dir`. Returns (ok, message).
"""
function reveal(p::Guided.GuidedProject, dir::String, state)
    key_ = Guided.statekey(p, dir)
    passed = Set(Int.(get(get(get(state, "projects", Dict()), key_, Dict()), "passed", Int[])))
    missing_ = [m.id for m in p.milestones if !(m.id in passed)]
    isempty(missing_) ||
        return (false, "Not yet: milestone$(length(missing_) == 1 ? "" : "s") $(join(missing_, ", ")) " *
                       "of $(p.name) $(length(missing_) == 1 ? "has" : "have") not passed for $dir " *
                       "(`tutor program check $dir`). The reference stays sealed until all have.")
    out = joinpath(dir, "solution")
    isdir(out) && !isempty(readdir(out)) && return (false, "refusing: $out exists and is not empty")
    files = Guided.reference_files(p)
    for rel in sort!(collect(keys(files)))
        path = joinpath(out, rel)
        mkpath(dirname(path)); write(path, files[rel])
    end
    write(joinpath(out, "README.md"),
          "# The reference for $(p.title)\n\nWritten by `tutor program reveal` after every milestone passed. " *
          "`src/` is the reference package; `test/m<k>.jl` are example test suites per milestone. " *
          "Compare with your own code: where do they differ, and does each difference matter?\n")
    return (true, "Wrote the reference to $out ($(length(files)) files).")
end

end # module Programs
