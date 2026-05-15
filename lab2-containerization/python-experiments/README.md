# Python application — containerization experiments

Experiments on the Python starter project
[lab-03-starter-project-python](https://github.com/KPI-FICT-MTSD/lab-03-starter-project-python)
(a small FastAPI app called *spaceship*).

The Dockerfiles in this folder are meant to be **copied into a clone of the
starter project** (that clone is the build context). They are kept here,
separate from the source, only so this repository stays self-contained.

```bash
git clone https://github.com/KPI-FICT-MTSD/lab-03-starter-project-python.git
cd lab-03-starter-project-python
cp /path/to/lab2-containerization/python-experiments/Dockerfile.* .
cp /path/to/lab2-containerization/python-experiments/requirements-numpy.in .
cp /path/to/lab2-containerization/python-experiments/api.py.numpy .
```

> **Python version.** The Dockerfiles pin `python:3.13`. The assignment
> suggests using the latest stable release — substitute `python:3.14` (and
> `python:3.14-alpine`) if desired; the experiments are identical.

## How build time and image size are measured

Per the assignment footnote, the base-image download must not be counted in
the build time. Use the helper `../scripts/measure.sh`, which pre-pulls
every `FROM` image before timing the build:

```bash
../scripts/measure.sh Dockerfile.naive spaceship:naive .            # cold build
../scripts/measure.sh Dockerfile.naive spaceship:naive . --no-cache # forced clean build
```

Image size can also be read directly:

```bash
docker images spaceship --format '{{.Tag}}\t{{.Size}}'
```

## The experiments

| # | Dockerfile | What it demonstrates |
|---|---|---|
| 1 | `Dockerfile.naive` | First build of the naive image — baseline size & time |
| 2 | `Dockerfile.naive` | Rebuild after a one-line code change — the whole dependency layer is re-run because `COPY . .` precedes `pip install` |
| 3 | `Dockerfile.optimized` | Layers reordered (deps before code); rebuild after a code change re-uses the cached dependency layer |
| 4 | `Dockerfile.alpine` | Same layout on the `python:3.13-alpine` base — final image size comparison |
| 5 | `Dockerfile.numpy-debian` / `Dockerfile.numpy-alpine` | `numpy` added; compare build time & size of Alpine vs Debian when a heavy native dependency is involved |

### Experiment 1 — naive build, baseline

```bash
../scripts/measure.sh Dockerfile.naive spaceship:naive .
```

Record: image size, build time.

### Experiment 2 — naive build, rebuild after code change

Make a trivial change (the assignment suggests printing your name, or just
adding a comment), then rebuild **without** `--no-cache`:

```bash
echo "# changed by <Name Surname>" >> spaceship/routers/api.py
../scripts/measure.sh Dockerfile.naive spaceship:naive .
```

Record: image size, build time. Note that `pip install` runs again even
though dependencies did not change.

### Experiment 3 — optimized layers

```bash
# first build (populates the cache)
../scripts/measure.sh Dockerfile.optimized spaceship:optimized .
# change code again, then rebuild WITH cache
echo "# another change by <Name Surname>" >> spaceship/routers/api.py
../scripts/measure.sh Dockerfile.optimized spaceship:optimized .
```

Record both build times. The second rebuild should be much faster because
the `pip install` layer is served from cache (`CACHED` in the build log).

### Experiment 4 — Alpine base

```bash
../scripts/measure.sh Dockerfile.alpine spaceship:alpine .
```

Record: image size, build time. Compare the final size with experiment 3.

### Experiment 5 — adding numpy, Alpine vs Debian

Apply the numpy changes to the build context first:

```bash
cp api.py.numpy spaceship/routers/api.py
# requirements-numpy.in is already referenced by the numpy Dockerfiles
```

Then build both variants:

```bash
../scripts/measure.sh Dockerfile.numpy-debian spaceship:numpy-debian .
../scripts/measure.sh Dockerfile.numpy-alpine  spaceship:numpy-alpine  .
```

Record: image size and build time for each. Watch the `pip install` output
to see whether numpy was downloaded as a prebuilt wheel
(`Downloading numpy-...-musllinux_...`/`...-manylinux_...`) or compiled from
source (`Building wheel for numpy`). Verify the endpoint works:

```bash
docker run --rm -p 8080:8080 spaceship:numpy-debian &
curl -s http://127.0.0.1:8080/api/matrix | head -c 200
```

## Inspecting image contents

[`dive`](https://github.com/wagoodman/dive) shows the per-layer contents and
wasted space:

```bash
dive spaceship:naive
dive spaceship:optimized
```
