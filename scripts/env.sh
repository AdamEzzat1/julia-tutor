# Source me: pins the Julia release, depot and thread counts for every tool run.
TUTOR_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export JULIA_DEPOT_PATH="$TUTOR_ROOT/.depot"
export JULIA_NUM_THREADS=1
export OPENBLAS_NUM_THREADS=1
export JULIA_PKG_OFFLINE=true
JULIA_PIN="$(cat "$TUTOR_ROOT/JULIA_VERSION")"
julia_pinned() { julia "+$JULIA_PIN" --startup-file=no --history-file=no --threads=1 "$@"; }
