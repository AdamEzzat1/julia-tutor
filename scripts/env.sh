# Source me: pins the Julia release, depot and thread counts for every tool run.
TUTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# TUTOR_DEPOT, if set, replaces the repo-local depot. On Windows a checkout
# under a long path cannot hold some packages (file paths over 260 characters,
# e.g. the sciml env), so point it at a short directory and instantiate there.
export JULIA_DEPOT_PATH="${TUTOR_DEPOT:-$TUTOR_ROOT/.depot}"
export JULIA_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export JULIA_PKG_OFFLINE=true
JULIA_PIN="$(cat "$TUTOR_ROOT/JULIA_VERSION")"
julia_pinned() { julia "+$JULIA_PIN" --startup-file=no --history-file=no --threads=1 "$@"; }
