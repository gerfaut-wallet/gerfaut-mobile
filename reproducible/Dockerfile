# Pinned toolchain the Gerfaut Android releases are built with.
#
# What compiles or packs bytes into the APK is pinned by hash: the base
# image and its JDK by digest; cmdline-tools and rustup by the hash of
# their download; the NDK and CMake by the hash of the tree sdkmanager
# unpacks; the Rust toolchain by the hash of its release manifest, which
# gives the hash of every package; the parts of the Flutter cache a
# release build reads (gen_snapshot, the patched SDK, the Dart SDK, and
# the host tools that write into the APK, such as font-subset) by the
# hash of their tree, Flutter itself by commit. Those trees are checked
# once `flutter precache` has run, which already ran the Dart SDK it
# fetched: the check catches a changed download, not a tool that hides
# its own change. What is still taken on the word of TLS: apt (the live
# jammy pocket, tools that fetch, unpack and link), platform-tools (no
# revision), build-tools and the platforms by exact revision
# (compile-time only), and the rest of the Flutter cache. The Gradle
# modules are checked against
# reproducible/verification-metadata.xml at build time (entrypoint.sh).
#
# The image builds *unsigned* APKs; signing happens later, on the release
# machine, with a key this image never sees.
#
# Build and run it through reproducible/build.sh, which also exports the
# sources at a fixed path so no host path reaches the artifacts.

# eclipse-temurin 17.0.20+8 on Ubuntu 22.04.5.
FROM eclipse-temurin:17.0.20_8-jdk-jammy@sha256:400014962ad7224461f945bb1cc3d7d5a1927ce15b8245b72d9cedcda554cd2a

# cmdline-tools 23.0. The checksum is the one Google publishes in
# https://dl.google.com/android/repository/repository2-3.xml, as sha256.
ARG ANDROID_CMDLINE_TOOLS=commandlinetools-linux-16111833_latest.zip
ARG ANDROID_CMDLINE_TOOLS_SHA256=0877a1d048fe4a24efe2eff536ca4223f7adeb58648bb81909d33c446918cfa8
# android-36 is the app's compileSdk and targetSdk; 35 and 34 are what
# some of the Flutter plugins compile against, and Gradle needs each one.
ARG ANDROID_PLATFORMS="android-36 android-35 android-34"
# The default build-tools revision of Android Gradle Plugin 9.4.1.
ARG ANDROID_BUILD_TOOLS=36.0.0
# The NDK Flutter 3.47.7 defaults to, which every native part builds
# with since flutter_zxing 3 stopped pinning an older one.
ARG ANDROID_NDK=28.2.13676358
# flutter_zxing and jni build their native code through CMake.
ARG ANDROID_CMAKE=3.22.1
# The NDK and CMake compile the native code the APK carries. sdkmanager
# checks what it downloads against a SHA-1 from a catalogue it fetches
# the same way, so the tree it unpacks is checked again here, path and
# content of every file and link (tree-sha256, below). Both hashes were
# taken from the archives the catalogue names, android-ndk-r28c-linux.zip
# and cmake-3.22.1-linux.zip, whose SHA-1 matched it, and they equal the
# trees an earlier sdkmanager install had made. To change a version:
# install it with sdkmanager, read `tree-sha256 <its folder>`, and check
# the archive it came from against the catalogue the same way.
ARG ANDROID_NDK_TREE_SHA256=23ae06352d74473cfc6d89ce88fec61ddbb097817e92030dfdd838873d0b7e6b
ARG ANDROID_CMAKE_TREE_SHA256=62b120bf4f6a00d14fad5ad549bfb653c929788b53d787529d5922ff1ab591a1
ARG FLUTTER_VERSION=3.47.7
ARG FLUTTER_COMMIT=abaf9c523780a608bd46686fd5e53740a07077f8
# What a release build of Flutter 3.47.7 reads from the cache `flutter
# precache` fills, each tree hashed like the NDK: gen_snapshot and the
# engine of each ABI (the engine itself reaches the APK from Maven, and
# Gradle checks it), the patched SDK the app's Dart compiles against,
# sky_engine, and the Dart SDK whose front end compiles it. The engine
# revision names these files but nothing checks them on the way in.
# Taken from a cache filled for the same release on another machine,
# which gave the same trees.
ARG FLUTTER_CACHE_TREES="\
a1dfe4083a1f17b70639f0fa3b57582483ceabf3caac86b0556e88cf9781182b:artifacts/engine/android-arm-release \
36a69fdce37f668ba65310f49e9aeee25b84a2f634ca6075e247a2252a567511:artifacts/engine/android-arm64-release \
0c487f1fe96e50241391836f252dc449abe38faae94008ddece15a0e7820469d:artifacts/engine/android-x64-release \
572852b710a9841c2de6668bf17f8041a2e3acfccd466bc41902369ca73668bf:artifacts/engine/common \
501978274592653e555dd4ccb0bfafe6652ce2acb9dbdbbf23a8a160ac7e483c:pkg/sky_engine \
496af49affa74eda470838e60d62cf40e23a5638b9fd686e96129ae634667874:dart-sdk \
d9ec0f47dcb832cde4e06b555eab83f22068ddf95976e399311f9d0328094853:artifacts/engine/linux-x64"
# The manifest hash has to follow the version:
#   curl -fsSL https://static.rust-lang.org/dist/channel-rust-<version>.toml | sha256sum
ARG RUST_VERSION=1.99.1
ARG RUST_MANIFEST_SHA256=fb152be80975c194aa5fc684b2aec3a6e14e2b855efe2faa4e5f8ae6e590f463
# rustup-init 1.29.1, the installer of the toolchain above, fetched as a
# binary and checked against the checksum rustup publishes beside it
# (rustup-init.sha256), never piped from a script into a shell.
ARG RUSTUP_VERSION=1.29.1
ARG RUSTUP_INIT_SHA256=dda7234360b7f578ca8b0ddcb80145646fa61a67c1720a5abc7051b35c9fcb71

