#!/usr/bin/env bash
# Builds the unsigned Gerfaut APKs in the pinned container.
#
#   reproducible/verify.sh                 build once into reproducible/out
#   reproducible/verify.sh --twice         build twice and compare the hashes
#
# The script exports both source trees from git at a fixed path, so the
# working tree, the checkout location and the host toolchain have no say
# in the result. Read docs/REPRODUCIBLE-BUILDS.md before trusting it.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo="$(cd "$here/.." && pwd)"

image=gerfaut-mobile-rb:latest
core="${GERFAUT_CORE_DIR:-$repo/../gerfaut-core}"
out="$here/out"
ref=HEAD
version=""
twice=0
build_image=1
use_cache=1
any_core=0

usage() {
    sed -n '2,9p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
    cat <<'USAGE'

Options:
  --core DIR      gerfaut-core checkout (default: ../gerfaut-core)
  --image NAME    tag to build and run (default: gerfaut-mobile-rb:latest)
  --out DIR       output directory (default: reproducible/out)
  --ref REF       commit to build (default: HEAD)
  --version TAG   version used in the artifact names (default: from pubspec.yaml)
  --twice         build twice and fail if the artifacts differ
  --skip-image    reuse the image already built
  --no-cache      do not reuse the downloaded-dependency volume
  --any-core      accept a gerfaut-core checkout other than the pinned one
USAGE
}

while [ $# -gt 0 ]; do
    case "$1" in
        --core) core="$2"; shift 2 ;;
        --out) out="$2"; shift 2 ;;
        --ref) ref="$2"; shift 2 ;;
        --version) version="$2"; shift 2 ;;
        --image) image="$2"; shift 2 ;;
        --twice) twice=1; shift ;;
        --skip-image) build_image=0; shift ;;
        --no-cache) use_cache=0; shift ;;
        --any-core) any_core=1; shift ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
    esac
done

# Docker Desktop wants a Windows path even when the shell hands it a
# POSIX one.
hostpath() {
    if command -v cygpath > /dev/null 2>&1; then cygpath -m "$1"; else echo "$1"; fi
}
docker() { MSYS_NO_PATHCONV=1 command docker "$@"; }

pinned="$(tr -d ' \t\r\n' < "$here/gerfaut-core.rev")"
[ -d "$core/.git" ] || [ -f "$core/.git" ] || {
    echo "not a gerfaut-core checkout: $core" >&2
    echo "clone https://github.com/gerfaut-wallet/gerfaut-core at $pinned" >&2
    exit 1
}
core_rev="$(git -C "$core" rev-parse HEAD)"
if [ "$core_rev" != "$pinned" ] && [ "$any_core" -eq 0 ]; then
    echo "gerfaut-core is at $core_rev, this release pins $pinned" >&2
    echo "check it out, or pass --any-core to build anyway" >&2
    exit 1
fi

# The commit date of what is being built, not the wall clock.
epoch="$(git -C "$repo" log -1 --format=%ct "$ref")"
[ -z "$(git -C "$repo" status --porcelain)" ] || \
    echo "warning: uncommitted changes are not part of the build ($ref is)" >&2

if [ "$build_image" -eq 1 ]; then
    echo "==> building $image"
    docker build -t "$image" "$(hostpath "$here")"
fi

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/gerfaut-mobile" "$stage/gerfaut-core"
# Blob bytes, never the working-tree representation: a Windows checkout
# with core.autocrlf on would otherwise hand the container CRLF sources
# and a different APK.
archive() { git -C "$1" -c core.autocrlf=false -c core.eol=lf archive --format=tar "$2"; }
archive "$repo" "$ref" | tar -x -C "$stage/gerfaut-mobile"
archive "$core" "$core_rev" | tar -x -C "$stage/gerfaut-core"

# Downloaded dependencies only; the artifacts do not depend on it. Keyed
# on the image so a rebuilt image never reuses an older toolchain's cache.
cache_mount=""
if [ "$use_cache" -eq 1 ]; then
    image_id="$(docker image inspect --format '{{.Id}}' "$image" | sed 's/^sha256://' | cut -c1-12)"
    cache_mount="gerfaut-rb-cache-$image_id:/cache"
fi

run_build() {
    local dest="$1"
    rm -rf "$dest"
    mkdir -p "$dest"
    docker run --rm \
        -e SOURCE_DATE_EPOCH="$epoch" \
        -e GERFAUT_VERSION="$version" \
        ${cache_mount:+-v "$cache_mount"} \
        -v "$(hostpath "$stage"):/src:ro" \
        -v "$(hostpath "$dest"):/out" \
        "$image"
}

mkdir -p "$out"
if [ "$twice" -eq 0 ]; then
    run_build "$out"
    echo
    echo "==> artifacts in $out"
    exit 0
fi

echo "==> build 1 of 2"
run_build "$out/build-1"
echo "==> build 2 of 2"
run_build "$out/build-2"

echo
if diff -u "$out/build-1/SHA256SUMS" "$out/build-2/SHA256SUMS"; then
    echo "==> reproducible: both builds produced the same artifacts"
    cat "$out/build-1/SHA256SUMS"
else
    echo "==> NOT reproducible: the two builds differ" >&2
    for apk in "$out"/build-1/*.apk; do
        name="$(basename "$apk")"
        python3 "$here/compare.py" "$apk" "$out/build-2/$name" || true
    done
    exit 1
fi
