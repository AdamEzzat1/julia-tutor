# The sandbox image for the course "Scientific computing": the base image's
# runtime plus this course's environments (course/courses/scicomp.toml, envs).
# `./tutor sandbox build scicomp` builds sandbox/base.Dockerfile's `runtime`
# stage first and passes it in as RUNTIME; `./tutor sandbox pull scicomp`
# fetches the published image instead. test/course_tests.jl checks that this
# file installs exactly the course's environments.
ARG RUNTIME
FROM ${RUNTIME}

COPY envs/scicomp /tutor/envs/scicomp
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/scicomp && rm -rf /depot/logs
COPY envs/mtk /tutor/envs/mtk
RUN umask 022 && julia --startup-file=no -e 'using Pkg; Pkg.activate(ARGS[1]); Pkg.instantiate(); Pkg.precompile()' /tutor/envs/mtk && rm -rf /depot/logs
# Offline loading needs no registry (and a stale one only misleads).
RUN rm -rf /depot/registries

COPY child /tutor/child
USER 1000:1000
WORKDIR /tmp
