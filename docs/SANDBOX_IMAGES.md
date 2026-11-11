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
* **The cost:** the caches hold several copies of each function, so the
  images are larger and the build slower. The sizes below were measured on
  the images before this fix; the next CI run measures the new ones.
* **The check:** `tutor sandbox check` (CI's `images` job) starts, in every
  environment, a second Julia with `-C generic` and lists every package
  whose cache it rejects. A cache compiled only for the build machine's CPU
  fails this on any machine. Checked on the authoring machine, on Julia
  1.10.13 outside the container: a cache built without the target was
  rejected under `-C generic`, and one built with it loaded. The check has
  not yet run in a container (Docker stopped on the authoring machine).

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

Every number here comes from CI run 42976555361 (2026-11-11, GitHub-hosted
ubuntu runner, 4 CPUs, cgroup v2), on the images of this PR. Docker is not
running on the authoring machine apart from one local check, noted below.

| Image | Compressed (a pull downloads) | Unpacked | Cold start, `using` the env (3 fresh containers) | Peak at load | Largest peak in `course verify` |
|---|---|---|---|---|---|
| base | 0.20 GiB | 0.67 GiB (local build, `du`) | 1.1, 1.0, 1.0 s | 0.18 GiB | 0.50 GiB |
| scicomp | 0.56 GiB | next CI run | scicomp 7.4, 7.2, 7.5 s; mtk 8.0, 7.5, 7.4 s | 0.64; 0.88 GiB | 0.74; 0.88 GiB |
| sciml | 0.64 GiB | next CI run | about 8.2 s | 0.54 GiB | 0.84 GiB |
| science | 1.26 GiB | next CI run | 2.0 (python) to 6.7 s (plots) | 0.22 to 0.54 GiB | 4.78 GiB (ml); every other env ≤ 1.39 (diffeq) |

* **Unpacked sizes:** the first CI run printed `docker image inspect .Size`
  as the unpacked size, but with the containerd image store (CI's) that is
  the compressed content again. The unpacked size is now counted inside the
  image (`du -sxb /` in a container with the same flags as a run); the base
  number above is from that command on a local build, the course images'
  come with the next CI run.
* **Science per environment:** cold start calculus 3.0, data 2.4, diffeq
  about 4.5, ml about 5.7, optim about 2.5, plots about 6.7, python about
  2.0, turing 3.1 s; largest verify peak calculus 0.44, data 0.33, diffeq
  1.39, ml 4.78, optim 0.30, plots 0.65, python 0.30, turing 0.43 GiB.
* **Pull time on a clean machine** (`clean-start` job, fresh runner): Core
  in 107 s from nothing, of which `tutor sandbox pull core` 10 s; then
  scicomp 18 s, sciml 24 s, science 32 s each. Anonymous pulls work, so the
  packages are public. Datacenter network: a home connection will be slower.

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

**Not measured:**
* **The guided projects:** `tutor guided verify` did not run in that CI
  job, because course verify failed first, on a CPU-dependent example in
  unit 32 (fixed in this PR). Every guided project runs in a science
  environment, which keeps 6 GB.
* **sciml in a long training run:** sciml's 0.84 GiB covers every recorded
  example, problem sample, reference, starter and variant. A learner who
  trains a much larger network than the units do may need more than 3 GB.

What this buys a Core learner: Docker Desktop no longer needs 6 GB to spare
for Core Julia (2 GB for the container).
