# The sandbox image for the course "Scientific ML": the base image's runtime
# plus this course's environments (course/courses/sciml.toml, envs).
# `./tutor sandbox build sciml` builds sandbox/base.Dockerfile's `runtime`
# stage first and passes it in as RUNTIME; `./tutor sandbox pull sciml`
# fetches the published image instead. test/course_tests.jl checks that this
# file installs exactly the course's environments.
ARG RUNTIME
FROM ${RUNTIME}

COPY envs/sciml /tutor/envs/sciml
RUN umask 022 && export JULIA_CPU_TARGET="$(cat /tutor/cpu-target)" && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/sciml && rm -rf /depot/logs
# Offline loading needs no registry (and a stale one only misleads).
RUN rm -rf /depot/registries

COPY child /tutor/child
USER 1000:1000
WORKDIR /tmp
