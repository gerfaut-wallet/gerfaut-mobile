# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Gerfaut now runs on iPhone. Live watch, the calculator disguise, home-screen widgets and Broadcast stay on Android. On iOS, background checks run when the system allows it, never more often than the cadence you choose, and stop once you swipe Gerfaut away. The app doesn't ask GitHub for new versions there either: TestFlight and the App Store deliver them.

### Changed

- On a wide window, like a tablet or the inner display of a foldable, each screen keeps its content 640 points wide and centred. Rows and buttons no longer run from one edge to the other. Phones held upright lay out as before.
- When you move through the app with a keyboard, buttons, choice lists, menus, switches and the address chip show a 2 px focus ring. Tooltips now use the app's own colours.
- On the last step of Add a wallet, Back and Add wallet stay at the bottom of the screen, above the keyboard.
- Hints that repeated a title or the line next to them are gone, so the screens carry less text.
- On a wallet's page, the Transactions and UTXOs lists sit on a surface of their own. Address and direction chips stand out from the page behind them.
- In the Wallets settings, each wallet is a row under a hairline, where it used to be a card inside the card. Its 4 actions sit in a grid of 2 columns.
- A button with a label that cannot be pressed yet is drawn hollow, with a thin edge and its label in grey. Faded to half strength, its label was too pale to read.
- In the Transactions list, a transaction under 6 confirmations shows a small green pie, one sixth filled for each confirmation. From 6 on it shows a grey check, and a pending transaction keeps its amber clock. A screen reader says "3 of 6 confirmations".
- In the UTXOs list, the same mark beside the amount replaces the green "Confirmed" pill of each row. A coin now counts its own confirmations: the clock while it waits, the pie under 6, then the grey check.
- On a transaction's page, the pill shows the pie next to its count under 6 confirmations.
- A closed list shows the chosen value alone. The line that says what the choice does stays in the open list, where it reads whole.
- In the Wallets settings, the gap limit is set as a figure against the right edge, and its explanation takes the whole width of the card under it.
- Icons that were 13, 15 or 18 px are now 12, 14, 16 or 20 px. Between the elements of a row, a card or a list, gaps of 6 or 10 px are now 4 or 8 px.
- In a list opened from the bottom of the screen, the choices line up with the title of the list.

### Fixed

- The Network, Wallets and Security settings show "Loading…" until the settings are read, and "Try again" if the read fails. On a locked phone, the app lock switch no longer reads off for a moment.
- The Policy page and the CSV export say when their data could not be loaded, and offer "Try again".
- The Broadcast page no longer shows raw app errors, and its "Ready to broadcast" pill goes away once the transaction is sent.
- On the Broadcast screen, a status check that fails after an earlier answer now says "Could not check", with the error and the time and content of the last answer. It used to keep the previous status, such as "Waiting to be mined", and show the error nowhere.
- When the vault fails to save a setting, the setting goes back to the value the vault still holds instead of showing a choice the background checks and Live never see. This covers new-transaction notifications, background checks, Live, notification details, widget balances, the unit, the fiat display and the theme. Hidden amounts stay hidden. Live and the background check also wait until the vault has saved the setting before they start.
- A wallet whose last sync failed still says so after Gerfaut restarts, instead of "Synced" with an old time. A sync that Live starts on its own shows "Syncing…" while it runs.
- Leaving the app for a moment while the QR scanner starts, for a permission prompt or the notification shade, no longer leaves it on "Starting the camera…" once you come back.
- An address cut to fit its chip shows its last character whole. The chip used to fade it, most often on a narrow phone.
- On a narrow phone, the amount of a transaction's input or output goes under its address, so the address keeps both of its ends. The Broadcast preview does the same.
- On a narrow phone, a transaction row shows the time under the date. It used to cut the time off. A pending transaction's ID is cut in the middle and keeps both of its ends.
- In the transaction diagram, an amount is drawn at its full size, under the icon. A label too long for its box shrinks, where it used to lose its last character to a fade.
- On a narrow phone, the labels of the transaction diagram have more room in their boxes and shrink less.
- On the Policy page, the wallet's name reads as you wrote it. It used to be set in capitals.
- A transaction with an input whose final signature field is present but empty reads as not yet signed. It used to read as ready to broadcast, and no node would take it.
- A mining reward paid to a watched address counts as immature until its 100th confirmation, as it already did in a descriptor wallet.

