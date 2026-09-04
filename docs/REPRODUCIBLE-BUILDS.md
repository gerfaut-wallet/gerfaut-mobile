# Reproducible builds

The Android APKs published on the [releases page](https://github.com/gerfaut-wallet/gerfaut-mobile/releases) are built inside a container where every version is pinned: the base image by digest, the JDK, the Android SDK, the NDK, Flutter and Rust by exact revision. Building the same commit twice in that container produces the same bytes.

This means you do not have to trust the machine that produced the file you downloaded. Rebuild it yourself, compare it with the published APK, and the only difference should be the signature.

That last point is the honest limit of the exercise. The release key stays on the author's machine, so nobody else can produce the signature. What you can verify is everything else: the code, the assets, the compiled libraries, in short the entire payload the phone installs.

## What you need

- Docker, and a Linux container engine (Docker Desktop on Windows and macOS works)
- git and Python 3
- About 10 GB of free disk for the image, a few more while a build runs, and
  8 GB of RAM given to the container engine
- Roughly half an hour per build on a recent laptop

## Rebuild a release

```sh
git clone https://github.com/gerfaut-wallet/gerfaut-mobile
git clone https://github.com/gerfaut-wallet/gerfaut-core
cd gerfaut-mobile
git checkout v0.1.0
git -C ../gerfaut-core checkout "$(cat reproducible/gerfaut-core.rev)"
reproducible/verify.sh
```

On Windows, run `pwsh reproducible/verify.ps1` instead of the last line; it calls the same script through Git Bash.

The script builds the image, exports both source trees from git into a fixed path inside the container, and writes three unsigned APKs plus a `SHA256SUMS` manifest into `reproducible/out/`.

The Rust core lives in a second repository, and a path dependency records no revision, so `reproducible/gerfaut-core.rev` names the exact `gerfaut-core` commit a release was built from. The script refuses to build against any other one.

To check that the build is stable on your own machine, ask for two of them:

```sh
reproducible/verify.sh --twice
```

It builds twice, in two separate containers, and fails if a single byte differs. That is exactly what the `Reproducible build` workflow runs on every tag.

## Compare with a published release

Your rebuild is unsigned, the published APK is signed. An APK signature is a block inserted between the file data and the zip index, so the two files are never byte for byte identical. Every entry inside them must be.

```sh
gh release download v0.1.0 --pattern 'gerfaut-*arm64-v8a.apk'
python3 reproducible/compare.py --signed \
    gerfaut-v0.1.0-android-arm64-v8a.apk \
    reproducible/out/gerfaut-v0.1.0-android-arm64-v8a-unsigned.apk
```

`compare.py` reads both zip indexes, hashes every entry, and prints `payload identical, only the signature differs` when they match. Anything else is listed entry by entry, and the exit code is non-zero. It needs nothing but Python.

[apksigcopier](https://github.com/obfusk/apksigcopier), the tool F-Droid and WalletScrutiny reach for, does not work on these APKs. It grafts the signature onto a rebuilt copy of your file, and its zip writer does not reproduce the alignment padding the Android Gradle Plugin writes into each stored entry's extra field. Every entry can be identical and it still reports a digest mismatch. Checked with apksigcopier 1.1.1 on the arm64 APK of this repository: 397 entries came back out with a different extra-field length. Use `compare.py`, which reads the entries instead of rewriting them.

## What is pinned

| Input | Pinned to | Where |
|---|---|---|
| Base image | `eclipse-temurin` 17.0.20+8, by sha256 digest | `reproducible/Dockerfile` |
| Android command-line tools | 23.0, by sha256 of the zip | `reproducible/Dockerfile` |
| Android platforms | `android-36`, `android-35`, `android-34` | `reproducible/Dockerfile` |
| Android build-tools | 36.0.0 | `reproducible/Dockerfile` |
| Android NDK | 28.2.13676358, and 27.0.12077973 for flutter_zxing | `reproducible/Dockerfile` |
| CMake | 3.22.1 | `reproducible/Dockerfile` |
| Flutter | tag 3.47.1, commit asserted after clone | `reproducible/Dockerfile` |
| Rust | 1.97.0 | `reproducible/Dockerfile`, `rust/rust-toolchain.toml` |
| Gradle | 9.3.1 | `android/gradle/wrapper/gradle-wrapper.properties` |
| Android Gradle Plugin, Kotlin | 9.1.0, 2.4.0 | `android/settings.gradle.kts` |
| Dart packages | resolved versions | `pubspec.lock` |
| Rust crates | resolved versions, plus a git revision for the one patched crate | `rust/Cargo.lock`, `rust/Cargo.toml` |
| Rust core revision | full commit sha | `reproducible/gerfaut-core.rev` |

On top of the versions, the container fixes what a compiler could otherwise pick up from its surroundings. The build runs at `/build`, always, so no host path can reach an artifact, and `CARGO_ENCODED_RUSTFLAGS` carries `--remap-path-prefix` entries for the build directory, the cargo home and the rustup home: the only absolute paths left in the shared objects are `/gerfaut/` and `/cargo/`. Incremental compilation is off, the Gradle daemon is off, and Gradle may not download an SDK component it is missing, so anything absent from the image stops the build instead of arriving unpinned. `SOURCE_DATE_EPOCH` is the commit date of what is being built and the timezone is UTC, though neither shows in the APK: the Android Gradle Plugin stamps every zip entry with a constant date of its own. The sources arrive as a `git archive` export with no `.git` directory, which keeps the plugin's version-control block constant too.

## Where the expected hashes live

Two manifests, for two different questions.

`SHA256SUMS`, attached to every release and signed with the author's minisign key, lists the hashes of the signed APKs. It answers "did I download the file the author published?".

The hashes of an unsigned rebuild are printed by `verify.sh` and written next to the APKs in `reproducible/out/`. They are not published as a reference, because a signed APK never hashes the same as an unsigned one. Compare payloads with `compare.py` instead. The `Reproducible build` workflow attaches its own unsigned APKs and their manifest to every run, so you can also check your rebuild against what CI produced from the same tag.

## What is not reproducible, and why

Nothing here is papered over. These are the parts a third party cannot reproduce today, with the reason and the fix where one exists.

### The signature

By design. The release key never leaves the author's machine. Compare payloads, as described above, and check the signing certificate with `apksigner verify --print-certs`.

### The container image itself

Two `docker build` runs of `reproducible/Dockerfile` do not produce the same image bytes: layer archives carry timestamps, and `apt-get install` pulls whatever point release the Ubuntu 22.04 pocket serves that day. This does not affect the APKs, because the packages installed that way (git, curl, unzip, a host C compiler) fetch and link, and none of them contributes bytes to an artifact. What matters is that everything that does contribute (JDK, SDK, NDK, Flutter, Rust) is pinned by digest or exact version.

### Cargokit ignores rust/rust-toolchain.toml

The Gradle plugin that compiles the Rust core runs `rustup run stable cargo build`, which sets `RUSTUP_TOOLCHAIN` and overrides the toolchain file. Inside the container this is handled by pointing the `stable` toolchain directory at the pinned 1.97.0 one, so both agree. Outside the container, a plain `flutter build apk` compiles the core with whatever `stable` your rustup resolves to, and the shared objects will differ. Reproduce inside the container, not on your host.

### Gradle dependencies are not locked

The Android dependency versions come from the Flutter plugins, from AGP and from the Kotlin plugin, and none of them is captured in a lock file. Today they all resolve to fixed versions, so a rebuild matches. A plugin that ever declares a dynamic version would break that silently. The fix is Gradle dependency locking, and it is not in place yet.

### Old releases will stop rebuilding eventually

The Dockerfile downloads the Android command-line tools and the Flutter repository from Google and GitHub. When those disappear, the recipe becomes a description rather than a procedure. Keeping a copy of the built image is the only real answer, and there is no public mirror today.

## What the CI proves, and what it does not

The `Reproducible build` workflow builds the same tag twice in the same image and fails if any artifact hash differs. That catches build-internal randomness: timestamps, hash ordering, parallelism, leftover state.

It does not, on its own, prove that a build on your machine matches. Only your own rebuild does that, which is the whole point of this document.
