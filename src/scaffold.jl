# Scaffolder: cuts holes from a complete reference solution.
#
# Authoring: put `# HOLE: <id>` on its own line directly above a hole's
# docstring (or above the `function` if it has none). Holes must be long-form
# `function ... end` definitions. Metadata lives in `holes.toml`.
#
# The marker is a comment, so it is found by line (comments are trivia, not tree
# nodes). Everything else (which function follows, where its body starts and
# ends) comes from the JuliaSyntax tree, so bodies with nested `end`s, strings
# containing "end", etc. are cut exactly.
#
# An opened hole contains only `error("TODO(hole:<id>)")` and keeps its
# docstring (invariant 5). The starter tree is generated, never hand-edited
# (invariant 6): `tutor scaffold <project> --check` diffs it.

module Scaffold

using TOML
using JuliaSyntax
const JS = JuliaSyntax
using ..Syntax

export HoleSpec, ProjectSpec, load_project, find_holes, render_source, starter_files,
       write_starter, check_starter, hole_body_is_todo

const MARKER = r"^# HOLE: ([a-z][a-z0-9_]*)\s*$"

struct HoleSpec
    id::String
    stage::Int
    kc::String
    file::String                 # relative to the reference package
    summary::String
    trivial_bodies::Vector{String}
end

struct ProjectSpec
    name::String
    dir::String                  # projects/<name>
    package::String              # package/module name
    stages::Vector{Int}
    holes::Vector{HoleSpec}      # in holes.toml order (= teaching order)
end

reference_dir(p::ProjectSpec) = joinpath(p.dir, "reference")
starter_dir(p::ProjectSpec, stage::Int) = joinpath(p.dir, "starter", "stage$stage")

function load_project(dir::AbstractString)
    meta = TOML.parsefile(joinpath(dir, "holes.toml"))
    holes = HoleSpec[]
    for h in meta["hole"]
        push!(holes, HoleSpec(h["id"], h["stage"], h["kc"], h["file"], h["summary"],
                              String.(get(h, "trivial", String[]))))
    end
    ids = [h.id for h in holes]
    allunique(ids) || error("duplicate hole ids in $(dir)/holes.toml")
    return ProjectSpec(meta["project"], String(dir), meta["package"], Int.(meta["stages"]), holes)
end

"""A located hole: marker line range and the function body's byte range."""
struct LocatedHole
    id::String
    marker_first::Int            # byte range of the marker line, incl. newline
    marker_last::Int
    body_first::Int              # byte range to replace (after signature, before `end`)
    body_last::Int
    line::Int                    # line of the `function` keyword (in the reference)
end

function find_holes(src::String, filename::AbstractString)
    tree = JS.parseall(SyntaxNode, src; filename)
    fns = filter(is_long_function, function_nodes(tree))
    sort!(fns; by = JS.first_byte)
    out = LocatedHole[]
    offset = 1
    for line in eachline(IOBuffer(src); keep = true)
        m = match(MARKER, chomp(line))
        start = offset
        offset += ncodeunits(line)
        m === nothing && continue
        idx = findfirst(f -> JS.first_byte(f) > start, fns)
        idx === nothing && error("$filename: `# HOLE: $(m[1])` is not followed by a long-form function")
        fn = fns[idx]
        between = String(codeunits(src)[offset:JS.first_byte(fn)-1])
        if !(isempty(strip(between)) || startswith(lstrip(between), "\"\"\""))
            error("$filename: `# HOLE: $(m[1])` must be directly above the function or its docstring")
        end
        sig = kids(fn)[1]
        push!(out, LocatedHole(m[1], start, offset - 1, JS.last_byte(sig) + 1,
                               JS.last_byte(fn) - 3, nodeline(fn)))
    end
    return out
end

function indent_body(body::AbstractString)
    lines = split(strip(body), '\n')
    return "\n" * join(("    " * rstrip(l) for l in lines), "\n") * "\n"
end

todo_body(id::AbstractString) = "error(\"TODO(hole:$id)\")"

"""
    render_source(src, filename, opened) -> String

`opened` maps hole id => replacement body (use `todo_body(id)` for a starter).
All marker lines are removed; holes not in `opened` keep the reference body.
"""
function render_source(src::String, filename::AbstractString, opened::Dict{String,String})
    holes = find_holes(src, filename)
    edits = Tuple{Int,Int,String}[]
    for h in holes
        push!(edits, (h.marker_first, h.marker_last, ""))
        haskey(opened, h.id) && push!(edits, (h.body_first, h.body_last, indent_body(opened[h.id])))
    end
    sort!(edits; by = first, rev = true)          # apply back to front: offsets stay valid
    bytes = Vector{UInt8}(codeunits(src))
    for (a, b, text) in edits
        bytes = vcat(bytes[1:a-1], Vector{UInt8}(codeunits(text)), bytes[b+1:end])
    end
    return String(bytes)
end