ENV DEBIAN_FRONTEND=noninteractive \
    TZ=UTC \
    LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    ANDROID_HOME=/opt/android-sdk \
    ANDROID_SDK_ROOT=/opt/android-sdk \
    FLUTTER_ROOT=/opt/flutter \
    RUSTUP_HOME=/opt/rustup \
    PATH=/opt/cargo/bin:/opt/flutter/bin:/opt/android-sdk/cmdline-tools/latest/bin:$JAVA_HOME/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Host tools. None of them end up in the artifacts: they fetch, unpack
# and link. The versions are whatever the base image's suite ships, which
# is why they are kept to tools with no influence on the output bytes.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      build-essential ca-certificates curl file git python3 unzip xz-utils zip \
 && rm -rf /var/lib/apt/lists/*

# `tree-sha256 <dir> [<hash>]` prints one hash for every file and link
# under <dir>, by path and content, leaving out the package.xml that
# sdkmanager writes itself; given a hash, it fails unless they match.
RUN printf '%s\n' \
      '#!/bin/bash' \
      'set -euo pipefail' \
      'have="$(cd "$1" && {' \
      '    find . -type f ! -path ./package.xml ! -path "./.installer/*" -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum' \
      '    find . -type l -printf "%p -> %l\n" | LC_ALL=C sort' \
      '} | sha256sum | cut -d" " -f1)"' \
      'if [ "$#" -lt 2 ]; then echo "$have"; exit 0; fi' \
      '[ "$have" = "$2" ] || { echo "tree-sha256: $1 is $have, pinned $2" >&2; exit 1; }' \
      > /usr/local/bin/tree-sha256 \
 && chmod 0755 /usr/local/bin/tree-sha256

# Android SDK.
RUN mkdir -p "$ANDROID_HOME/cmdline-tools" \
 && curl -fsSL -o /tmp/cmdline-tools.zip \
      "https://dl.google.com/android/repository/${ANDROID_CMDLINE_TOOLS}" \
 && echo "${ANDROID_CMDLINE_TOOLS_SHA256}  /tmp/cmdline-tools.zip" | sha256sum -c - \
 && unzip -q /tmp/cmdline-tools.zip -d /tmp/cmdline-tools \
 && mv /tmp/cmdline-tools/cmdline-tools "$ANDROID_HOME/cmdline-tools/latest" \
 && rm -rf /tmp/cmdline-tools.zip /tmp/cmdline-tools \
 && yes | sdkmanager --licenses > /dev/null \
 && sdkmanager --install \
      "build-tools;${ANDROID_BUILD_TOOLS}" \
      "cmake;${ANDROID_CMAKE}" \
      "platform-tools" \
      $(for p in $ANDROID_PLATFORMS; do echo "platforms;$p"; done) \
      "ndk;${ANDROID_NDK}" > /dev/null \
 && rm -rf "$ANDROID_HOME/.downloadIntermediates" \
 && tree-sha256 "$ANDROID_HOME/ndk/${ANDROID_NDK}" "${ANDROID_NDK_TREE_SHA256}" \
 && tree-sha256 "$ANDROID_HOME/cmake/${ANDROID_CMAKE}" "${ANDROID_CMAKE_TREE_SHA256}"

# Flutter, at the exact commit the tag points to.
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_ROOT" \
 && test "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" = "$FLUTTER_COMMIT" \
 && git config --global --add safe.directory "$FLUTTER_ROOT" \
 && flutter config --no-analytics > /dev/null \
 && flutter precache --android --no-ios --universal \
 && flutter --version \
 && [ -n "$FLUTTER_CACHE_TREES" ] \
 && for pin in $FLUTTER_CACHE_TREES; do \
      tree-sha256 "$FLUTTER_ROOT/bin/cache/${pin#*:}" "${pin%%:*}" || exit 1; \
    done

# Rust, without letting rustup download it. Left alone, rustup fetches
# the release manifest again after any check made here, and trusts
# whatever it gets the second time. So the manifest is fetched once,
# into /opt/rust-dist, and checked against the hash above. `rust-dist
# <target> <package>...` then fetches each package from the address that
# manifest gives and checks it against the hash it gives, and rustup
# installs from that local copy, through a file:// address. Its proxy
# points at a closed port, so it could not reach the network if it
# tried. The packages are deleted once installed.
#
# Cargokit invokes `rustup run stable cargo`, which sets
# RUSTUP_TOOLCHAIN and therefore ignores rust/rust-toolchain.toml; the
# symlink below makes `stable` resolve to the pinned toolchain so the
# two agree.
RUN printf '%s\n' \
      '#!/bin/bash' \
      'set -euo pipefail' \
      'manifest=(/opt/rust-dist/dist/channel-rust-*.toml)' \
      '[ "${#manifest[@]}" -eq 1 ] && [ -f "${manifest[0]}" ] || { echo "rust-dist: no checked manifest" >&2; exit 1; }' \
      'target="$1"' \
      'shift' \
      'for package in "$@"; do' \
      '    url=""; hash=""; inside=0' \
      '    while read -r key _ value; do' \
      '        case "$key" in' \
      '            "[pkg.$package.target.$target]") inside=1 ;;' \
      '            "["*) inside=0 ;;' \
      '            xz_url) [ "$inside" -eq 0 ] || url="${value//\"/}" ;;' \
      '            xz_hash) [ "$inside" -eq 0 ] || hash="${value//\"/}" ;;' \
      '        esac' \
      '    done < "${manifest[0]}"' \
      '    case "$url" in' \
      '        https://static.rust-lang.org/dist/*) ;;' \
      '        *) echo "rust-dist: no $package for $target in the manifest" >&2; exit 1 ;;' \
      '    esac' \
      '    [ "${#hash}" -eq 64 ] || { echo "rust-dist: no hash for $package" >&2; exit 1; }' \
      '    file="/opt/rust-dist/dist/${url#https://static.rust-lang.org/dist/}"' \
      '    mkdir -p "$(dirname "$file")"' \
      '    curl --proto =https --tlsv1.2 --retry 5 -fsSL -o "$file" "$url"' \
      '    echo "$hash  $file" | sha256sum -c -' \
      'done' \
      > /usr/local/bin/rust-dist \
 && chmod 0755 /usr/local/bin/rust-dist \
 && curl --proto '=https' --tlsv1.2 --retry 5 -fsSL -o /tmp/rustup-init \
      "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" \
 && echo "${RUSTUP_INIT_SHA256}  /tmp/rustup-init" | sha256sum -c - \
 && mkdir -p /opt/rust-dist/dist \
 && curl --proto '=https' --tlsv1.2 --retry 5 -fsSL -o "/opt/rust-dist/dist/channel-rust-${RUST_VERSION}.toml" \
      "https://static.rust-lang.org/dist/channel-rust-${RUST_VERSION}.toml" \
 && echo "${RUST_MANIFEST_SHA256}  /opt/rust-dist/dist/channel-rust-${RUST_VERSION}.toml" | sha256sum -c - \
 && echo "${RUST_MANIFEST_SHA256}  channel-rust-${RUST_VERSION}.toml" \
      > "/opt/rust-dist/dist/channel-rust-${RUST_VERSION}.toml.sha256" \
 && rust-dist x86_64-unknown-linux-gnu rustc rust-std cargo \
 && for target in aarch64-linux-android armv7-linux-androideabi x86_64-linux-android; do \
      rust-dist "$target" rust-std || exit 1; \
    done \
 && chmod +x /tmp/rustup-init \
 && CARGO_HOME=/opt/cargo RUSTUP_DIST_SERVER=file:///opt/rust-dist \
    all_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 \
    /tmp/rustup-init -y --no-modify-path --profile minimal --default-toolchain "$RUST_VERSION" \
 && rm /tmp/rustup-init \
 && ln -s "$RUSTUP_HOME/toolchains/${RUST_VERSION}-x86_64-unknown-linux-gnu" \
          "$RUSTUP_HOME/toolchains/stable-x86_64-unknown-linux-gnu" \
 && CARGO_HOME=/opt/cargo RUSTUP_DIST_SERVER=file:///opt/rust-dist \
    all_proxy=http://127.0.0.1:9 https_proxy=http://127.0.0.1:9 http_proxy=http://127.0.0.1:9 \
    rustup target add --toolchain "$RUST_VERSION" \
      aarch64-linux-android armv7-linux-androideabi x86_64-linux-android \
 && find /opt/rust-dist/dist -mindepth 1 -maxdepth 1 -type d -exec rm -rf {} + \
 && rustup run stable rustc --version | grep -q "$RUST_VERSION"

# Downloaded dependencies only. Mounting a volume here across two builds
# saves bandwidth; it cannot change the output, which is pinned by
# Cargo.lock, pubspec.lock, the Gradle module versions and their hashes
# in reproducible/verification-metadata.xml.
ENV CARGO_HOME=/cache/cargo \
    GRADLE_USER_HOME=/cache/gradle \
    PUB_CACHE=/cache/pub \
    CARGO_INCREMENTAL=0 \
    CI=true \
    FLUTTER_SUPPRESS_ANALYTICS=true

# The recipe travels with the sources rather than with the image: what
# runs below is reproducible/entrypoint.sh of the very commit being
# built, mounted read-only under /src. The image is nothing but the
# toolchain.
WORKDIR /build
ENTRYPOINT ["bash", "/src/gerfaut-mobile/reproducible/entrypoint.sh"]
