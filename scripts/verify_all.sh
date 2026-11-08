#!/usr/bin/env bash
# The definition-of-done check for every milestone. Runs everything that can
# change a verdict: tutor tests, reference tests, starter diff, measured
# test->hole map + mutation tests, measurement baseline, lesson answer keys.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/env.sh
step() { echo; echo "== $* =="; }
step "pinned Julia"
julia_pinned -e 'v = VersionNumber(strip(read("JULIA_VERSION", String))); VERSION == v || error("running $VERSION, pinned $v")'
step "tutor test suite"
julia_pinned --project=. --check-bounds=yes test/runtests.jl
for p in projects/*/; do
  name=$(basename "$p")
  step "$name: reference tests"
  (cd "$p/reference" && julia_pinned --project=. --check-bounds=yes test/runtests.jl)
  step "$name: checker on reference"
  ./tutor check "$p/reference/src" "$p/reference/test"
  step "$name: starter is generated (invariant 6)"
  ./tutor scaffold "$name" --check
  step "$name: measured test->hole map + mutation tests"
  ./tutor holemap "$name" --check
  step "$name: measurement baseline"
  ./tutor baseline "$name" --check
  step "$name: explain on fixtures vs golden outputs"
  ./tutor fixtures "$name" --check
done
step "lesson answer keys"
./tutor lessons verify
echo; echo "ALL CHECKS PASSED"
