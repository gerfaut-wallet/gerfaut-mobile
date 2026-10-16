# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

The first release: Gerfaut for Android, as a public beta.

Gerfaut watches bitcoin wallets it cannot spend from. There is no key generation, no seed handling and no signing anywhere in the code, and no Send button in the interface.

### Added

#### Watching a wallet

- Watch a wallet from what you already have: a descriptor, an extended or single public key, a plain address, a multisig setup, a BSMS record or another wallet's export file. Paste it, pick a file, or scan its QR code, static or animated.
- Gerfaut works out the format on its own and shows what it understood, with the first address, before it stores anything. A private key is refused, with a sentence that says what to bring instead.
- Watch several wallets on mainnet, signet, testnet4 or regtest. Hold a wallet card and drag it into the order you want, on the home screen and in the settings.
- For each wallet: the balance, the transaction history and the UTXOs, with one action to hide every amount on screen.
- Receive addresses with their QR code. Receive offers only addresses nobody has paid yet, a fresh one after every sync, up to 200 past the next unused one, and the gap limit warning counts the unused addresses in a row.
- A Policy page for every wallet: what the descriptor allows, branch by branch, primary paths first, with each timelock counted down in blocks and in days. Its Descriptor section shows and copies the whole wallet as one multipath descriptor, with `/<0;1>/*`.
- Export the history of a wallet as CSV, filtered by date and direction, to a file or through the share sheet.
- Home screen widgets for the price, the balance (hidden by default) and the block height.

#### Broadcasting a signed transaction

- Broadcast a signed transaction or a PSBT, read back in plain language before it goes anywhere. When no backend could confirm a coin it spends and only the PSBT declares its amount, Gerfaut marks the amounts and the fee "as the PSBT claims" and says what to check before sending.
- A signature that leaves the outputs open (SIGHASH_NONE or SIGHASH_SINGLE) gets a red warning: whoever relays such a transaction can send that money elsewhere. A transaction the network is sure to refuse, such as one that spends a coin already spent in a block, reads "Will be refused" and cannot be sent.

#### Talking to the chain

- Public servers by default, or your own node over Electrum or Esplora. A self-signed certificate is shown and trusted once, then refused if it ever changes.
- A Tor client built in, so a `.onion` backend works with no Orbot installed. While "Test the connection" starts it, the Tor card shows its progress.
- A sync downloads only what a wallet lacks, so a payment that Live notices costs a few kilobytes. Gerfaut reads a wallet in full when the vault opens and once a day.
- A "This is my node" switch under the address of your own server, in Settings › Network. Turned on, it lets Live follow up to 20,000 addresses, against 2,000 otherwise. Leave it off for a server you do not run: it would refuse most of them and learn every one.
- With Live on and the Automatic backend, syncs go first to the server Live talks to, Blockstream's Electrum server on mainnet, so a single operator sees your addresses. A broadcast and a transaction preview go to the rotation, which starts with mempool.space.

#### Getting told when something moves

- "Check for transactions", in Settings › Notifications, syncs your wallets while Gerfaut is closed, every 15 minutes, every hour or every 6 hours, and posts a local notification when a sync finds something new.
- Live, another choice under "Check for transactions", keeps a connection open to the backend your syncs already use. It tells you when a transaction reaches the mempool, then again at its first confirmation: within seconds from an Electrum server, later from an Esplora server, which Live polls, going through every address in turn.
- Live runs with the app closed and comes back after the phone restarts, behind the small permanent notification Android requires, which has a "Stop" button. A check every 15 minutes stays scheduled for whenever Android stops Live.
- Before Live starts, a sheet explains what it does and what the server learns, then asks for the battery exemption, which you can refuse. On a Xiaomi, Redmi, POCO, Huawei, Honor, Samsung, OnePlus, Oppo or realme phone, it also lists the switches to turn on in the maker's battery manager. A button opens Gerfaut's app info page.
- Each transaction is announced once when it appears and once when it confirms, whichever part of the app saw it first. A fee bump brings no second notice. An incoming payment that leaves the mempool with nothing in its place gets one more notice saying it is no longer coming. Past 3 transactions in one wallet at once, one line counts the rest, and notices stop at 20 a minute.
- "Show wallet and amount", a switch in Settings › Notifications, decides whether a notification names the wallet and gives the amount. It is on by default and applies whether the app is locked or not. Turned off, a notification only says what happened, as in "New transaction · pending", and hidden balances keep the amount out either way.
- When Android stops letting Gerfaut's notifications through, Settings › Notifications says so in amber, with a button to the system settings. Live waits meanwhile and starts again once they get through.
- When Live cannot follow every address, Settings › Notifications says how many addresses of how many wallets wait for the next sync, and how to lift the limit. Each wallet shows "Live", "Partly live" or "At next sync" on its card, on its page and in Settings › Wallets, and "Always watch live first", under Settings › Wallets › Advanced, picks the wallets Live follows first.
- When a server takes only part of your addresses, Live asks it again for all of them a day later, or an hour later when it took none. On your own node, when the server itself refuses addresses, the note names the server setting that lets it follow more.

