# Wrapper: pinned Julia (via juliaup), repo-local depot, one thread, offline Pkg.
$root = $PSScriptRoot
$pin = (Get-Content (Join-Path $root "JULIA_VERSION") -Raw).Trim()
$env:JULIA_DEPOT_PATH = Join-Path $root ".depot"
$env:JULIA_NUM_THREADS = "1"
$env:OPENBLAS_NUM_THREADS = "1"
$env:JULIA_PKG_OFFLINE = "true"
& julia "+$pin" --startup-file=no --history-file=no --threads=1 "--project=$root" (Join-Path $root "bin/tutor.jl") @args
exit $LASTEXITCODE
