# Cross-course prerequisite graph for the proposed course split (docs/COURSES_PLAN.md).
# Generated from the units' `prerequisites`; Phase 1 moves the mapping into
# course/courses/*.toml and this report into `tutor courses`.
# Run: julia_pinned --project=. scripts/course_graph.jl
using JuliaTutor: Course

const SPLIT = [("core", 1:20), ("science", 21:29), ("scicomp", 30:42), ("sciml", 43:48)]
num(id) = parse(Int, id[1:2])
course_of(id) = first(c for (c, r) in SPLIT if num(id) in r)

units = Course.load_course()
pre = Dict(u.id => u.prerequisites for u in units)
function closure(id)
    seen = Set{String}(); stack = copy(pre[id])
    while !isempty(stack)
        p = pop!(stack); p in seen && continue
        push!(seen, p); append!(stack, pre[p])
    end
    seen
end

println("Direct prerequisites that cross a course boundary:")
for u in units, p in u.prerequisites
    course_of(p) == course_of(u.id) && continue
    println("  ", course_of(u.id), "/", u.id, "  <-  ", course_of(p), "/", p)
end
println("\nUnits each course needs from other courses (transitive closure):")
for (c, _) in SPLIT
    need = sort!(unique([p for u in units if course_of(u.id) == c for p in closure(u.id) if course_of(p) != c]))
    byc = Dict{String,Vector{String}}()
    for p in need; push!(get!(byc, course_of(p), String[]), p); end
    println("  ", c, ": ", isempty(need) ? "none" :
            join(["$k ($(length(v))): $(join(v, ", "))" for (k, v) in sort(collect(byc))], "; "))
end