"""Hole ids present in the reference sources, checked against holes.toml."""
function validate(p::ProjectSpec)
    found = Dict{String,String}()
    for h in p.holes
        src = read(joinpath(reference_dir(p), h.file), String)
        ids = [l.id for l in find_holes(src, h.file)]
        h.id in ids || error("hole `$(h.id)` from holes.toml has no `# HOLE:` marker in $(h.file)")
        for id in ids
            found[id] = h.file
        end
    end
    declared = Set(h.id for h in p.holes)
    extra = sort!([id for id in keys(found) if !(id in declared)])
    isempty(extra) || error("markers without a holes.toml entry: $(join(extra, ", "))")
    for h in p.holes
        isempty(h.trivial_bodies) && error("hole `$(h.id)` has no trivial bodies for mutation testing")
    end
    return true
end

"""Source files of the reference package (relative paths, sorted)."""
function package_files(p::ProjectSpec)
    ref = reference_dir(p)
    out = String[]
    for (root, _, files) in walkdir(ref), f in files
        push!(out, replace(relpath(joinpath(root, f), ref), '\\' => '/'))
    end
    return sort!(out)
end

function starter_readme(p::ProjectSpec, stage::Int)
    io = IOBuffer()
    println(io, "# $(p.package): stage $stage (generated, do not edit)")
    println(io)
    println(io, "Generated by `tutor scaffold $(p.name)` from `projects/$(p.name)/reference`.")
    println(io, "Do not edit this directory; copy it with `tutor start $(p.name) $stage <dir>`.")
    println(io)
    println(io, "Holes to fill (each raises `TODO(hole:<id>)` until you do):")
    println(io)
    for h in p.holes
        h.stage <= stage || continue
        println(io, "- `$(h.id)` ($(h.file)): $(h.summary)  [knowledge component: $(h.kc)]")
    end
    println(io)
    println(io, "Run `tutor explain $(p.name) <dir>` to see failing tests, findings and where to start.")
    return String(take!(io))
end

"""In-memory starter tree for `stage`: relative path => contents."""
function starter_files(p::ProjectSpec, stage::Int)
    validate(p)
    opened_by_file = Dict{String,Dict{String,String}}()
    for h in p.holes
        h.stage <= stage || continue
        get!(opened_by_file, h.file, Dict{String,String}())[h.id] = todo_body(h.id)
    end
    files = Dict{String,String}()
    for rel in package_files(p)
        src = read(joinpath(reference_dir(p), rel), String)
        if endswith(rel, ".jl") && startswith(rel, "src/")
            src = render_source(src, rel, get(opened_by_file, rel, Dict{String,String}()))
        end
        files[rel] = src
    end
    files["README.md"] = starter_readme(p, stage)
    files[".tutor-project.toml"] = "# generated by tutor scaffold\nproject = \"$(p.name)\"\nstage = $stage\n"
    return files
end

function write_starter(p::ProjectSpec)
    for stage in p.stages
        dir = starter_dir(p, stage)
        rm(dir; recursive = true, force = true)
        files = starter_files(p, stage)
        for rel in sort!(collect(keys(files)))
            path = joinpath(dir, rel)
            mkpath(dirname(path))
            write(path, files[rel])
        end
    end
end

"""Differences between the generated and the committed starter (empty = up to date)."""
function check_starter(p::ProjectSpec)
    problems = String[]
    for stage in p.stages
        dir = starter_dir(p, stage)
        files = starter_files(p, stage)
        on_disk = String[]
        if isdir(dir)
            for (root, _, fs) in walkdir(dir), f in fs
                push!(on_disk, replace(relpath(joinpath(root, f), dir), '\\' => '/'))
            end
        end
        for rel in sort!(collect(keys(files)))
            path = joinpath(dir, rel)
            if !isfile(path)
                push!(problems, "stage$stage/$rel: missing")
            elseif read(path, String) != files[rel]
                push!(problems, "stage$stage/$rel: differs from generated")
            end
        end
        for rel in sort!(on_disk)
            haskey(files, rel) || push!(problems, "stage$stage/$rel: not generated (hand-added?)")
        end
    end
    return problems
end

"""Whether hole `id` in `src` still has the untouched TODO body."""
function hole_body_is_todo(src::String, filename::AbstractString, id::AbstractString)
    needle = todo_body(id)
    occursin(needle, src) || return false
    tree = JS.parseall(SyntaxNode, src; filename)
    for fn in filter(is_long_function, function_nodes(tree))
        body = kids(fn)[2]
        strip(JS.sourcetext(body)) == needle && return true
    end
    return false
end

"""Line of the function that holds hole `id` in a starter source (by its TODO body)."""
function hole_line(src::String, filename::AbstractString, id::AbstractString)
    tree = JS.parseall(SyntaxNode, src; filename)
    for fn in filter(is_long_function, function_nodes(tree))
        occursin("TODO(hole:$id)", JS.sourcetext(fn)) && return nodeline(fn)
    end
    return nothing
end

end # module Scaffold