#### Keeping it yours

- An encrypted backup file, and the same backup as an animated QR code, so another device gets your wallets with no server in between. The export page asks for a passphrase of several words, since a copied file can be guessed offline, and can add your node settings. The restore page lists what the file holds, wallet by wallet and node setting by node setting, before it writes anything.
- The vault stays out of Android's own backups and device-to-device transfers: it leaves the phone only as a Gerfaut backup, sealed under your password.
- A vault this phone cannot open, such as one restored without its key, is never overwritten. Gerfaut sets it aside under another name and offers to start over, with the restore page first.
- Fiat value beside the balances and the transaction amounts, in the currency you pick, from CoinGecko, Kraken or mempool.space. No price source hears from Gerfaut until you turn "Fiat value" on or place the price widget. A wallet on signet, testnet4 or regtest shows 0 in your currency, since test coins are worth nothing.
- Amounts in BTC or in sats, and a light, dark or system theme.
- A PIN or password lock with biometrics. Attempts slow down after 3 tries and stay slowed after a restart, and coming back from a file picker, a save dialog or a share sheet more than 10 minutes after it opened asks for the lock again.
- A calculator disguise for the icon. While Gerfaut is disguised, it posts no notification, Live stays off and no update check goes out.
- A notice on the home screen when a newer release is out, with a button to the release page and a "Later" button that closes it for that release. Gerfaut asks GitHub at most once a day, when you open it, and Settings › About turns the automatic check off.
- Settings › About marks a 0.x version as a beta, with a "Report a problem" button that opens the issues of this repository. The first page of the welcome tour says that Gerfaut is in public beta.
- One APK per processor architecture, so a phone downloads only the code it runs. Gerfaut installs on a phone without a camera, and scanning stays optional.
- TalkBack names every switch, field and checkbox and reads errors aloud, and everything you can tap has a touch area of at least 48 by 48 dp.

### Security

- The wallet list is stored encrypted, under a key that Android's secure storage keeps apart from the vault.
- Gerfaut marks a descriptor or a policy you copy as sensitive on the clipboard: Android shows no preview of it and keeps it out of its history. Gerfaut clears it from the clipboard a minute later, unless you copied something else since.
- When one of your nodes is a `.onion` address, the price and the update check go through Tor, on any network, and Gerfaut sends neither when Tor is out of reach. The price widget never starts Tor for the price alone.
- While an app lock is set, the balance widget shows no wallet name and no amount, and "Show balances on widgets" stays greyed out.
- Under the calculator disguise, a vault that fails to open shows the calculator, not Gerfaut's error page.
- Gerfaut refuses a file far too large to be a wallet, a transaction or a backup, and an animated QR code that announces more than 5,000 parts.
- A transaction history shared as CSV does not stay in Gerfaut's cache: Gerfaut deletes the copy at the next share, or when it next starts.
- A release build writes no error text to the system log, where it could quote an address.
- Every release carries a `SHA256SUMS` manifest signed with minisign. CI builds the APKs unsigned, and the author signs them on his own machine, so the release key never reaches GitHub.
