# The base sandbox image: Julia, the base environment (stdlib only) and the
# child scripts. Core Julia runs in it, and every course image starts from its
# `runtime` stage (sandbox/<course>.Dockerfile). See src/runner.jl,
# `run_contained`, for the flags a container is started with: no network,
# read-only root, no capabilities, an unprivileged user, memory/CPU/process
# limits.
#
# Build with `./tutor sandbox build core`, or fetch the published one with
# `./tutor sandbox pull core`. The build context holds only this file,
# src/child (as child/) and course/envs/base (as envs/base). The image is
# labelled with a hash of them, so `tutor serve` can tell when it is stale.
# Nothing is mounted at run time: the job arrives on stdin.

# The official image, pinned by digest (julia:1.10.13, linux/amd64 + arm64 index;
# Debian 13).
FROM julia:1.10.13@sha256:6a34b77ca84c433310869ca85d774572bd24569c949fc867ed64ec90ae95526e AS runtime

# Links the published packages (ghcr.io) to the repository. Inherited by every
# course image. It does not by itself let CI's workflow token push: each
# package's "Manage Actions access" must give this repository the Write role
# (docs/SANDBOX_IMAGES.md).
LABEL org.opencontainers.image.source="https://github.com/AdamEzzat1/julia-tutor"

ENV JULIA_DEPOT_PATH=/depot \
    JULIA_PKG_PRECOMPILE_AUTO=0

# The depot is made readable by the run-time user as it grows (umask 022), with
# no chmod pass at the end, which would copy every file into a new layer.
RUN umask 022 && mkdir -p /depot /tutor/envs
COPY envs/base /tutor/envs/base

FROM runtime AS base
# Last, so editing the child scripts rebuilds in seconds.
COPY child /tutor/child
USER 1000:1000
WORKDIR /tmp
