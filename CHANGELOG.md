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
- Gerfaut marks a descriptor or a policy you copy from the app as sensitive
  on the clipboard: the system shows no preview of it and keeps it out of its
  history. It also leaves the clipboard a minute later, unless you copied
  something else since, and the confirmation says "for 1 minute".
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
  clears Gerfaut's notifications from the shade.
- On a phone whose maker adds a battery manager of its own (Xiaomi, Redmi,
  POCO, Huawei, Honor, Samsung, OnePlus, Oppo, realme), the Live sheet lists
  the switches to turn on there and opens Gerfaut's app info page, where most
  of them live. No app can flip those switches for you. A step that only
  repeats Android's battery exemption is left out once you have granted it.
- A "This is my node" switch under the address of your own Electrum or
  Esplora server, in Settings › Network. When it is on, Live follows up to
  20 000 addresses instead of 2 000. Leave it off for a server you do not
  run: it would refuse most of them, and learn every one. Saving the server
  address again keeps the switch as it was.
- When Live cannot follow every address, Settings › Notifications says how
  many addresses of how many wallets are checked at the next sync instead,
  and how to lift the limit. Each wallet then shows "Live", "Partly live" or
  "At next sync" on its card, on its page and in Settings › Wallets. On your
  own node, if the server itself refuses addresses, the note names the
  server setting that lets it follow more.
- Settings › Wallets › Advanced › "Always watch live first" picks the
  wallets Live follows before the others when it cannot follow every
  address.
- When Android stops letting Gerfaut's notifications through, from the
  system settings or by blocking the channel, Settings › Notifications says
  so in amber under New transactions, with a button to the system settings.
  Live stops meanwhile, since it would have nothing to say, and starts again
  once they get through.
- While the app is disguised, the notification settings are greyed out, with
  a line that says why: a notification would show the name Gerfaut. The
  sheet that turns the disguise on says so before you confirm.
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

- Syncs use far less data. Gerfaut now downloads only what a wallet does not have yet, and a payment that Live notices costs a few kilobytes instead of the wallet's whole history. A wallet is still read in full when the vault opens and once a day.
- Fiat values group their thousands with a space, like amounts in BTC and
  sats.
- In Add a wallet, the script type choices give the address prefixes of the
  wallet's network, such as tb1q on signet and testnet4.
- Broadcast warns in red when a signature leaves the outputs open
  (SIGHASH_NONE or SIGHASH_SINGLE). Whoever relays such a transaction can
  send that money elsewhere, so the page tells you not to send it as it is.
  When the outputs pay more than the inputs bring, the last check before
  sending says the network will refuse it.
- Coming back from a file picker, a save dialog or a share sheet more than
  ten minutes after it opened asks for the app lock again. Before, that trip
  never locked the app, however long it lasted.
- A release build no longer writes the text of an unexpected error to the
  system log, where it could quote an address.
- When every wallet is on the selected network, the backup export says
  "All wallets (N)" instead of offering a choice of one.
- In Add a wallet, an input that fits a single network, such as a mainnet
  address, names that network instead of offering a choice of one.
- The Policy page now reads like the desktop one. The primary paths come
  first, then the recovery and emergency ones, each sorted from the nearest
  lock to the farthest. A single coin is counted like several, as in
  "1 of 1 coin unlocked", and a Next coin line gives the wait of the first
  coin to unlock, in blocks and in days.
- On the Policy page, a coin that cannot be counted down before the first
  sync says "next known after the first sync" instead of "next in an unknown
  time".
- TalkBack now calls the pin icon "Pin", like the desktop app, instead of
  "Map pin".

### Fixed

- The vault opens in one place at a time. When the app, a background check
  and Live start together, they now share that one opening instead of the
  later ones failing. If the vault is still held elsewhere, Gerfaut says it
  is already open and offers to try again. It never sets that vault aside,
  and a background check quietly skips its turn.
- Receive offers only addresses nobody has paid yet, and stops 200
  addresses past the next unused one. The gap limit warning counts unused
  addresses in a row, as scanning software does, and a descriptor with a
  single address offers no next one.
- The wallet file picker shows every file, so a .bsms or .desc file can be
  picked. It used to grey them out.
- When the app refuses a backend, for example a host with a port still in
  it, the reason now shows under the Save button. The save used to stop
  without a word.
- A private key in a pasted wallet, a file or a backup is refused with a
  sentence that says what to bring instead. A descriptor the wallet engine
  refuses says so, with the engine's reason.
- The UTXOs tab keeps its rows on screen while a sync reads them again,
  instead of flashing "Loading UTXOs…". A coin with no address says "n/a",
  and TalkBack says which chip holds the outpoint and which the address.
- A QR code that announces more than 10,000 parts is refused before it is
  read. One such frame used to make the app quit.
- Importing a wallet, a transaction or a backup from a file that is too
  large, such as a video, now says so. The app used to read the whole file
  first, which could make it quit. A wallet file that is not text says so
  too.
- Turning Live off and on again within a few seconds now starts it again.
  It used to stay off until the app came back to the screen.
