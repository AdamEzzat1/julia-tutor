# One-time: instantiate the pinned environment into the repo-local depot.
using Pkg
Pkg.add([PackageSpec(name="JuliaSyntax"), PackageSpec(name="JET")])
Pkg.instantiate()
Pkg.status()
