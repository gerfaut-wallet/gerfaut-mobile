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

A signed APK is built by CI from every `v*` tag and published on the [releases page](https://github.com/gerfaut-wallet/gerfaut-mobile/releases). Each release ships a `SHA256SUMS` manifest signed with the author's [minisign](https://jedisct1.github.io/minisign/) key:

```
RWTz3c4gUmglCX5Uvjthigz1ts3TS3ZSdhRNpFgOJRW/Wr4XjGlqTR3O
```

Verify a download in two steps: `minisign -Vm SHA256SUMS -P <key>` proves the manifest comes from the author, then `sha256sum --check SHA256SUMS --ignore-missing` proves your file matches it.

## License

[AGPL-3.0-only](LICENSE). Commercial licensing: info@pandul.fr.

The Gerfaut name and logo are not covered by the code license. See [TRADEMARK.md](TRADEMARK.md).

## Security

Report vulnerabilities privately. See [SECURITY.md](SECURITY.md).
