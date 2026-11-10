# The container `tutor serve` runs learner code in (see src/runner.jl,
# `run_contained`, for the flags it is started with: no network, read-only
# root, no capabilities, an unprivileged user, memory/CPU/process limits).
#
# Build with `./tutor sandbox build`. It assembles a context with only this
# file, src/child (as child/) and course/envs (as envs/), and labels the image
# with a hash of them, so `tutor serve` can tell when the image is stale.
# Nothing is mounted at run time: the job arrives on stdin.

# The official image, pinned by digest (julia:1.10.13, linux/amd64 + arm64 index;
# Debian 13).
FROM julia:1.10.13@sha256:6a34b77ca84c433310869ca85d774572bd24569c949fc867ed64ec90ae95526e

# Python for the PythonCall unit: Debian's interpreter and NumPy, so nothing is
# downloaded when the code runs (CondaPkg would fetch Python at first use, and
# the container has no network).
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-numpy \
 && rm -rf /var/lib/apt/lists/*

ENV JULIA_DEPOT_PATH=/depot \
    JULIA_PKG_PRECOMPILE_AUTO=0 \
    JULIA_CONDAPKG_BACKEND=Null \
    JULIA_PYTHONCALL_EXE=/usr/bin/python3 \
    GKSwstype=100

# One layer per environment, smallest first, each copied on its own: changing
# one Manifest rebuilds that layer and the ones after it, not all of them. The
# depot is made readable by the run-time user as it grows (umask 022), with no
# chmod pass at the end, which would copy every file into a new layer.
# test/course_tests.jl checks that every environment is listed here, and
# `tutor sandbox check` loads each one as the unprivileged user.
RUN umask 022 && mkdir -p /depot /tutor/envs
COPY envs/base /tutor/envs/base
COPY envs/data /tutor/envs/data
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/data && rm -rf /depot/logs
COPY envs/python /tutor/envs/python
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/python && rm -rf /depot/logs
COPY envs/calculus /tutor/envs/calculus
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/calculus && rm -rf /depot/logs
COPY envs/optim /tutor/envs/optim
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/optim && rm -rf /depot/logs
COPY envs/turing /tutor/envs/turing
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/turing && rm -rf /depot/logs
COPY envs/diffeq /tutor/envs/diffeq
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/diffeq && rm -rf /depot/logs
COPY envs/ml /tutor/envs/ml
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/ml && rm -rf /depot/logs
COPY envs/plots /tutor/envs/plots
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/plots && rm -rf /depot/logs
COPY envs/sciml /tutor/envs/sciml
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/sciml && rm -rf /depot/logs
# Offline loading needs no registry (and a stale one only misleads).
RUN rm -rf /depot/registries

# PythonCall loads libpython, which Debian ships apart from the interpreter
# (python3 is 3.13 in this pinned Debian 13 base). A separate layer, so adding
# it did not invalidate the package layers above.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpython3.13 \
 && rm -rf /var/lib/apt/lists/*

# Last, so editing the child scripts rebuilds in seconds (packages are cached).
COPY child /tutor/child

USER 1000:1000
WORKDIR /tmp
