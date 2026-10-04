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
  preview of it and keeps it out of its history. It also leaves the
  clipboard a minute later, unless you copied something else since, and the
  confirmation says "for 1 minute".
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
- On a phone whose maker adds a battery manager of its own (Xiaomi, Huawei,
  Samsung, OnePlus, Oppo, realme), the Live sheet lists the switches to turn
  on there and opens Gerfaut's app info page, where most of them live. No
  app can flip those switches for you. A step that only repeats Android's
  battery exemption is left out once you have granted it.
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
- While the app is disguised, the notification settings are greyed out, with
  a line that says why: a notification would show the name Gerfaut. The
  sheet that turns the disguise on says so before you confirm and, with
  Premium on, adds that its alerts still reach your channels.
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
- A Premium channel that has delivered nothing for an hour or more reads
  "Not delivering", with the last error the server got and what to do for
  that kind of channel.
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
- When the Premium server's code cannot go into the Telegram link, the page
  asks you to type it to the bot, instead of promising that Start sends it
  for you.
- Premium requests go through Tor as soon as any network has a .onion
  backend, not only the network on screen, and the Tor notice says so.
- A Telegram link now opens in Telegram itself, or in a browser tab when
  Telegram is not installed. On older Android versions any app that claimed
  t.me links could receive the code that connects a chat to your alerts.
- Coming back from a file picker, a save dialog or a share sheet more than
  ten minutes after it opened asks for the app lock again. Before, that trip
  never locked the app, however long it lasted.
- A release build no longer writes the text of an unexpected error to the
  system log, where it could quote an address.
- Premium controls and the Premium settings row now use the Premium colour,
  so what belongs to the paid service reads as such at a glance: the card
  icons, the switch that hands a wallet to the server, and the buttons that
  activate a key, confirm the watch or add a channel.

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
- The "watch is offline" banner now goes away when you forget the Premium
  key or stop watching the last wallet during an outage. Tapping
  Acknowledge twice writes it once, and a failed write leaves the banner up.
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
- Leaving Settings › Premium before the server answers no longer leaves the
  app out of date. Forget the key and go back right away: the Premium row in
  Settings now reads "Not activated" as soon as the server answers, instead
  of showing the old key until the app restarts. Every other Premium action
  behaves the same.
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
- Every small target, the address chips included, is now at least 44 dp
  high.
- The app lock sheet takes only digits for a PIN, on the number keyboard,
  and counts its length the way the app does when it saves it.
- Saving a file to a slow cloud provider no longer freezes the screen.
- Gerfaut no longer requires a camera to install. Scanning stays optional.
- A double tap on the switch that hands a wallet to Premium opens one
  consent page, not two.
- A wallet added on another network opens even when switching to that
  network fails.

### Security

- The price is no longer fetched while Gerfaut goes through Tor, since the
  price sources would see the phone's address. Amounts then show without
  fiat. The price is also no longer asked for while the app is out of sight.
- While an app lock is set, the balance widget names no wallet.
- Under the calculator disguise, a vault that fails to open shows the
  calculator, not Gerfaut's error page.
- Sharing the transaction history as CSV no longer leaves a copy in the
  app's cache.
