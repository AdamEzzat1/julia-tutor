# Sandbox images per course (Phase 2)

Until Phase 2 there was one sandbox image holding all twelve course
environments. A Core Julia learner had to build or download every package of
every course before the first Run. Now each course gets its own image.

## Images

| Image | Course | Holds | Dockerfile |
|---|---|---|---|
| `base` | core | Julia 1.10.13, the base env (stdlib only), the child scripts | `sandbox/base.Dockerfile` (stages `runtime`, `base`) |
| `science` | science | base's runtime + Debian's python3/NumPy/libpython + data, python, calculus, optim, turing, diffeq, ml, plots | `sandbox/science.Dockerfile` |
| `scicomp` | scicomp | base's runtime + scicomp, mtk | `sandbox/scicomp.Dockerfile` |
| `sciml` | sciml | base's runtime + sciml | `sandbox/sciml.Dockerfile` |

* **Which image a run uses:** the environment picks the image
  (`Runner.env_image`). Each environment other than base belongs to exactly
  one course, and `Course.validate_courses` fails otherwise. The base env
  runs in the base image.
* **Where the env lists come from:** they are read from the course manifests
  (`course/courses/<id>.toml`, `envs`). A test checks that each course
  Dockerfile copies exactly those environments and nothing else.
* **How course images are built:** each starts from base.Dockerfile's
  `runtime` stage, which is Julia plus the base env without the child scripts.
  Each image copies the child scripts last, so editing them rebuilds seconds
  of layers, not the packages.
* **Staleness labels:** every image is labelled with the hash of exactly what
  it bakes in: both Dockerfiles, `src/child`, and its own environments
  (`Runner.sandbox_hash(img)`). `tutor serve` and `--sandbox=docker` refuse a
  missing or stale image and print the command that fixes it.
* **Shared layers:** layers are shared between images only when the course
  image is built on the same `runtime` image as base. In CI a course image
  rebuilt on its own gets a rebuilt runtime, whose two small layers then have
  different digests from base's. The Julia layers are always shared.

## Package caches for every CPU

* **The problem:** Pkg compiles each package's cache for the CPU of the
  machine that builds the image, unless told otherwise. A CPU without that
  machine's features rejects every cache and recompiles on each Run (every
  Run is a fresh container, so the recompiled code is thrown away). On CI
  run 42998692738, the science image built on one runner made `using
  DataFrames` take 84 s on this repository's authoring machine (2 s when
  built locally), and verify on the next runner timed out at 120 s in unit
  21, twice. The first CI run had passed only because its verify runner
  happened to have a compatible CPU. Julia's debug log names the reason:
  "Rejecting this target due to use of runtime-disabled features".
* **The fix:** every precompile step sets `JULIA_CPU_TARGET` from
  `/tutor/cpu-target`, which base.Dockerfile writes. On x86_64 it is the
  target list of Julia's own release builds,
  `generic;sandybridge,-xsaveopt,clone_all;haswell,-rdrnd,base(1)`: a
  baseline copy of every function, plus faster copies that Julia picks at
  load time on newer CPUs. Other architectures get `generic` only (arm64
  images are not published or tested). Run-time code is still compiled for
  the CPU it runs on (`julia_cmd` stays `-C native`).
* **The cost:** the caches hold several copies of each function. On CI run
  43035350960 the compressed images (what a pull downloads) grew by 7 to 11%:
  scicomp 0.56 to 0.62 GiB, sciml 0.64 to 0.68, science 1.26 to 1.35; base
  holds no package caches and stayed at 0.20. Building every image took 1 h
  23 min. Cold starts measured slower on that run than on the one before
  (table below); the two runs were on different runners, so how much of that
  is the larger caches is not known.
