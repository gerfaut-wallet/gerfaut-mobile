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
- Hold a wallet card and drag it into the order you want, on the home screen
  and in the settings. When the vault cannot keep the new order, a note above
  the cards says so, with a button to try again.
- Receive addresses with their QR code, the used ones marked, and a warning
  past the gap limit.
- A Policy page for every wallet: what the descriptor allows, branch by
  branch, with each timelock counted down in blocks and in days.
- Broadcast a signed transaction or a PSBT, read back in plain language
  before it goes anywhere. When no backend could confirm a coin it spends,
  Gerfaut marks the amounts and the fee as the file's claims rather than
  the chain's, and says what to check before sending.
- Your own node over Electrum or Esplora, or one of the public servers. A
  self-signed certificate is shown and trusted once, then refused if it ever
  changes.
- A Tor client built in: an .onion backend works with no Orbot installed.
- An encrypted backup file, and the same backup as an animated QR code, so
  two devices sync with no server in between. The export page asks for a
  passphrase of several words, since a copied file can be guessed offline;
  the restore page lists what the file holds, wallet by wallet and node
  setting by node setting, before it writes anything. If the system's save
  dialog cannot open, the page says so in place, like any other failure.
- The vault stays out of Android's own backups and device-to-device
  transfers. It leaves the phone only as a Gerfaut backup, sealed under your
  password.
- A vault this phone can no longer open is never overwritten: Gerfaut sets
  it aside under another name and offers to start over, with the restore
  page first.
- A PIN or password lock with biometrics, attempts slowed after three tries
  and still slowed after a restart, and a calculator disguise for the icon.
- A secret copied from the app, an extended key, an ntfy topic or the
  account key, is marked sensitive on the clipboard: the system shows no
  preview of it and keeps it out of its history.
- Home screen widgets for the price, the balance (hidden by default) and the
  block height.
- Local notifications when a sync finds something new. Nothing leaves the
  phone for them.
- Live watch, a new choice under Settings, Notifications. Gerfaut keeps a
  connection open to the backend your syncs already use, and tells you when
  a transaction reaches the mempool, then again at its first confirmation.
  From an Electrum server that takes a few seconds; an Esplora server can
  only be polled, so it takes longer. With the Automatic backend, the
  connection goes first to an Electrum server run by one of the operators
  the syncs rotate through. Live runs with the app closed and comes back
  after a restart of the phone. Android requires a small permanent
  notification for it, which has a Stop button. A sheet explains all this
  before anything is turned on, then asks for the battery exemption, which
  you can refuse. The server learns what a sync already tells it, plus how
  long your phone stays connected and from where. A check every 15 minutes
  stays scheduled for whenever Android stops Live. Force-stopping the app
  ends Live until you open Gerfaut again, and what arrived in the meantime
  is announced then. Turning the calculator disguise on turns Live off and
  clears Gerfaut's notifications from the shade. Battery use has not been
  measured on a phone yet.
- A transaction is announced once when it appears and once when it confirms,
  whichever part of the app saw it first. A fee bump brings no second
  notice, and its confirmation takes the place of the pending one. An
  incoming payment that leaves the mempool before it confirms, with nothing
  in its place that pays the wallet, gets one more notice saying it is no
  longer coming. While an app lock is set, a notification names no wallet
  and no amount: it is titled Gerfaut and only says what happened, as in
  "New transaction · pending". Without a lock it is titled with the wallet's
  name, and hiding the balances keeps the amount out of it.
- Signet, testnet4 and regtest alongside mainnet.
- Gerfaut Premium, as an eighth section of the settings. Enter the account
  key bought on gerfaut-wallet.com, switch a wallet on, and the server
  watches it from there; before the first one leaves the phone, a page says
  in plain words what the server will learn, and the row says "First scan
  pending" until the server has been through the wallet once. A wallet
  removed from the phone is taken off the server with it, and one the server
  still watches that this phone no longer has is listed with a way off.
  Taking a wallet off the server also deletes its alert history there, so
  Gerfaut says so and asks before doing it, whether from the switch or when
  the wallet is removed from the phone. A wallet made of a single address
  can be watched too: only that address is sent. When the server refuses a
  wallet, its row says why in the words of the server.
- Alerts reach the ntfy app, Telegram, an e-mail address or a webhook of
  yours, and the last 20 are listed in the app. An e-mail address receives a
  6-digit code first, typed back under its row, and nothing is sent to it
  before; a Telegram channel names the chat it reaches; a webhook the server
  turned off, because it points at a private address, says so with what to
  do about it.
- Forgetting the key can take the account with it: the server then deletes
  the wallets it watches, the channels and the log, and whatever paid time
  the key had left goes with them. Premium calls go through Tor whenever the
  node connection does, never around it. When the server misses 2 heartbeats
  in a row, a red banner on the home screen says so until you acknowledge it.
