# gerfaut-mobile

[Gerfaut](https://github.com/gerfaut-wallet) for Android, a Bitcoin watch-only wallet.

![Status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange) ![License: AGPL-3.0-only](https://img.shields.io/badge/license-AGPL--3.0--only-blue)

> Status: pre-alpha. The app builds and runs: wallet import with explicit confirmation, balances, transaction history, UTXO view, receive addresses, and settings. Interfaces are still moving.

Watch your coins without ever exposing them: Gerfaut holds no private keys. It watches descriptors, shows balances and history, and alerts you when something moves.

## Scope

- Flutter app, Android first. An iOS version is planned for a later stage, and the codebase stays portable by construction.
- Wallet logic delegated to [`gerfaut-core`](https://github.com/gerfaut-wallet/gerfaut-core) (Rust) via `flutter_rust_bridge`
- Native code kept to what must be native: home-screen widgets, push notifications, biometric unlock

## Watch-only, by design

The app contains no code to generate keys, handle seeds, or sign transactions. There is no "Send" button. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Project

| Repository | Role |
|---|---|
| [`gerfaut-core`](https://github.com/gerfaut-wallet/gerfaut-core) | Core Rust library |
| `gerfaut-mobile` | Mobile app, this repository |
| [`gerfaut-desktop`](https://github.com/gerfaut-wallet/gerfaut-desktop) | Desktop app (Tauri v2, for Windows, macOS, and Linux) |
| [`gerfaut-web`](https://github.com/gerfaut-wallet/gerfaut-web) | Website, documentation, downloads |

## Releases

Every `v*` tag makes CI build three APKs in a pinned container, one per processor architecture. They come out unsigned: the release key never leaves the author's machine, which signs them and publishes them on the [releases page](https://github.com/gerfaut-wallet/gerfaut-mobile/releases):

| File | Architecture | For |
|---|---|---|
| `gerfaut-<version>-android-arm64-v8a.apk` | 64-bit ARM | almost every phone, take this one |
| `gerfaut-<version>-android-armeabi-v7a.apk` | 32-bit ARM | older or entry-level devices |
| `gerfaut-<version>-android-x86_64.apk` | Intel and AMD | emulators, Chromebooks |

Every Android phone sold since roughly 2017 runs on 64-bit ARM, so `arm64-v8a` is the answer unless you know otherwise.

Each release ships a `SHA256SUMS` manifest signed with the author's [minisign](https://jedisct1.github.io/minisign/) key:

```
RWTz3c4gUmglCX5Uvjthigz1ts3TS3ZSdhRNpFgOJRW/Wr4XjGlqTR3O
```

Verify a download in two steps: `minisign -Vm SHA256SUMS -P <key>` proves the manifest comes from the author, then `sha256sum --check SHA256SUMS --ignore-missing` proves your file matches it. Android checks the APK signature on its own; the certificate's SHA-256 fingerprint is listed in [docs/REPRODUCIBLE-BUILDS.md](docs/REPRODUCIBLE-BUILDS.md) if you want to compare it with `apksigner verify --print-certs`.

## Reproducible builds

The APKs are built in a container where every tool version is pinned, so the same commit always produces the same bytes. You can rebuild a release yourself and check that only the signature differs from the published file. See [docs/REPRODUCIBLE-BUILDS.md](docs/REPRODUCIBLE-BUILDS.md).

## License

[AGPL-3.0-only](LICENSE). Commercial licensing: info@pandul.fr.

The Gerfaut name and logo are not covered by the code license. See [TRADEMARK.md](TRADEMARK.md).

## Security

Report vulnerabilities privately. See [SECURITY.md](SECURITY.md).
