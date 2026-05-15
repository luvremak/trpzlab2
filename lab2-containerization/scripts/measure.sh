#!/usr/bin/env bash
#
# measure.sh — build a Docker image and report build time + final size.
#
# Usage:
#   ./measure.sh <dockerfile> <tag> [context-dir] [--no-cache]
#
# Every base image referenced by a `FROM` line is pulled BEFORE the build is
# timed, so base-image download time is not counted (assignment footnote 1).
#
#   * without --no-cache : the build uses the layer cache. Use this to
#                          measure cache-assisted rebuilds, e.g. the
#                          layer-ordering experiment.
#   * with --no-cache    : the build ignores the cache. Use this for a
#                          "cold" from-scratch measurement.
#
# Examples:
#   ./measure.sh Dockerfile.naive      spaceship:naive      .
#   ./measure.sh Dockerfile.optimized  spaceship:optimized  . --no-cache
#
set -euo pipefail

if [[ $# -lt 2 ]]; then
    echo "Usage: $0 <dockerfile> <tag> [context-dir] [--no-cache]" >&2
    exit 1
fi

DOCKERFILE="$1"
TAG="$2"
CONTEXT="."
NO_CACHE=""

shift 2
for arg in "$@"; do
    case "$arg" in
        --no-cache) NO_CACHE="--no-cache" ;;
        *)          CONTEXT="$arg" ;;
    esac
done

if [[ ! -f "$DOCKERFILE" ]]; then
    echo "Dockerfile not found: $DOCKERFILE" >&2
    exit 1
fi

# --- Pre-pull every base image so download time is not measured ------------
echo "[measure] pre-pulling base images referenced in $DOCKERFILE ..."
grep -E '^[[:space:]]*FROM[[:space:]]' "$DOCKERFILE" \
    | awk '{print $2}' \
    | sort -u \
    | while read -r img; do
        if [[ "$img" == "scratch" ]]; then
            continue
        fi
        echo "[measure]   docker pull $img"
        docker pull "$img" >/dev/null
    done

# --- Timed build -----------------------------------------------------------
echo "[measure] building $TAG (cache: ${NO_CACHE:-enabled}) ..."
START=$(date +%s.%N)
docker build $NO_CACHE -f "$DOCKERFILE" -t "$TAG" "$CONTEXT"
END=$(date +%s.%N)

BUILD_TIME=$(awk "BEGIN {printf \"%.2f\", $END - $START}")

# --- Final image size ------------------------------------------------------
SIZE_BYTES=$(docker image inspect "$TAG" --format '{{.Size}}')
SIZE_MIB=$(awk "BEGIN {printf \"%.2f\", $SIZE_BYTES / 1024 / 1024}")

echo
echo "=============================================="
echo " Dockerfile : $DOCKERFILE"
echo " Tag        : $TAG"
echo " Cache      : ${NO_CACHE:-enabled}"
echo " Build time : ${BUILD_TIME} s"
echo " Image size : ${SIZE_MIB} MiB (${SIZE_BYTES} bytes)"
echo "=============================================="