### Security

- Another app can no longer hand Gerfaut arguments when it opens it. A release build drops the extras of the intent that starts it, and its main screen is reached only through the launcher icons.
- A transfer from one phone to another no longer copies Gerfaut's data. Android 12 and later make that copy even with backups turned off, so every data domain is now excluded from it, the vault included.
- An Esplora server on plain `http://`, other than a `.onion` one, now carries the same "in the clear" warning as an Electrum server without TLS: what Gerfaut asks it and what it answers travel unencrypted.
- A release build no longer writes debug messages to the system log.
- The release build checks the hash of what it downloads: every Gradle module, the NDK, CMake, the Rust toolchain and the parts of the Flutter cache that end up in the APK. Dart packages come only at the versions and hashes of the lockfiles.
- Gerfaut no longer takes the height of a block on a server's word. The work of a block proves it was mined, not where it sits, so a server could serve real blocks at heights of its own and make a payment look deeper than it is. On mainnet, the height of every server tip, and of the block of every confirmation that no checkpoint vouches for, is now proven by the block's own coinbase.
- A wallet that a server fooled with heights too high is repaired by the next server whose latest block is recent. A server that is far behind, with an old latest block, is refused and changes nothing in the wallet.
- An Electrum certificate that has expired, is not valid yet or was issued for another host is refused with that reason. It used to read as a certificate nobody vouches for.
- The build compiles only a revision of gerfaut-core that its main branch has reached. GitHub serves any commit of a fork by its hash, so a pinned hash alone could point at code that was never merged.

## [0.1.0] - 2026-10-21

The first release: Gerfaut for Android, as a public beta.

Gerfaut watches bitcoin wallets it cannot spend from. There is no key generation, no seed handling and no signing anywhere in the code, and no Send button in the interface.

### Added

#### Watching a wallet

- Watch a wallet from what you already have: a descriptor, an extended or single public key, a plain address, a multisig setup, a BSMS record or another wallet's export file. Paste it, pick a file, or scan its QR code, static or animated. A long animated code reads as fast at its last frame as at its first.
- Gerfaut works out the format on its own and shows what it understood, with the first address, before it stores anything. A private key is refused, with a sentence that says what to bring instead.
- Watch several wallets on mainnet, signet, testnet4 or regtest. Hold a wallet card and drag it into the order you want, on the home screen and in the settings.
- For each wallet: the balance, the transaction history and the UTXOs, with one action to hide every amount on screen.
- Receive addresses with their QR code. Receive offers only addresses nobody has paid yet, a fresh one after every sync, up to 200 past the next unused one, and the gap limit warning counts the unused addresses in a row.
- A Policy page for every wallet: what the descriptor allows, branch by branch, primary paths first, with each timelock counted down in blocks and in days. A branch open now shows in green, and one that opens within 30 days in amber. Its Descriptor section shows and copies the whole wallet as one multipath descriptor, with `/<0;1>/*`.
- Export the history of a wallet as CSV, filtered by date and direction, to a file or through the share sheet.
- Home screen widgets for the price, the balance (hidden by default) and the block height.

#### Broadcasting a signed transaction

- Broadcast a signed transaction or a PSBT, read back in plain language before it goes anywhere. When no backend could confirm a coin it spends and only the PSBT declares its amount, Gerfaut marks the amounts and the fee "as the PSBT claims" and says what to check before sending.
- A signature that leaves the outputs open (SIGHASH_NONE or SIGHASH_SINGLE) gets a red warning: whoever relays such a transaction can send that money elsewhere. A transaction the network is sure to refuse, such as one that spends a coin already spent in a block, reads "Will be refused" and cannot be sent.
- On a PSBT still missing signatures, the fee rate reads "≈ … once signed", the rate it pays once your signing device has signed it. A transaction already waiting in the mempool reads "Already in the mempool" and can go out again, which does no harm.

#### Talking to the chain

