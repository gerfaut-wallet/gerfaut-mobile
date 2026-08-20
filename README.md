# gerfaut-mobile

**[Gerfaut](https://github.com/gerfaut-wallet) for Android and iOS — Bitcoin watch-only wallet.**

![Status: pre-alpha](https://img.shields.io/badge/status-pre--alpha-orange) ![License: AGPL-3.0-only](https://img.shields.io/badge/license-AGPL--3.0--only-blue)

> **Status: pre-development.** Repository conventions and scaffolding only — no code yet.

Watch your coins without ever exposing them: Gerfaut holds no private keys. It watches descriptors, shows balances and history, and alerts you when something moves.

## Scope

- Flutter app for Android and iOS
- Wallet logic delegated to [`gerfaut-core`](https://github.com/gerfaut-wallet/gerfaut-core) (Rust) via `flutter_rust_bridge`
- Native code kept to what must be native: home-screen widgets, push notifications, biometric unlock

## Watch-only, by design

No key generation, no seed handling, no signing — anywhere in the app. There is no "Send" button. See [CONTRIBUTING.md](CONTRIBUTING.md).

## Project

| Repository | Role |
|---|---|
| [`gerfaut-core`](https://github.com/gerfaut-wallet/gerfaut-core) | Core Rust library |
| `gerfaut-mobile` | Mobile app — this repository |
| [`gerfaut-desktop`](https://github.com/gerfaut-wallet/gerfaut-desktop) | Desktop app (Tauri v2 — Windows, macOS, Linux) |
| [`gerfaut-web`](https://github.com/gerfaut-wallet/gerfaut-web) | Website, documentation, downloads |

## License

[AGPL-3.0-only](LICENSE). Commercial licensing: **info@pandul.fr**.

The Gerfaut name and logo are not covered by the code license — see [TRADEMARK.md](TRADEMARK.md).

## Security

Report vulnerabilities privately — see [SECURITY.md](SECURITY.md).
