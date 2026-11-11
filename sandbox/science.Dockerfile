# The sandbox image for the course "Julia for science": the base image's
# runtime plus this course's environments (course/courses/science.toml, envs).
# `./tutor sandbox build science` builds sandbox/base.Dockerfile's `runtime`
# stage first and passes it in as RUNTIME; `./tutor sandbox pull science`
# fetches the published image instead. test/course_tests.jl checks that this
# file installs exactly the course's environments.
ARG RUNTIME
FROM ${RUNTIME}

# Python for the PythonCall unit: Debian's interpreter and NumPy, so nothing is
# downloaded when the code runs (CondaPkg would fetch Python at first use, and
# the container has no network). PythonCall also loads libpython, which Debian
# ships apart from the interpreter (python3 is 3.13 in this Debian 13 base).
RUN apt-get update \
 && apt-get install -y --no-install-recommends python3 python3-numpy libpython3.13 \
 && rm -rf /var/lib/apt/lists/*

ENV JULIA_CONDAPKG_BACKEND=Null \
    JULIA_PYTHONCALL_EXE=/usr/bin/python3 \
    GKSwstype=100

# One layer per environment, smallest first, each copied on its own: changing
# one Manifest rebuilds that layer and the ones after it, not all of them.
COPY envs/data /tutor/envs/data
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/data && rm -rf /depot/logs
COPY envs/python /tutor/envs/python
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/python && rm -rf /depot/logs
COPY envs/calculus /tutor/envs/calculus
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/calculus && rm -rf /depot/logs
COPY envs/optim /tutor/envs/optim
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/optim && rm -rf /depot/logs
COPY envs/turing /tutor/envs/turing
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/turing && rm -rf /depot/logs
COPY envs/diffeq /tutor/envs/diffeq
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/diffeq && rm -rf /depot/logs
COPY envs/ml /tutor/envs/ml
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/ml && rm -rf /depot/logs
COPY envs/plots /tutor/envs/plots
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/plots && rm -rf /depot/logs
# Offline loading needs no registry (and a stale one only misleads).
RUN rm -rf /depot/registries

COPY child /tutor/child
USER 1000:1000
WORKDIR /tmp
