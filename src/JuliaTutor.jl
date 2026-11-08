"""
    JuliaTutor

A symbolic (rule-based, deterministic, no LLM in the loop) tutor for Julia.

Components: `Syntax` (JuliaSyntax helpers + scope resolver), `Checker`
(misconception rules), `Scaffold` (holes cut from reference solutions),
`Runner` (subprocess test runs), `Models` (BKT, SM-2, Ochiai), `Explain`
(joins tests, findings, measurements and the test-to-hole map), `Lessons`
(predict-the-output checks with verified answer keys), `Progress` (BKT over
time from lessons and hole attempts).
"""
module JuliaTutor

const ROOT = normpath(joinpath(@__DIR__, ".."))
const PINNED_JULIA = VersionNumber(strip(read(joinpath(ROOT, "JULIA_VERSION"), String)))

"""Refuse to run on any Julia but the pinned release (invariant 4)."""
function check_julia_version(; strict::Bool = true)
    VERSION == PINNED_JULIA && return true
    msg = "julia-tutor is pinned to Julia $(PINNED_JULIA) but is running on $(VERSION). " *
          "Run through `tutor` (it calls `julia +$(PINNED_JULIA)`), or see CLAUDE.md, \"Upgrading Julia\"."
    strict ? error(msg) : (@warn msg; false)
end

include("syntax.jl")
include("checker.jl")
include("models.jl")
include("scaffold.jl")
include("runner.jl")
include("holemap.jl")
include("progress.jl")
include("explain.jl")
include("fixtures.jl")
include("lessons.jl")
include("sitedata.jl")

end # module
