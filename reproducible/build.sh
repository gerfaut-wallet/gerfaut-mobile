#!/usr/bin/env bash
# Builds the unsigned Gerfaut APKs inside the pinned container.
#
# Sources arrive read-only under /src, are copied to a fixed path under
# /build so nothing outside the container can influence the artifacts,
# and the three per-ABI APKs land in /out next to a SHA256SUMS manifest.
#
# Run it through reproducible/verify.sh rather than by hand.
set -euo pipefail

SRC=/src
WORK=/build
OUT=/out

for dir in "$SRC/gerfaut-mobile" "$SRC/gerfaut-core"; do
    [ -d "$dir" ] || { echo "missing source tree: $dir" >&2; exit 1; }
done
mkdir -p "$OUT"

# A fixed build path, identical on every machine: the Rust core resolves
# its sibling through ../../gerfaut-core, and no absolute path from the
# host can reach a compiler.
rm -rf "$WORK"
mkdir -p "$WORK"
cp -a "$SRC/gerfaut-mobile" "$WORK/gerfaut-mobile"
cp -a "$SRC/gerfaut-core" "$WORK/gerfaut-core"

# The tagged commit's date, so nothing picks up the wall clock. Android
# Gradle Plugin already writes a constant timestamp on every zip entry,
# so this mostly matters to the toolchains underneath it.
export SOURCE_DATE_EPOCH="${SOURCE_DATE_EPOCH:-0}"
export TZ=UTC
export LC_ALL=C.UTF-8

# Rust: no incremental artifacts, and no path from this container in the
# shared objects. Cargokit appends its own -L flag to this variable, so
# the separator has to be the one Cargo expects.
US=$'\x1f'
export CARGO_INCREMENTAL=0
export CARGO_ENCODED_RUSTFLAGS="--remap-path-prefix=${WORK}=/gerfaut${US}--remap-path-prefix=${CARGO_HOME}=/cargo${US}--remap-path-prefix=${RUSTUP_HOME}=/rustup"

# Gradle: no daemon, so a build never inherits state from the one before
# it, and no SDK auto-download, so a component missing from the image
# stops the build instead of arriving unpinned from the network. These
# are properties of the container, not of the project, which is why they
# are written here and not in the repository.
mkdir -p "$GRADLE_USER_HOME"
cat > "$GRADLE_USER_HOME/gradle.properties" <<'PROPS'
org.gradle.daemon=false
org.gradle.parallel=false
org.gradle.caching=false
android.builder.sdkDownload=false
# The project asks for an 8 GB heap, which is more than a container
# usually gets; these two caps keep both JVMs inside 8 GB of RAM and
# change nothing in the output.
org.gradle.jvmargs=-Xmx4g -XX:MaxMetaspaceSize=1g
kotlin.daemon.jvmargs=-Xmx1g
PROPS

cd "$WORK/gerfaut-mobile"

VERSION="${GERFAUT_VERSION:-}"
if [ -z "$VERSION" ]; then
    VERSION="v$(sed -n 's/^version: *\([0-9][^+]*\).*/\1/p' pubspec.yaml)"
fi

echo "==> flutter $(flutter --version | head -1)"
echo "==> rust $(rustup run stable rustc --version)"
echo "==> version $VERSION, SOURCE_DATE_EPOCH $SOURCE_DATE_EPOCH"

flutter pub get
# The same flags the release workflow uses, minus the keystore: the
# artifacts have to differ only by the signature.
flutter build apk --release --split-per-abi --android-project-arg=gerfaut.unsigned=true

for abi in armeabi-v7a arm64-v8a x86_64; do
    src="build/app/outputs/flutter-apk/app-${abi}-release.apk"
    [ -f "$src" ] || { echo "missing build output: $src" >&2; exit 1; }
    cp "$src" "$OUT/gerfaut-${VERSION}-android-${abi}-unsigned.apk"
done

cd "$OUT"
rm -f SHA256SUMS
sha256sum gerfaut-*.apk | sort -k2 > SHA256SUMS
cat SHA256SUMS

# Leave the output owned by whoever owns the mount, not by root.
owner="$(stat -c '%u:%g' "$OUT")"
[ "$owner" = "0:0" ] || chown -R "$owner" "$OUT"