* **The check:** `tutor sandbox check` (CI's `images` job) starts, in every
  environment, a second Julia with `-C generic` and lists every package
  whose cache it rejects. A cache compiled only for the build machine's CPU
  fails this on any machine. On CI run 43035350960 it passed for all eleven
  package environments in their images. Before that, on the authoring
  machine (Julia 1.10.13, outside the container), a cache built without the
  target was rejected under `-C generic`, and one built with it loaded.
* **What it fixed:** `course verify --sandbox=docker` on the next runner then
  finished every unit with no timeout (before: unit 21 timed out at 120 s,
  twice). It also exposed three MCMC examples in unit 27 whose digits moved,
  now recorded but not checked: the multi-CPU caches can run a different
  copy of the same function, which may round differently (fused
  multiply-add), and a sampler's chain carries that into the digits.

## Publishing and pulling

* **Where CI pushes:** each image goes to
  `ghcr.io/adamezzat1/julia-tutor-sandbox-<img>`, tagged `<julia>-<first 16
  hex digits of its input hash>` (`tutor sandbox publish --push`). If an image
  for the same inputs is already in the registry, CI pulls it instead of
  rebuilding. That turns the 1.5 h image build into a pull whenever no
  environment, Dockerfile or child script changed.
* **What gets recorded:** the digests go into `sandbox/images.toml`, together
  with the input hash each was built from. CI's last step (`tutor sandbox
  digests --check`) fails when the file does not name exactly the images for
  the checkout's inputs, and prints the file to commit. A PR that changes an
  image therefore needs a second commit carrying the digests from its own CI
  run; that run is fast because the images exist by then.
* **What `tutor sandbox pull <course>` does:**
  1. pulls base and the course's image by digest, never by tag;
  2. tags them locally;
  3. checks their labels against the checkout's hash.

  When the published image was built from other inputs, it refuses and says
  to run `tutor sandbox build <course>`.
* **Building instead of pulling:** `tutor sandbox build [course...]` stays for
  offline or audited setups. It builds the same Dockerfiles from a context
  holding only the baked-in files.
* **Making the images public:** the packages have to be public for a learner
  to pull without logging in. GHCR creates a package as private on its first
  push, and its visibility is changed in the repository owner's package
  settings. The `clean-start` CI job reports whether an anonymous pull works.
* **Letting CI push (once per package):** the first push of a new image
  creates its package and is then denied, even with `packages: write` and the
  `org.opencontainers.image.source` label (observed on this repo, Nov 2026).
  In the package's settings, under "Manage Actions access", add this
  repository with the Write role, then re-run CI. `tutor sandbox publish`
  tries every image before failing, so one run creates every missing package.

## `tutor serve --course=<id>`

* **What it needs:** only base and that course's image.
* **What it serves:**
  * `/api/health` reports the course and only its environments. The website
    already disables the environments a server does not list.
  * `/api/run` in another course's environment, and `/api/grade` of another
    course's problem, get 403 with the course to restart with.
* **What stays first:** the request policy (Host, Origin, token, size limits)
  is unchanged and runs before these checks. A request without the token
  still gets 401, tested in `test/course_tests.jl`.
* **Without `--course`:** it serves every course and needs every image.

## Sandbox/security review of the `docker run` flags

`Runner.docker_args` changed in two places only:
* the image name, now chosen by environment;
* the memory limit, now per image (`--memory`, `--memory-swap`, and
  `--heap-size-hint` at two thirds of it).

The memory limit is now 2 GB for base, 3 GB for scicomp and sciml, and
stays 6 GB for science ("Revisiting the 6 GB limit" below). Lowering a limit
only makes the container stricter. These flags are unchanged:
* `--network=none`, `--read-only`, `--cap-drop=ALL`,
  `--security-opt=no-new-privileges`;
* `--pids-limit=512`, `--cpus`;
* the unprivileged `--user`;
* the tmpfs on /tmp;
* the environment variables;
* no mount, volume, or extra network.

A test asserts that the argument list is identical for every environment
apart from the image, memory and `--project`, and that none of the images
use `ADD`, `VOLUME` or `EXPOSE`.

`contained.jl` now prints one more line after the files block: the
container's cgroup `memory.peak`. It is a measurement only:
* the learner's code could fake it from an `atexit` hook, so nothing is
  decided by it;
* it is read only after the files block, so a learner printing the marker
  does not lose output.

## Measurements

The numbers here come from two CI runs on 2026-11-11 (GitHub-hosted ubuntu
runners, 4 CPUs, cgroup v2): run 43035350960 on the current images (package
caches for every CPU), and run 42976555361 on the images before that change,
in brackets. Docker is not running on the authoring machine.

| Image | Compressed (a pull downloads) | Unpacked (`du` in the image) | Cold start, `using` the env (3 fresh containers) | Peak at load | Largest peak in `course verify` |
|---|---|---|---|---|---|
| base | 0.20 GiB (0.20) | 0.67 GiB | 1.3, 1.2, 1.2 s (1.1, 1.0, 1.0) | 0.15 GiB | 0.50 GiB (0.50) |
| scicomp | 0.62 GiB (0.56) | 2.33 GiB | scicomp 10.6, 9.9, 9.3 s (about 7.4); mtk 11.4, 10.1, 10.2 s (about 7.6) | 0.77; 0.86 GiB | 0.70; 0.88 GiB (0.74; 0.88) |
| sciml | 0.68 GiB (0.64) | 2.47 GiB | 10.8, 11.2, 11.0 s (about 8.2) | 0.51 GiB | 0.83 GiB (0.84) |
| science | 1.35 GiB (1.26) | 4.75 GiB | 2.6 (python) to 9.6 s (plots) (2.0 to 6.7) | 0.24 to 0.87 GiB | 3.85 GiB, ml (4.78); every other env ≤ 1.39 (diffeq) |

* **Unpacked sizes:** counted inside the image (`du -sxb /` in a container
  with the same flags as a run). `docker image inspect .Size`, which the
  first run printed, is the compressed content again under the containerd
  image store (CI's), so there is no "before" number for the course images.
* **Cold starts:** every one is slower on the later run, by 10 to 50%. The
  two runs were on different runners, and each number is three containers
  on one runner, so this does not separate the larger caches from the
  runner. Each first container is the slowest: the image's files are not
  yet in the page cache.
* **Science per environment** (later run): cold start calculus 3.8 to 4.7,
  data 3.2 to 4.2, diffeq 5.9 to 7.7, ml 8.4 to 8.7, optim 3.5 to 4.2, plots
  9.3 to 9.6, python 2.6 to 3.2, turing 3.9 to 4.7 s; largest verify peak
  calculus 0.39, data 0.32, diffeq 1.39, ml 3.85, optim 0.30, plots 0.61,
  python 0.29, turing 0.43 GiB.
* **Pull time on a clean machine** (`clean-start` job, fresh runner): Core
  in 87 s from nothing (107 s on the earlier run), of which `tutor sandbox
  pull core` 10 s; then scicomp 14 s (18), sciml 19 s (24), science 26 s
  (32) each. Anonymous pulls work, so the packages are public. Datacenter
  network: a home connection will be slower.

The jobs that produce them:

* **Sizes:** `images` job, `tutor sandbox measure`. For each image, the
  uncompressed size on disk and the compressed bytes a pull downloads, from
  the registry manifest.
* **Cold starts:** `images` job, `tutor sandbox measure`. Every Run is a fresh
  container, so every Run is a cold start. For each environment, three runs
  of loading its packages, each shown, with the container's memory peak.
* **Memory peak per course:** `verify` job. `tutor course verify
  --sandbox=docker` and `tutor guided verify` print the largest
  `memory.peak` of any container per environment, over every recorded
  example, problem sample, reference, starter and variant they run. The peak
  includes page cache, which the kernel reclaims before it kills for memory,
  so it is an upper bound on what a course needs.
* **Pull time on a clean machine:** `clean-start` job. A fresh runner with
  Docker and nothing else follows docs/START_CORE.md step by step, then
  pulls each other course's image on its own.

### Revisiting the 6 GB limit

The plan expected SciML to need 6 GB and Core not to. The measurements
agree about Core and disagree about SciML. Science is the course that needs
6 GB:

| Image | Largest measured peak | Limit now | Why |
|---|---|---|---|
| base | 0.50 GiB | 2g (was 6g) | 4x headroom; never below 2 GB |
| scicomp | 0.88 GiB (mtk) | 3g (was 6g) | 3.4x headroom |
| sciml | 0.84 GiB | 3g (was 6g) | 3.6x headroom |
| science | 4.78 GiB (ml) | 6g (unchanged) | 1.25x headroom only; MLJ's `evaluate` compiled inside a function, and a wrong answer that compiles a second path was killed at 4 GB before |

The rule (`Runner.IMAGE_MEMORY`): at least 3x the largest peak, rounded up
to a whole GB, never below 2 GB. The margin is wide because:
* a learner's own code is not measured, and can allocate more or compile
  more than any recorded run;
* one CI run measured the peaks, on one CPU type.

The peak includes page cache, which the kernel reclaims before it kills, so
it overstates what a run needs. A run that does hit the limit is reported as
a kill for memory (exit 137), with the limit, not as a crash.

**The guided projects** (measured later, on CI run 43127818869): every
guided project runs in a science environment, and `tutor guided verify`
(reference, mutants, exemplary tests, fixtures) peaked at plots 1.17, ml
0.85, calculus 0.72, diffeq 0.67, turing 0.55, data 0.51, optim 0.46 and
python 0.43 GiB, well under science's 6 GB. That run's `course verify` peaks
in the science environments were within 0.1 GiB of the later run above,
except ml (3.72 GiB, against 3.85).

**Not measured:**
* **sciml in a long training run:** sciml's 0.84 GiB covers every recorded
  example, problem sample, reference, starter and variant. A learner who
  trains a much larger network than the units do may need more than 3 GB.

What this buys a Core learner: Docker Desktop no longer needs 6 GB to spare
for Core Julia (2 GB for the container).
