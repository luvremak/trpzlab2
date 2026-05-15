# Golang application — multi-stage build experiments

Experiments on the Go starter project
[deploy.lab-containers-starter-project-golang](https://github.com/comsys-kpi-ua/deploy.lab-containers-starter-project-golang)
(a small cobra CLI / HTTP server called *fizzbuzz*).

As with the Python experiments, the Dockerfiles here are meant to be copied
into a clone of the starter project, which becomes the build context:

```bash
git clone https://github.com/comsys-kpi-ua/deploy.lab-containers-starter-project-golang.git
cd deploy.lab-containers-starter-project-golang
cp /path/to/lab2-containerization/golang-experiments/Dockerfile.* .
```

## The experiments

| # | Dockerfile | What it demonstrates |
|---|---|---|
| 1 | `Dockerfile.single-stage` | Build + run in one `golang` image — correct but huge; the toolchain, module cache and source are all dead weight at runtime |
| 2 | `Dockerfile.multistage-scratch` | Two stages: compile in `golang`, ship the binary in an empty `scratch` image. Surfaces two real pitfalls (dynamic linking, missing runtime asset) and their fixes |
| 3 | `Dockerfile.multistage-distroless` | Same two-stage idea but a `distroless` runtime base — a middle ground between `scratch` and a full distro |

### Experiment 1 — single-stage

```bash
../scripts/measure.sh Dockerfile.single-stage fizzbuzz:single-stage .
docker run --rm -p 8080:8080 fizzbuzz:single-stage &
curl -s http://127.0.0.1:8080/ | head -c 100
```

Record: image size, build time. Then inspect the contents and ask which
files are actually needed to *run* the app:

```bash
dive fizzbuzz:single-stage
# or, without dive:
docker run --rm fizzbuzz:single-stage ls -la /usr/local/go /src
```

### Experiment 2 — multi-stage with `scratch`

First, reproduce the **naive** failure to understand it (the assignment
explicitly expects this). Build a throwaway naive version — binary only,
CGO left enabled, no templates — and watch it fail:

```bash
# naive attempt, expected to fail at runtime with "no such file or directory"
cat > Dockerfile.scratch-naive <<'EOF'
FROM golang:1.23 AS builder
WORKDIR /src
COPY . .
RUN go build -o /fizzbuzz
FROM scratch
COPY --from=builder /fizzbuzz /fizzbuzz
CMD ["/fizzbuzz", "serve"]
EOF
docker build -f Dockerfile.scratch-naive -t fizzbuzz:scratch-naive .
docker run --rm fizzbuzz:scratch-naive          # observe the error
```

Then build the corrected version from this folder, which fixes both causes
(static binary via `CGO_ENABLED=0`, plus copying `templates/`):

```bash
../scripts/measure.sh Dockerfile.multistage-scratch fizzbuzz:scratch .
docker run --rm -p 8080:8080 fizzbuzz:scratch &
curl -s http://127.0.0.1:8080/ | head -c 100
```

Record: image size, build time. Note for the report: there is no shell in
the image, so `docker run --rm -it fizzbuzz:scratch sh` does **not** work —
the image is awkward to poke around in.

### Experiment 3 — multi-stage with `distroless`

```bash
../scripts/measure.sh Dockerfile.multistage-distroless fizzbuzz:distroless .
docker run --rm -p 8080:8080 fizzbuzz:distroless &
curl -s http://127.0.0.1:8080/ | head -c 100
```

Record: image size, build time. Compare the size and contents against the
`scratch` image — distroless is slightly larger because it bundles CA
certificates, timezone data and a nonroot user.

## Suggested results table for the report

| Variant | Base image | Image size | Build time | Has shell? |
|---|---|---|---|---|
| single-stage | `golang:1.23` | — | — | yes |
| multi-stage scratch | `scratch` | — | — | no |
| multi-stage distroless | `distroless/static-debian12` | — | — | no |