- Public servers by default, or your own node over Electrum or Esplora. A self-signed certificate is shown and trusted once, then refused if it ever changes.
- A Tor client built in, so a `.onion` backend works with no Orbot installed. While "Test the connection" starts it, the Tor card shows its progress. When a `.onion` server stays silent for 30 seconds, the built-in Tor opens a second route to it alongside the first one, and Gerfaut uses whichever answers.
- A sync downloads only what a wallet lacks, so a payment that Live notices costs a few kilobytes. Gerfaut reads a wallet in full when the vault opens and once a day. Past the last used address, a sync asks the server about as many unused addresses as the gap limit, and no more.
- A "This is my node" switch under the address of your own server, in Settings › Network. Turned on, it lets Live follow up to 20,000 addresses, against 2,000 otherwise. Leave it off for a server you do not run: it would refuse most of them and learn every one.
- With Live on and the Automatic backend, syncs, transaction previews and broadcasts go first to the operator Live talks to, Blockstream on mainnet, so a single operator sees your addresses. When Gerfaut opens, the first sync waits up to 20 seconds for Live to connect.
- A preview or a broadcast moves to another server only when one cannot be reached. When a node refuses a transaction, Gerfaut asks no other and shows the node's own words.
- A server that is down while another one answers goes to the end of the list for 5 minutes, then twice as long each time it fails again, up to an hour. When the server Live talks to sees no new block for 2 hours, Gerfaut compares it with another server of the same operator, and Live moves there if it lags 2 blocks or more.

#### Getting told when something moves

- "Check for transactions", in Settings › Notifications, syncs your wallets while Gerfaut is closed, every 15 minutes, every hour or every 6 hours, and posts a local notification when a sync finds something new.
- Live, another choice under "Check for transactions", keeps a connection open to the backend your syncs already use. It tells you when a transaction reaches the mempool, then again at its first confirmation: within seconds from an Electrum server, later from an Esplora server, which Live polls, going through every address in turn.
- Live runs with the app closed and comes back after the phone restarts, behind the small permanent notification Android requires, which has a "Stop" button. A check every 15 minutes stays scheduled for whenever Android stops Live.
- Before Live starts, a sheet explains what it does and what the server learns, then asks for the battery exemption, which you can refuse. On a Xiaomi, Redmi, POCO, Huawei, Honor, Samsung, OnePlus, Oppo or realme phone, it also lists the switches to turn on in the maker's battery manager. A button opens Gerfaut's app info page.
- Each transaction is announced once when it appears and once when it confirms, whichever part of the app saw it first, in the same words as on the desktop. A fee bump brings no second notice. An incoming payment that leaves the mempool with nothing in its place gets one more notice saying it is no longer coming. Past 3 transactions in one wallet at once, one line counts the rest, and notices stop at 20 a minute. If Gerfaut cannot word a notice, it still posts one, with no wallet and no amount, that says more is waiting in the app.
- "Show wallet and amount", a switch in Settings › Notifications, decides whether a notification names the wallet and gives the amount. It is on by default and applies whether the app is locked or not. Turned off, a notification only says what happened, as in "New transaction · pending", and hidden balances keep the amount out either way.
- When Android stops letting Gerfaut's notifications through, Settings › Notifications says so in amber, with a button to the system settings. Live waits meanwhile and starts again once they get through.
- When Live cannot follow every address, Settings › Notifications says how many addresses of how many wallets wait for the next sync, and how to lift the limit. Each wallet shows "Live", "Partly live" or "At next sync" on its card, on its page and in Settings › Wallets, and "Always watch live first", under Settings › Wallets › Advanced, picks the wallets Live follows first.
- When a server takes only part of your addresses, Live asks it again for all of them a day later, or an hour later when it took none. On your own node, when the server itself refuses addresses, the note names the server setting that lets it follow more.

#### Keeping it yours

