# Contributing to Gerfaut

Thank you for your interest in Gerfaut. The project is in early development and moving fast; expect significant changes until the first release.

## Before you start

- Open an issue first for anything beyond a trivial fix. It avoids wasted work on changes that don't fit the roadmap.
- Everything public happens in English: issues, pull requests, code, comments, commit messages.
- Security vulnerabilities are never reported through issues or pull requests. See [SECURITY.md](SECURITY.md).

## License of contributions

Gerfaut's code is licensed under the GNU Affero General Public License v3.0 (AGPL-3.0-only), with copyright kept centralized. This is what makes commercial licensing and signed store builds possible, and those are what fund the project.

By submitting a contribution (pull request, patch, or code suggestion), you agree that:

1. Your contribution is licensed under the AGPL-3.0, like the rest of the project.
2. You grant Loïc Morel a perpetual, worldwide, irrevocable right to also license your contribution under other terms, for example a commercial license, or the exceptions required for app-store distribution.
3. You wrote the contribution yourself, or otherwise have the right to submit it under these terms.

Accepted contributions remain published under the AGPL forever. There is no CLA to sign; submitting a pull request constitutes agreement.

## The one hard rule

Gerfaut is watch-only. The codebase contains no code that generates keys, handles seeds, or signs transactions, and pull requests introducing any of it will be closed.

## Build and test

The Rust core lives in its own repository, and the app builds it from the folder next to its own, `../gerfaut-core`. Clone both side by side, then check out the core at the revision this repository names:

```
git clone https://github.com/gerfaut-wallet/gerfaut-mobile
git clone https://github.com/gerfaut-wallet/gerfaut-core
cd gerfaut-mobile
git -C ../gerfaut-core checkout "$(cat reproducible/gerfaut-core.rev)"
```

You need Flutter 3.47.1, Rust 1.97.0 with the three Android targets listed in `rust/rust-toolchain.toml`, and the Android SDK with the NDK that Flutter asks for. Before you push, run what CI runs:

```
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test
cd rust && cargo fmt --check && cargo clippy --all-targets -- -D warnings && cargo test
```

`flutter build apk --debug` builds an APK for an emulator or a phone. Release APKs come from the pinned container described in [docs/REPRODUCIBLE-BUILDS.md](docs/REPRODUCIBLE-BUILDS.md).

When you change a function in `rust/src/api/`, regenerate the Dart side of the bridge with `flutter_rust_bridge_codegen generate`, version 2.12.0 like the crate, and commit `lib/src/rust/` along with it.

## Pull requests

- Keep them small and focused, one concern per pull request.
- Write commit messages in English, imperative mood, with a short subject line.
- Make sure formatting, lints and tests pass before pushing. See [Build and test](#build-and-test).
- Brand assets (name, logo, visual identity) are out of contribution scope. See [TRADEMARK.md](TRADEMARK.md).
