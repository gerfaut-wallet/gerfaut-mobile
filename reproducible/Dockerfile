# Pinned toolchain for reproducible Gerfaut Android builds.
#
# Everything that shapes the APK is pinned here: the base image by
# digest, the JDK by the base image, the Android SDK components by exact
# revision, Flutter by tag and commit, Rust by version. What is not
# pinned is the image's own build — apt pulls the live jammy pocket and
# platform-tools has no revision — which changes the image without
# changing the APKs it produces; the caveats are spelled out in
# docs/REPRODUCIBLE-BUILDS.md.
#
# The image builds *unsigned* APKs; signing happens later, in the release
# workflow, with a key this image never sees.
#
# Build and run it through reproducible/verify.sh, which also exports the
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
# The default build-tools revision of Android Gradle Plugin 9.1.0.
ARG ANDROID_BUILD_TOOLS=36.0.0
# Two NDKs: the one Flutter 3.47.1 defaults to, and the older revision
# flutter_zxing pins for its native decoder.
ARG ANDROID_NDKS="28.2.13676358 27.0.12077973"
# flutter_zxing and jni build their native code through CMake.
ARG ANDROID_CMAKE=3.22.1
ARG FLUTTER_VERSION=3.47.1
ARG FLUTTER_COMMIT=6655482ec06e547f90abf8ae7590466f4415978d
ARG RUST_VERSION=1.97.0

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
      $(for n in $ANDROID_NDKS; do echo "ndk;$n"; done) > /dev/null \
 && rm -rf "$ANDROID_HOME/.downloadIntermediates"

# Flutter, at the exact commit the tag points to.
RUN git clone --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git "$FLUTTER_ROOT" \
 && test "$(git -C "$FLUTTER_ROOT" rev-parse HEAD)" = "$FLUTTER_COMMIT" \
 && git config --global --add safe.directory "$FLUTTER_ROOT" \
 && flutter config --no-analytics > /dev/null \
 && flutter precache --android --no-ios --universal \
 && flutter --version

# Rust. Cargokit invokes `rustup run stable cargo`, which sets
# RUSTUP_TOOLCHAIN and therefore ignores rust/rust-toolchain.toml; the
# symlink below makes `stable` resolve to the pinned toolchain so the
# two agree. See docs/REPRODUCIBLE-BUILDS.md.
RUN CARGO_HOME=/opt/cargo curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
      | CARGO_HOME=/opt/cargo sh -s -- -y \
          --no-modify-path --profile minimal --default-toolchain "$RUST_VERSION" \
 && ln -s "$RUSTUP_HOME/toolchains/${RUST_VERSION}-x86_64-unknown-linux-gnu" \
          "$RUSTUP_HOME/toolchains/stable-x86_64-unknown-linux-gnu" \
 && CARGO_HOME=/opt/cargo rustup target add --toolchain "$RUST_VERSION" \
      aarch64-linux-android armv7-linux-androideabi x86_64-linux-android \
 && rustup run stable rustc --version | grep -q "$RUST_VERSION"

# Downloaded dependencies only. Mounting a volume here across two builds
# saves bandwidth; it cannot change the output, which is pinned by
# Cargo.lock, pubspec.lock and the Gradle module versions.
ENV CARGO_HOME=/cache/cargo \
    GRADLE_USER_HOME=/cache/gradle \
    PUB_CACHE=/cache/pub \
    CARGO_INCREMENTAL=0 \
    CI=true \
    FLUTTER_SUPPRESS_ANALYTICS=true

# The recipe travels with the sources rather than with the image: what
# runs below is reproducible/build.sh of the very commit being built,
# mounted read-only under /src. The image is nothing but the toolchain.
WORKDIR /build
ENTRYPOINT ["bash", "/src/gerfaut-mobile/reproducible/build.sh"]