- An encrypted backup file, and the same backup as an animated QR code, so another device gets your wallets with no server in between. The export page asks for a passphrase of several words, since a copied file can be guessed offline, and can add your node settings. The restore page lists what the file will put in place, wallet by wallet and node setting by node setting, before it writes anything, and never replaces a certificate you already accepted. A wallet whose keys belong to another network says which one. A wrong password, a file that is not a Gerfaut backup and a backup made by a newer Gerfaut each get their own sentence, so Gerfaut never blames a password that was right. A wallet Gerfaut cannot watch stays on the restore list, unticked, with the reason, and the confirmation names it once the others are restored.
- The vault stays out of Android's own backups and device-to-device transfers: it leaves the phone only as a Gerfaut backup, sealed under your password.
- A vault this phone cannot open, such as one restored without its key, is never overwritten. Gerfaut sets it aside under another name and offers to start over, with the restore page first.
- Fiat value beside the balances and the transaction amounts, in the currency you pick, from mempool.space, the default, or CoinGecko. With CoinGecko, "Powered by CoinGecko" shows once on each screen that uses its prices, and on the price widget. No price source hears from Gerfaut until you turn "Fiat value" on or place the price widget. A wallet on signet, testnet4 or regtest shows 0 in your currency, since test coins are worth nothing.
- Amounts in BTC or in sats, and a light, dark or system theme.
- A PIN or password lock with biometrics. Attempts slow down after 3 tries and stay slowed after a restart, and coming back from a file picker, a save dialog or a share sheet more than 10 minutes after it opened asks for the lock again.
- Only a biometric that Android rates as strong opens the lock. On a phone whose face or fingerprint unlock is rated weak, the switch stays greyed out and says why. When the fingerprints or faces on the phone change, biometrics stop opening Gerfaut until you turn them on again.
- A calculator disguise for the icon. While Gerfaut is disguised, it posts no notification, Live stays off and no update check goes out. From Android 13, the recent apps keep no picture of Gerfaut while it is disguised. The sheet that turns the disguise on also says what Android keeps: an older thumbnail below Android 13, and Gerfaut's earlier notifications in the notification history, if you turned it on.
- A notice on the home screen when a newer release is out, with a button to the release page and a "Later" button that closes it for that release. Gerfaut asks GitHub at most once a day, when you open it, the first time a day after you first opened it, and never announces a pre-release. Settings › About turns the automatic check off.
- Settings › About marks a 0.x version as a beta, with a "Report a problem" button that opens the issues of this repository. The first page of the welcome tour says that Gerfaut is in public beta.
- One APK per processor architecture, so a phone downloads only the code it runs. Gerfaut installs on a phone without a camera, and scanning stays optional.
- TalkBack names every switch, field and checkbox and reads errors aloud, and everything you can tap has a touch area of at least 48 by 48 dp.

### Security

- The wallet list is stored encrypted, under a key that Android's secure storage keeps apart from the vault.
- Gerfaut marks a descriptor or a policy you copy as sensitive on the clipboard: Android shows no preview of it and keeps it out of its history. Gerfaut clears it from the clipboard a minute later, unless you copied something else since. If Android closes Gerfaut within that minute, Gerfaut clears it the next time it opens.
- A server cannot make up a confirmation. Gerfaut checks that the transaction is in the block the server names and, on mainnet, that the block carries the work the network asked for. Over Electrum, a confirmation in an older block must also link to the checkpoints built into Gerfaut. When no other server answers in place of one whose proof does not hold, the sync says that a server sent a false proof, whether you started it, it covered every wallet or Live started it. Over Esplora, a confirmation from before March 2014 must also link to the checkpoints, and every block height a server gives must carry the work of its block. A server cannot take a confirmation away either: to replace a block that holds one, it must send the headers of its new chain, each linked to the one before and, on mainnet, carrying the work of its height.
- When one of your nodes is a `.onion` address, the price and the update check go through Tor, on any network, and Gerfaut sends neither when Tor is out of reach. Neither the price widget nor the automatic update check starts Tor for itself. When the check finds no Tor running, the day does not count, and it asks again the next time Gerfaut comes back on screen.
- The built-in Tor client is arti 2.7.0, with its security fixes. A relay can no longer fill memory through half-closed streams, and a directory mirror can no longer do it through the consensus it sends, or stall Tor by holding back its answer.
- While an app lock is set, the balance widget shows no wallet name and no amount, and "Show balances on widgets" stays greyed out.
- Under the calculator disguise, a vault that fails to open shows the calculator, not Gerfaut's error page.
- Gerfaut refuses a file far too large to be a wallet, a transaction or a backup, and an animated QR code that announces more than 5,000 parts.
- A history or a backup you share reaches only the app you pick in the share sheet. Gerfaut deletes its copy from the cache an hour later, or when it next starts.
- From Android 12, Android hides the windows other apps draw over Gerfaut, so none can cover what a button does.
- A release build writes no error text to the system log, where it could quote an address.
- Every release carries a `SHA256SUMS` manifest signed with minisign. CI builds the APKs unsigned, and the author signs them on his own machine, so the release key never reaches GitHub.
