#!/usr/bin/env bash
# Times docs/START_CORE.md step by step on a machine that has Docker and git
# but no Julia, no checkout and no images (CI's `clean-start` job, a fresh
# GitHub runner). Each step is the guide's command, run as written; the table
# goes to stdout and to the job summary. The runner's network is a data
# centre's, so a home connection will take longer on the download steps: the
# table says how much each one downloads where that is known.
#
# usage: scripts/clean_start.sh <repo-url> <branch> [images.toml to use]
set -euo pipefail
repo=$1; branch=$2; images=${3:-}
work=$(mktemp -d)
rows=()
secs() { awk "BEGIN{printf \"%.0f\", $2 - $1}"; }
t0=$(date +%s.%N)
step() {   # step "<label>" <command...>
  local label=$1; shift
  local s; s=$(date +%s.%N)
  "$@"
  local e; e=$(date +%s.%N)
  rows+=("| $label | $(secs "$s" "$e") |")
  echo "== $label: $(secs "$s" "$e") s"
}

# Nothing of the tutor may be here already. (GitHub's runner image may carry a
# system Julia; the guide installs juliaup, whose `julia` comes first on PATH,
# and pins 1.10.13, so a system Julia is never used.)
if [ -d "$HOME/.juliaup" ] || [ -d "$HOME/.julia/juliaup" ]; then echo "not a clean machine: juliaup is installed"; exit 1; fi
if docker image ls --format '{{.Repository}}' | grep -q julia-tutor; then echo "not a clean machine: images present"; exit 1; fi

install_julia() {
  curl -fsSL https://install.julialang.org | sh -s -- --yes --default-channel 1.10.13
  export PATH="$HOME/.juliaup/bin:$PATH"
}
clone() { git clone --depth 1 --branch "$branch" "$repo" "$work/julia-tutor"; }
instantiate() {
  cd "$work/julia-tutor"
  # the guide's command; `source scripts/env.sh` pins the depot inside the checkout
  source scripts/env.sh
  JULIA_PKG_OFFLINE=false julia_pinned --project=. -e 'using Pkg; Pkg.instantiate()'
}
pull() {
  # Before the digests are committed (the PR that changes the images), CI hands
  # in the images.toml its own publish step wrote; the pull itself is the same.
  [ -n "$images" ] && cp "$images" sandbox/images.toml
  ./tutor sandbox pull core
}
first_run() {
  # `tutor serve --course=core`, then the website's first Run, as an HTTP
  # request with the token the server wrote (a throwaway token on a throwaway
  # runner, in a file of its own).
  local tok="$work/token"
  ./tutor serve --course=core --token-file="$tok" > "$work/serve.log" 2>&1 &
  local pid=$!
  for _ in $(seq 1 300); do grep -q "Press Ctrl-C" "$work/serve.log" 2>/dev/null && break; sleep 1; done
  grep -q "Press Ctrl-C" "$work/serve.log" || { cat "$work/serve.log"; kill $pid; return 1; }
  local out
  out=$(curl -fsS -H "Host: 127.0.0.1:8749" -H "Authorization: Bearer $(cat "$tok")" \
        -H "Content-Type: application/json" -d '{"code": "println(\"hello from the sandbox\")"}' \
        http://127.0.0.1:8749/api/run)
  kill $pid
  echo "$out"
  echo "$out" | grep -q "hello from the sandbox"
}

step "1. install juliaup and Julia 1.10.13" install_julia
step "2. git clone (depth 1)" clone
step "3. install the tutor's packages" instantiate
step "4. tutor sandbox pull core" pull
step "5. tutor serve --course=core, first Run answered" first_run
t1=$(date +%s.%N)
total=$(secs "$t0" "$t1")

{
  echo
  echo "### Start Core Julia: measured on a clean GitHub runner ($(date -u +%F), $(nproc) CPUs)"
  echo
  echo "| step (docs/START_CORE.md) | seconds |"
  echo "|---|---|"
  printf '%s\n' "${rows[@]}"
  echo "| **total** | **$total** |"
  echo
  echo "Docker was already installed (not timed). Downloads went over the runner's data-centre network."
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"

# The other courses' images, each pulled onto the same machine (which has only
# the base image now, so this is what a Core learner pays to add a course),
# then removed again so the runner's disk holds one course image at a time.
prow=()
for c in scicomp sciml science; do
  s=$(date +%s.%N)
  ./tutor sandbox pull "$c"
  e=$(date +%s.%N)
  # .Size is the compressed content with the containerd image store (this
  # runner's), so the unpacked size is counted in the image, as `tutor sandbox
  # measure` does (src/runner.jl, image_sizes); du exits 1 on apt's mode-700
  # partial/ directory after printing the total, hence `|| true`.
  comp=$(docker image inspect --format '{{.Size}}' "julia-tutor-sandbox-$c:1.10.13")
  disk=$( (docker run --rm --network=none --read-only --cap-drop=ALL --security-opt=no-new-privileges \
            --user=0:0 --entrypoint=du "julia-tutor-sandbox-$c:1.10.13" -sxb / 2>/dev/null || true) | awk '{print $1}')
  prow+=("| $c | $(secs "$s" "$e") | $(awk "BEGIN{printf \"%.2f\", $disk / 1073741824}") GiB | $(awk "BEGIN{printf \"%.2f\", $comp / 1073741824}") GiB |")
  # by id: the image also carries its registry name, which a tag removal would leave
  docker image rm -f "$(docker image inspect --format '{{.Id}}' "julia-tutor-sandbox-$c:1.10.13")" > /dev/null
done
{
  echo
  echo "### Adding a course: \`tutor sandbox pull <course>\` after Core (same runner)"
  echo
  echo "| course | seconds | unpacked size | docker .Size (compressed content here) |"
  echo "|---|---|---|---|"
  printf '%s\n' "${prow[@]}"
} | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