- With Live on, removing your last wallet left the permanent notification
  on "Connecting…" for good. Live now stops, notification included, while
  the selected network has no wallet, and starts again by itself when you
  add one.
- With the screen off, Live now keeps the phone awake while it checks the
  server, and until it has announced a new transaction, so the notification
  arrives within seconds rather than at the next check. A status that
  changes nothing keeps nothing awake.
- When Android refuses to restart Live, Gerfaut waits longer before each new
  attempt, instead of waking the phone every few minutes.
- Receive offers a fresh address after every sync, Live's included. It used
  to keep showing an address that had just been paid, until the app
  restarted.
- Picking "Automatic" as the public server works again after choosing a
  named one.
- The welcome tour opened from Settings › About now closes with Skip and Get
  started.
- A restore or a broadcast interrupted by the app lock now finishes: the
  restored wallets show, and the transaction joins Recent broadcasts.
- Policy › Descriptor shows and copies the whole wallet as one multipath
  descriptor, with /<0;1>/*. It used to give the receive branch alone, which
  would watch the wallet without its change.
- When the server itself refuses addresses, Settings › Notifications says
  so, instead of blaming Live's own limits.
- When a server takes only a certain number of your addresses, Live now
  asks it again for all of them a day later, or an hour later when it took
  none. Before, it waited until you changed the server settings or Live
  started again, so a server that took no address could leave Live off for
  days. Two refusals still hold until you change the server settings or Live
  starts again: a single address the server turns down, such as one with a
  history too long for it, and a cut from an ElectrumX server when Live uses
  too much of its resources. After such a cut, Live asks for fewer
  addresses, since asking for all of them would only get it cut off again.
- In Add a wallet, a QR code that gives no receive or change path now says
  that Gerfaut assumes the usual 0/* and 1/*, and asks you to compare the
  first address with your signer.
- The price widget now gives the date of a price that is not from today, as
  in "as of Oct 03, 09:41". It used to give the time alone, so a price kept
  for days read like one from this morning.
- "Synced 5 min ago" and the other "ago" lines move on while a page stays
  open.
- A page that fails to load, such as a wallet, its UTXOs, a transaction or
  the wallet list, says why and offers Try again. A list of UTXOs that
  failed to load no longer reads as an empty one.
- A refused rename stays in its dialog with the reason, and a failed "Load
  older transactions" says why under the button, instead of in a toast gone
  before you read it.
- TalkBack names every switch, field and checkbox, reads errors aloud, says
  "Hidden amount" instead of reading out dots, and reads a transaction ID
  once.
- Everything you can tap, address chips included, now has a touch area of
  at least 48 by 48 dp, the minimum Android asks for. Most buttons and
  fields look the same: the extra room is invisible padding around them.
- With fiat values on, a wallet on signet, testnet4 or regtest now shows 0
  in your currency. Test coins have no price, yet Gerfaut used to value them
  at the price of real bitcoin. A zero amount also reads €0.00 instead of
  €0.0000.
- The app lock sheet takes only digits for a PIN, on the number keyboard,
  and counts its length the way the app does when it saves it.
- Saving a file to a slow cloud provider no longer freezes the screen.
- Gerfaut no longer requires a camera to install. Scanning stays optional.
- A wallet added on another network opens even when switching to that
  network fails.
- On the import screen, the first address now belongs to the network you
  pick, and changes when you pick another one. A key added on regtest shows
  its bcrt1 address, not the tb1 address of signet.
- While Test the connection starts the built-in Tor, the Tor card now counts
  up in steps of ten, as in "Starting the built-in Tor… 40%". Before, the
  card stayed still until the test ended.
- Forgetting a certificate now says that syncs with that server fail until
  you press Save backend again and accept it. When the server does not
  answer at Save backend, the note says the same of a server that signs its
  own certificate. Both texts used to say that Gerfaut would ask again at
  the next connection, which it does not.
- On an Esplora server, Live now polls every address in turn. It used to
  start over at the top of the list each time it reconnected, every half
  hour, so it never reached the addresses further down, and a payment to one
  of them waited for the next sync.

### Security

- The price now goes through Tor whenever one of your nodes is a .onion
  address, on any network, and is not asked at all while Tor is out of
  reach, because the price sources would otherwise see the phone's IP
  address. The Tor card says so. The price is also no longer asked for while
  the app is out of sight.
- With a .onion node, the price widget never starts Tor for the price alone.
  While Gerfaut is closed, it asks for the price only through a Tor that is
  already running, such as the one a sync started or Orbot, and otherwise
  keeps the last price with the time it was fetched.
- While an app lock is set, the balance widget shows no wallet name and no
  amount. On the Widgets card in Settings › Notifications,
  "Show balances on widgets" is greyed out until the lock is removed.
- Under the calculator disguise, a vault that fails to open shows the
  calculator, not Gerfaut's error page.
- A transaction history shared as CSV no longer stays in the app's cache:
  Gerfaut deletes the copy the share sheet needed at the next share, or when
  it next starts.
