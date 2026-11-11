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

Every image keeps the 6 GB limit until its peak is measured. These flags are
unchanged:
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

**Not measured yet: Docker is not running on the authoring machine, so every
number here comes from CI.** The jobs that produce them:

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

Recorded here once CI has measured the peaks. The expectation from the plan
was that the SciML image needs 6 GB and Core does not. It is not acted on
until the peaks are in.