- Premium devices. The account key connects this phone to the account. In
  return, the server hands the phone a token of its own, which the encrypted
  vault keeps and never shows, and every request after that carries this token
  instead of the key. The first device an account ever has gets full access at
  once. Any later device waits 10 days, or until a device with full access
  approves it, and in the meantime it sees nothing and changes nothing.
- A Devices card in Settings › Premium lists every device that entered the
  key, with its platform, the day it connected, and either full access or the
  number of days it still has to wait. From there, you approve or refuse a
  waiting device, or disconnect another one.
- While a device waits for approval, a red banner at the top of the home
  screen says so, and its Review button opens the Devices card. The banner
  goes away on its own once nothing waits. When notifications are on, a
  notification also announces each new device, once. While an app lock is set,
  it names neither the device nor the account, and nothing is posted while the
  app is disguised. Gerfaut checks the list when it opens, when it comes back
  to the front, and every 5 minutes while it stays on screen. In the
  background, it asks nothing.
- A phone waiting for approval sees a single card in place of the account: the
  day it connected, the day it gets full access without approval, and a Check
  again button. It also checks its own standing every 5 minutes while the app
  is on screen, keeps checking when an attempt fails, and opens up on its own
  as soon as another device approves it.
- Change key replaces the account key. The old key stops working at once, on
  the website too, and the server disconnects every other device. The new key
  is shown once, with a Copy button, and the sheet stays open until you tick
  "I saved my new key".
- A phone the server disconnected says so under the Licence card, in the
  server's own words when it gave some, with a Connect again button. If the
  key was changed on another device, the key field comes back so you can enter
  the new one. Forget this key sits beside it, for when you do not have the
  new key.
- After the first connection, a Protect your Premium account card suggests 3
  things: connect a second device, turn on the app lock, and save the key in a
  password manager. Each step ticks itself as soon as Gerfaut can tell it is
  done, and you can hide the card.
- Before approving, refusing or disconnecting a device, changing the key,
  deleting the account, taking a wallet off the server, removing a wallet the
  server watches or removing a channel, Gerfaut asks you to confirm it's you.
  Concretely, it asks for the app lock's PIN, password or fingerprint, and
  checks it the way the lock screen does. Without an app lock, the phone's own
  screen lock answers instead, and it is also asked before a first app lock is
  set on a phone that holds a Premium key, or is still connecting one:
  otherwise, whoever holds the phone unlocked could choose a PIN and answer
  with it. Gerfaut also asks before you forget the key on a phone with full
  access or enter another key on it. While the app lock is on, it asks too
  before you add a channel, or open again the subscribe link or the link code
  of an existing one. A phone with no lock at all is sent to Settings ›
  Security to set one.
- Forget this key also disconnects this phone from the account on the server.
  Connecting it again takes a new approval, or 10 days.
- A lost answer from the Gerfaut server costs neither the key nor a device.
  When a connection never gets its answer back, Gerfaut sends the exact same
  request again on its own: when the app opens, when it comes back to the
  front, and at each heartbeat. When a key change never gets its answer back,
  the Licence card says "The key change did not finish. Try again to complete
  it." with a Try again button, which sends the same new key. Until then,
  Gerfaut offers no key to copy, and a connected phone can neither change nor
  forget its key, since only this phone holds the new one. If you forget the
  key while the server is out of reach, Gerfaut tells the server as soon as it
  can, at the same moments.
- The Licence card offers Copy key until you mark the key as saved. When the
  clipboard refuses a copy, an amber note under the button says so and stays
  there. Hide and Mark as done on the Protect card do the same when the vault
  cannot save them.
- When the server asks to wait, the note says how long, in seconds, minutes or
  hours.
- One APK per processor architecture instead of one carrying all three:
  50 MB to download on a 64-bit ARM phone rather than 127.
- Reproducible builds. The APKs are built in a container where every tool
  version is pinned, so the same commit always produces the same bytes.
  Rebuild them yourself and compare; only the signature should differ.
  See `docs/REPRODUCIBLE-BUILDS.md`.
- A notice on the home screen when a newer release is out, with a button to
  the release page and a Later button that closes it for that release. To
  know, Gerfaut asks GitHub for the latest release once a day at most, when
  you open it. When one of your nodes is a .onion address the request goes
  through Tor, or not at all if Tor cannot be reached. Nothing is asked
  while the app is disguised. The About settings turn it off, and keep the
  check on demand.

### Changed

- Premium controls and the Premium settings row now use the Premium colour,
  so what belongs to the paid service reads as such at a glance: the card
  icons, the switch that hands a wallet to the server, and the buttons that
  activate a key, confirm the watch or add a channel.
