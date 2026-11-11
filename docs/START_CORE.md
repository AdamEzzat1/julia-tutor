# Start Core Julia in 10 minutes

This gets you from nothing to running code from the course's website on your
own machine. Every Run happens in a sandbox container with no network and a
read-only file system.

**Measured time: 107 seconds** for steps 1–5, on a fresh GitHub-hosted Linux
runner (4 CPUs) on 2026-11-11 (CI run 42976555361, `clean-start` job, which
runs `scripts/clean_start.sh`):

| Step | Seconds |
|---|---|
| 1. install juliaup and Julia 1.10.13 | 3 |
| 2. git clone | 0 |
| 3. install the tutor's packages | 80 |
| 4. `tutor sandbox pull core` | 10 |
| 5. `tutor serve --course=core`, first Run answered | 13 |

That runner sits on a datacenter network, so the downloads in steps 1, 3 and
4 were fast: expect them to take longer on a home connection. This time has
not been measured on a learner's machine, on macOS or on Windows.

You need **Docker** (Docker Desktop on Windows and macOS, the Docker engine on
Linux), running, and **git**. Installing Docker is not part of the timing.

## 1. Install Julia 1.10.13 with juliaup

Linux and macOS:

```bash
curl -fsSL https://install.julialang.org | sh -s -- --yes --default-channel 1.10.13
```

Windows: `winget install --name Julia --id 9NJNWW8PVKMN -e -s msstore`, then
`juliaup add 1.10.13`. Open a new terminal afterwards so `julia` is on PATH.

The tutor runs only on 1.10.13 and refuses any other version.

## 2. Get the tutor

```bash
git clone --depth 1 https://github.com/AdamEzzat1/julia-tutor
cd julia-tutor
```

## 3. Install the tutor's own packages

This is the only step that uses the network besides the image pull.

```bash
source scripts/env.sh
JULIA_PKG_OFFLINE=false julia_pinned --project=. -e 'using Pkg; Pkg.instantiate()'
```

On Windows (PowerShell), into the same repo-local depot the wrapper uses:

```powershell
$env:JULIA_DEPOT_PATH = "$PWD\.depot"; julia +1.10.13 --project=. -e "using Pkg; Pkg.instantiate()"
```

and run `.\tutor.ps1` in place of `./tutor` in the steps below. (Only the
Linux steps are timed.)

## 4. Fetch Core Julia's sandbox

```bash
./tutor sandbox pull core
```

This downloads the published base image by its digest (recorded in
`sandbox/images.toml`) and checks it was built from this checkout. If it was
not (you changed `src/child` or `course/envs`), it says so and tells you to
run `./tutor sandbox build core`, which builds the same image offline from
the checkout.

## 5. Start the server and connect the website

```bash
./tutor serve --course=core
```

It prints a link. Open it: the website connects to the server on 127.0.0.1
and every Run button on the Core Julia pages works. The server answers only
Core Julia's environments and problems; for another course it says which
course to start instead.

## Adding a course later

```bash
./tutor sandbox pull scicomp     # or science, sciml
./tutor serve --course=scicomp
```

Each course's image holds only that course's packages, so it is a separate
and larger download. Measured on the same runner right after Core: scicomp
18 s, sciml 24 s, science 32 s. The sizes are in
[docs/SANDBOX_IMAGES.md](SANDBOX_IMAGES.md).
