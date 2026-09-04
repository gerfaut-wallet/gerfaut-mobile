# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The first release: Gerfaut for Android.

### Added

- Watch a wallet from whatever you already have: a descriptor, an extended
  key, a single public key, a plain address, a multisig setup, a BSMS record,
  or another wallet's export file. Paste it, pick a file, or scan the QR code,
  static or animated. Gerfaut works out the format on its own and shows what
  it understood before writing anything down.
- Balance, transaction history and UTXOs per wallet, with the fiat value of
  the day and one tap to hide every amount on screen.
- Receive addresses with their QR code, the used ones marked, and a warning
  past the gap limit.
- A Policy page for every wallet: what the descriptor allows, branch by
  branch, with each timelock counted down in blocks and in days.
- Broadcast a signed transaction or a PSBT, read back in plain language
  before it goes anywhere.
- Your own node over Electrum or Esplora, or one of the public servers. A
  self-signed certificate is shown and trusted once, then refused if it ever
  changes.
- A Tor client built in: an .onion backend works with no Orbot installed.
- An encrypted backup file, and the same backup as an animated QR code, so
  two devices sync with no server in between.
- A PIN or password lock with biometrics, attempts slowed after three tries
  and still slowed after a restart, and a calculator disguise for the icon.
- Home screen widgets for the price, the balance (hidden by default) and the
  block height.
- Local notifications when a sync finds something new. Nothing leaves the
  phone for them.
- Signet, testnet4 and regtest alongside mainnet.
