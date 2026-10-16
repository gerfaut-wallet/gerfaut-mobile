//! JSON-string bridge over the gerfaut-core wallet manager.
//!
//! Every function takes and returns strings carrying JSON, keeping the
//! Dart side decoupled from the core types: success payloads mirror the
//! core structures serialized with serde, failures serialize to
//! `{"error": {"kind": "...", "message": "..."}}`, where a failure of
//! the core has the core's own code (`ErrorCode`) as its kind and the
//! few kinds this bridge adds are its own. A panic is not one of
//! those: flutter_rust_bridge catches it at the boundary and raises it on
//! the Dart side as an error of its own, outside this shape, so the Dart
//! code must be ready for a failure that carries no `kind`.

use crate::frb_generated::StreamSink;
use gerfaut_core::backup::{BackupOptions, ImportChoices};
use gerfaut_core::chain::BackendConfig;
use gerfaut_core::chain::tor::TorSettings;
use gerfaut_core::export::ExportOptions;
use gerfaut_core::input::{ImportOptions, ParsedInput, ScriptKind};
use gerfaut_core::live::LiveEvent;
use gerfaut_core::lock::LockKind;
use gerfaut_core::price::{FiatCurrency, PriceSource};
use gerfaut_core::store::VaultKey;
use gerfaut_core::wallet::meta::WalletIcon;
use gerfaut_core::wallet::snapshot::SyncReport;
use gerfaut_core::{CoreError, Network, WalletManager};
use rand::TryRngCore;
use serde_json::json;
use std::sync::LazyLock;
use tokio::sync::{Mutex, OnceCell, broadcast};

/// The process-wide manager, set once by [`init_manager`].
static MANAGER: OnceCell<WalletManager> = OnceCell::const_new();

/// The key a first launch seals the vault under, drawn once for the
/// whole process by [`fresh_vault_key`], as the manager is opened once.
static FRESH_KEY: OnceCell<String> = OnceCell::const_new();

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    match console_log_level(cfg!(debug_assertions)) {
        Some(level) => flutter_rust_bridge::setup_log_to_console(level),
        None => log::set_max_level(log::LevelFilter::Off),
    }
    // A panic still reaches Dart with its backtrace.
    flutter_rust_bridge::setup_backtrace();
}

/// How much of what the crates log reaches the console, which is logcat
/// on Android: everything in a debug build, nothing in a release one.
///
/// The Electrum client logs every request it sends and every answer it
/// reads at the trace level: the scripts of every wallet, their
/// histories, whole transactions. The WebSocket of a mempool instance
/// logs every message the same way. Logcat is read over adb and goes
/// into bug reports, past the app lock and the disguise, and the live
/// watch would feed it all day.
fn console_log_level(debug_build: bool) -> Option<log::LevelFilter> {
    debug_build.then_some(log::LevelFilter::Trace)
}

// --- helpers -----------------------------------------------------------

fn error_json(kind: &str, message: impl std::fmt::Display) -> String {
    json!({ "error": { "kind": kind, "message": message.to_string() } }).to_string()
}

/// Deserializes one JSON argument, naming what it should have been.
fn from_json<T: serde::de::DeserializeOwned>(raw: &str, what: &str) -> Result<T, String> {
    serde_json::from_str(raw)
        .map_err(|e| error_json("bad_json", format!("invalid {what} JSON: {e}")))
}

/// A failure of the core, under the core's own code: the Dart side
/// decides on it, the way the desktop app does on the same name.
fn core_error_json(error: &CoreError) -> String {
    error_json(error.code().as_str(), error)
}

fn ok_json() -> String {
    json!({ "ok": true }).to_string()
}

fn to_json<T: serde::Serialize>(value: &T) -> String {
    match serde_json::to_string(value) {
        Ok(s) => s,
        Err(e) => error_json("internal", format!("serialization failed: {e}")),
    }
}

/// The initialized manager, or the `{"error": ...}` payload to return.
fn manager() -> Result<&'static WalletManager, String> {
    MANAGER
        .get()
        .ok_or_else(|| error_json("not_initialized", "call init_manager first"))
}

fn parse_network(name: &str) -> Result<Network, String> {
    name.parse::<Network>().map_err(|e| core_error_json(&e))
}

fn parse_network_opt(name: Option<String>) -> Result<Option<Network>, String> {
    match name {
        Some(name) => parse_network(&name).map(Some),
        None => Ok(None),
    }
}

/// Decodes exactly 64 hex characters into 32 key bytes.
fn decode_key(key_hex: &str) -> Result<[u8; 32], String> {
    let bad = |detail: &str| error_json("bad_key", detail);
    if key_hex.len() != 64 || !key_hex.is_ascii() {
        return Err(bad("vault key must be 64 hex characters"));
    }
    let mut key = [0u8; 32];
    for (i, byte) in key.iter_mut().enumerate() {
        let pair = &key_hex[i * 2..i * 2 + 2];
        *byte = u8::from_str_radix(pair, 16).map_err(|_| bad("vault key must be hexadecimal"))?;
    }
    Ok(key)
}

macro_rules! try_json {
    ($expr:expr) => {
        match $expr {
            Ok(value) => value,
            Err(payload) => return payload,
        }
    };
}

// --- lifecycle ---------------------------------------------------------

/// Opens (or creates) the vault under `data_dir` with a 32-byte key given
/// as 64 hex characters. Idempotent: once initialized, later calls (hot
/// restarts) succeed without reopening.
///
/// The screens, the periodic task and the live watch each run in an
/// isolate of their own, in this one process, and each calls this when
/// it starts: two of them can call it at once. The vault takes one
/// opener at a time, within a process as between two, so a second open
/// would fail with `vault_in_use` instead of finding the first. One
/// call opens, and any other waits for it and shares its manager.
pub async fn init_manager(data_dir: String, key_hex: String) -> String {
    let key = try_json!(decode_key(&key_hex));
    let opened = MANAGER
        .get_or_try_init(|| async move { WalletManager::open(data_dir, VaultKey::Raw(key)) })
        .await;
    match opened {
        Ok(_) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// The key to store and open a new vault with, as 64 hex characters,
/// for a first launch: no vault yet, and no key kept for one.
///
/// The screens, the periodic task and the live watch each start in an
/// isolate of their own, and on a first launch each of them finds no
/// vault and no key. Were each to draw its own, the vault would be
/// sealed under the first key to reach [`init_manager`] while the
/// storage kept whichever was written last, and the next launch could
/// not open it. Drawn here, in one cell for the process, every caller
/// gets the same key: they all store that one and open with it.
pub async fn fresh_vault_key() -> String {
    let drawn = FRESH_KEY
        .get_or_try_init(|| async {
            let mut bytes = [0u8; 32];
            rand::rngs::OsRng
                .try_fill_bytes(&mut bytes)
                .map_err(|e| error_json("random", format!("no randomness to draw a key: {e}")))?;
            Ok::<String, String>(bytes.iter().map(|b| format!("{b:02x}")).collect())
        })
        .await;
    match drawn {
        Ok(key) => json!({ "key": key }).to_string(),
        Err(e) => e,
    }
}

// --- input classification ---------------------------------------------

/// Classifies pasted or scanned wallet material. Returns the serialized
/// `ParsedInput` to pass back to [`add_wallet`] after user confirmation.
/// `script` is the user's script type choice for a lone extended key
/// (`legacy`, `nested_segwit`, `segwit`, `taproot`), ignored otherwise.
pub async fn parse_input(input: String, script: Option<String>) -> String {
    let script: Option<ScriptKind> = match script {
        None => None,
        Some(id) => match serde_json::from_value(json!(id)) {
            Ok(kind) => Some(kind),
            Err(_) => return error_json("invalid_input", format!("unknown script type `{id}`")),
        },
    };
    match gerfaut_core::input::parse_input_with(&input, script) {
        Ok(parsed) => to_json(&parsed),
        Err(e) => core_error_json(&e),
    }
}

/// Classifies wallet material with the choices of the import screen:
/// `options_json` is a serialized `ImportOptions` (script type,
/// derivation paths, and the network the wallet goes to), all
/// optional. Everything the input fixes by itself ignores the first
/// two; the network decides the first address shown.
pub async fn parse_input_with_options(input: String, options_json: String) -> String {
    let options: ImportOptions = try_json!(from_json(&options_json, "ImportOptions"));
    match gerfaut_core::input::parse_input_with_options(&input, &options) {
        Ok(parsed) => to_json(&parsed),
        Err(e) => core_error_json(&e),
    }
}

/// Reads a server address scanned or pasted into the backend settings:
/// the Electrum one-liner `host:port:s|t` that node dashboards print,
/// an `ssl://`/`tcp://` address, or an `http(s)://` Esplora endpoint.
/// Returns the serialized `ScannedBackend`; the screen fills its fields
/// with it and the person still presses Save.
pub async fn parse_backend(input: String) -> String {
    match gerfaut_core::chain::connect::parse_backend(&input) {
        Ok(backend) => to_json(&backend),
        Err(e) => core_error_json(&e),
    }
}

/// Assembles the QR frames scanned so far (plain text, UR, BBQr) from a
/// JSON array of strings. Returns the serialized `QrProgress`: feed the
/// growing list until `complete` is true, then pass `text` to
/// [`parse_input`].
pub async fn assemble_qr(frames_json: String) -> String {
    let frames: Vec<String> = try_json!(
        serde_json::from_str(&frames_json)
            .map_err(|e| error_json("bad_json", format!("invalid frames JSON: {e}")))
    );
    match gerfaut_core::input::qr::assemble(&frames) {
        Ok(progress) => to_json(&progress),
        Err(e) => core_error_json(&e),
    }
}

// --- wallet lifecycle --------------------------------------------------

/// Adds a wallet from a `ParsedInput` JSON on an explicit network.
/// Returns the new wallet's metadata.
pub async fn add_wallet(name: String, parsed_json: String, network: String) -> String {
    let manager = try_json!(manager());
    let parsed: ParsedInput = try_json!(
        serde_json::from_str(&parsed_json)
            .map_err(|e| error_json("bad_json", format!("invalid ParsedInput JSON: {e}")))
    );
    let network = try_json!(parse_network(&network));
    match manager.add_wallet(&name, &parsed, network).await {
        Ok(meta) => to_json(&meta),
        Err(e) => core_error_json(&e),
    }
}

/// Lists wallet metadata, optionally restricted to one network.
pub async fn list_wallets(network: Option<String>) -> String {
    let manager = try_json!(manager());
    let network = try_json!(parse_network_opt(network));
    to_json(&manager.list_wallets(network).await)
}

/// Removes a wallet from this device.
pub async fn remove_wallet(id: String) -> String {
    let manager = try_json!(manager());
    match manager.remove_wallet(&id).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

pub async fn rename_wallet(id: String, name: String) -> String {
    let manager = try_json!(manager());
    match manager.rename_wallet(&id, &name).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Changes the glyph a wallet shows next to its name. `icon` is one of
/// the serde names: `wallet`, `key`, `shield`, `map_pin`, `snowflake`,
/// `landmark`, `piggy_bank`.
pub async fn set_wallet_icon(id: String, icon: String) -> String {
    let manager = try_json!(manager());
    let icon: WalletIcon = try_json!(parse_variant(&icon, "wallet icon"));
    match manager.set_wallet_icon(&id, icon).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Puts a wallet ahead of the others in the live watch, or back among
/// them. When the watch cannot follow every address, the pinned wallets
/// are followed first. Kept in the vault; the watch takes the new order
/// by itself.
pub async fn set_wallet_live_pinned(id: String, pinned: bool) -> String {
    let manager = try_json!(manager());
    match manager.set_wallet_live_pinned(&id, pinned).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Puts the listed wallets in that order. Wallets left out keep their
/// slots, so the list of one network reorders without moving another
/// network's wallets. A repeated id is refused, an unknown one too.
pub async fn reorder_wallets(ids: Vec<String>) -> String {
    let manager = try_json!(manager());
    match manager.reorder_wallets(&ids).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

// --- views -------------------------------------------------------------

pub async fn wallet_snapshot(id: String) -> String {
    let manager = try_json!(manager());
    match manager.wallet_snapshot(&id).await {
        Ok(snapshot) => to_json(&snapshot),
        Err(e) => core_error_json(&e),
    }
}

/// The wallet's descriptor read as a spending policy: its keys, its
/// branches, and every timelock evaluated against the chain tip and the
/// wallet's coins. Returns a serialized `PolicySnapshot`; a watched
/// address yields one with no keys and no branches.
pub async fn wallet_policy(id: String) -> String {
    let manager = try_json!(manager());
    match manager.policy(&id).await {
        Ok(policy) => to_json(&policy),
        Err(e) => core_error_json(&e),
    }
}

pub async fn tx_detail(id: String, txid: String) -> String {
    let manager = try_json!(manager());
    match manager.tx_detail(&id, &txid).await {
        Ok(detail) => to_json(&detail),
        Err(e) => core_error_json(&e),
    }
}

pub async fn utxos(id: String) -> String {
    let manager = try_json!(manager());
    match manager.utxos(&id).await {
        Ok(utxos) => to_json(&utxos),
        Err(e) => core_error_json(&e),
    }
}

/// The next unused receive address plus `lookahead` upcoming ones.
pub async fn receive_addresses(id: String, lookahead: u32) -> String {
    let manager = try_json!(manager());
    match manager.receive_addresses(&id, lookahead).await {
        Ok(entries) => to_json(&entries),
        Err(e) => core_error_json(&e),
    }
}

/// Revealed addresses of a wallet, by keychain, with usage and balance.
/// Capped by the core: an audit view, not an infinite scroll.
pub async fn address_list(id: String) -> String {
    let manager = try_json!(manager());
    match manager.address_list(&id).await {
        Ok(list) => to_json(&list),
        Err(e) => core_error_json(&e),
    }
}

/// Builds a CSV export of one wallet's transactions from serialized
/// `ExportOptions`. Returns `{"ok": ExportResult}`; nothing leaves the
/// device.
pub async fn export_transactions(id: String, options_json: String) -> String {
    let manager = try_json!(manager());
    let options: ExportOptions = try_json!(
        serde_json::from_str(&options_json)
            .map_err(|e| error_json("bad_json", format!("invalid ExportOptions JSON: {e}")))
    );
    match manager.export_transactions(&id, &options).await {
        Ok(result) => json!({ "ok": result }).to_string(),
        Err(e) => core_error_json(&e),
    }
}

// --- sync --------------------------------------------------------------

pub async fn sync_wallet(id: String) -> String {
    let manager = try_json!(manager());
    match manager.sync_wallet(&id).await {
        Ok(report) => to_json(&report),
        Err(e) => core_error_json(&e),
    }
}

/// Scans a wallet again from its first address with the current gap
/// limit, for funds an incremental sync can no longer see. Returns a
/// serialized `SyncReport`.
pub async fn rescan_wallet(id: String) -> String {
    let manager = try_json!(manager());
    match manager.rescan_wallet(&id).await {
        Ok(report) => to_json(&report),
        Err(e) => core_error_json(&e),
    }
}

/// Fetches an older round of history for a watched address. Returns how
/// many transactions were added; zero means the history is exhausted.
pub async fn load_more_history(id: String) -> String {
    let manager = try_json!(manager());
    match manager.load_more_history(&id).await {
        Ok(added) => to_json(&added),
        Err(e) => core_error_json(&e),
    }
}

pub async fn sync_all(network: Option<String>) -> String {
    let manager = try_json!(manager());
    let network = try_json!(parse_network_opt(network));
    to_json(&manager.sync_all(network).await)
}

// --- settings ----------------------------------------------------------

pub async fn get_settings() -> String {
    let manager = try_json!(manager());
    to_json(&manager.settings().await)
}

pub async fn set_active_network(network: String) -> String {
    let manager = try_json!(manager());
    let network = try_json!(parse_network(&network));
    match manager.set_active_network(network).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Sets the global gap limit applied to every descriptor wallet on the
/// next sync. Bounded to 1..=500 by the core.
pub async fn set_gap_limit(gap_limit: u32) -> String {
    let manager = try_json!(manager());
    match manager.set_gap_limit(gap_limit).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Sets the backend for a network from a serialized `BackendConfig`.
pub async fn set_backend(network: String, config_json: String) -> String {
    let manager = try_json!(manager());
    let network = try_json!(parse_network(&network));
    let config: BackendConfig = try_json!(
        serde_json::from_str(&config_json)
            .map_err(|e| error_json("bad_json", format!("invalid BackendConfig JSON: {e}")))
    );
    match manager.set_backend(network, config).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// The public servers offered for a network, in settings order.
/// Returns a serialized `Vec<PublicServer>`, empty on regtest, which
/// has no public server by definition.
pub async fn public_servers(network: String) -> String {
    let network = try_json!(parse_network(&network));
    to_json(&gerfaut_core::chain::public::public_servers(network))
}

// --- certificates ------------------------------------------------------

/// What an Electrum server's certificate amounts to right now, seen
/// through the handshake a sync would open. Returns a serialized
/// `CertificateReport`: the `host:port` an acceptance is recorded
/// against, plus the `status` the settings screen acts on.
pub async fn inspect_certificate(url: String) -> String {
    let manager = try_json!(manager());
    match manager.inspect_certificate(&url).await {
        Ok(report) => to_json(&report),
        Err(e) => core_error_json(&e),
    }
}

/// Remembers the certificate the user accepted for this server. That
/// host must present exactly this one from then on.
pub async fn trust_certificate(url: String, fingerprint: String) -> String {
    let manager = try_json!(manager());
    match manager.trust_certificate(&url, &fingerprint).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Drops an accepted certificate, keyed by `host:port`: the next
/// connection to that host asks again.
pub async fn forget_certificate(host: String) -> String {
    let manager = try_json!(manager());
    match manager.forget_certificate(&host).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Stores one small app preference in the encrypted vault.
pub async fn set_app_pref(key: String, value: String) -> String {
    let manager = try_json!(manager());
    match manager.set_app_pref(key, value).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

// --- broadcast ---------------------------------------------------------

/// Decodes a transaction somebody else signed (PSBT as base64, hex or a
/// binary file passed as hex; raw transaction as hex; a `ur:crypto-psbt`
/// or BBQr envelope) and previews what it does on `network`. Returns a
/// serialized `TxPreview`; nothing is signed, nothing is sent.
pub async fn preview_transaction(input: String, network: String) -> String {
    let manager = try_json!(manager());
    let network = try_json!(parse_network(&network));
    match manager.preview_transaction(&input, network).await {
        Ok(preview) => to_json(&preview),
        Err(e) => core_error_json(&e),
    }
}

/// Hands a fully signed transaction (hex) to the backend of `network`.
/// Returns a serialized `BroadcastReport`; a refusal comes back verbatim
/// as the error message.
pub async fn broadcast_transaction(network: String, hex: String) -> String {
    let manager = try_json!(manager());
    let network = try_json!(parse_network(&network));
    match manager.broadcast_transaction(network, &hex).await {
        Ok(report) => to_json(&report),
        Err(e) => core_error_json(&e),
    }
}

/// Where a broadcast transaction (hex) stands as the backend of
/// `network` sees it. Returns a serialized `BroadcastStatus`.
pub async fn transaction_status(network: String, hex: String) -> String {
    let manager = try_json!(manager());
    let network = try_json!(parse_network(&network));
    match manager.transaction_status(network, &hex).await {
        Ok(status) => to_json(&status),
        Err(e) => core_error_json(&e),
    }
}

// --- tor ---------------------------------------------------------------

/// Where Tor stands for `.onion` backends. Returns a serialized
/// `TorStatus`: the mode, the route in use, and how far the built-in
/// client has bootstrapped.
pub async fn tor_status() -> String {
    let manager = try_json!(manager());
    to_json(&manager.tor_status().await)
}

/// Sets how `.onion` backends reach Tor from serialized `TorSettings`
/// (`mode`: auto, system, embedded; `socks_proxy`: `host:port` or null).
pub async fn set_tor_settings(settings_json: String) -> String {
    let manager = try_json!(manager());
    let settings: TorSettings = try_json!(from_json(&settings_json, "TorSettings"));
    match manager.set_tor_settings(settings).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Resolves the route now, bootstrapping the built-in client if that is
/// the path. Up to a minute and a half on a first run. Returns a
/// serialized `TorRoute`.
pub async fn tor_connect() -> String {
    let manager = try_json!(manager());
    match manager.tor_connect().await {
        Ok(route) => to_json(&route),
        Err(e) => core_error_json(&e),
    }
}

// --- app lock ----------------------------------------------------------

/// The lock in place without its hash, serialized, or `null`.
pub async fn app_lock() -> String {
    let manager = try_json!(manager());
    to_json(&manager.app_lock().await)
}

/// Sets a lock (`kind` is `pin` or `password`), or replaces its secret;
/// replacing needs the current one.
pub async fn set_app_lock(kind: String, secret: String, current: Option<String>) -> String {
    let manager = try_json!(manager());
    let kind: LockKind = try_json!(parse_variant(&kind, "lock kind"));
    match manager
        .set_app_lock(kind, &secret, current.as_deref())
        .await
    {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

pub async fn clear_app_lock(current: String) -> String {
    let manager = try_json!(manager());
    match manager.clear_app_lock(&current).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Tries a secret. Returns a serialized `LockVerdict`, whose delay says
/// when the next attempt is looked at after repeated failures.
pub async fn verify_app_lock(secret: String) -> String {
    let manager = try_json!(manager());
    match manager.verify_app_lock(&secret).await {
        Ok(verdict) => to_json(&verdict),
        Err(e) => core_error_json(&e),
    }
}

/// Whether the phone's biometric prompt may stand in for the secret.
pub async fn set_biometric_unlock(enabled: bool, current: String) -> String {
    let manager = try_json!(manager());
    match manager.set_biometric_unlock(enabled, &current).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

// --- backup ------------------------------------------------------------

/// Seals the chosen wallets under a password from serialized
/// `BackupOptions`. Returns a serialized `BackupBundle`: base64 for a
/// file, UR frames for an animated QR.
pub async fn export_backup(options_json: String, password: String) -> String {
    let manager = try_json!(manager());
    let options: BackupOptions = try_json!(from_json(&options_json, "BackupOptions"));
    match manager.export_backup(&options, &password).await {
        Ok(bundle) => to_json(&bundle),
        Err(e) => core_error_json(&e),
    }
}

/// Opens a backup (base64 of the file, or the `gerfaut-backup:` text a
/// scan yields) and lists what it holds. Returns a `BackupPreview`.
pub async fn preview_backup(source: String, password: String) -> String {
    let manager = try_json!(manager());
    match manager.preview_backup(&source, &password).await {
        Ok(preview) => to_json(&preview),
        Err(e) => core_error_json(&e),
    }
}

/// Restores the chosen wallets from serialized `ImportChoices`. Returns
/// a serialized `ImportReport`.
pub async fn import_backup(source: String, password: String, choices_json: String) -> String {
    let manager = try_json!(manager());
    let choices: ImportChoices = try_json!(from_json(&choices_json, "ImportChoices"));
    match manager.import_backup(&source, &password, &choices).await {
        Ok(report) => to_json(&report),
        Err(e) => core_error_json(&e),
    }
}

// --- live watch --------------------------------------------------------

/// What the running watch says, as JSON, for the screens: its status,
/// the wallets it synced, blocks, and `{"type":"stopped"}` at its end.
/// Never a transaction to announce: those go to the one caller of
/// [`live_run`] alone, since the core hands each of them out once.
static LIVE_EVENTS: LazyLock<broadcast::Sender<String>> =
    LazyLock::new(|| broadcast::channel(256).0);

/// A [`live_run`] holds the watch. Behind an async lock so that a run
/// asked for while another is still ending waits for it to be gone.
static LIVE_RUNNING: Mutex<bool> = Mutex::const_new(false);

/// Starts the live watch of the active network and hands everything it
/// says to this one caller, each a serialized `LiveEvent`, then
/// `{"type":"stopped"}` once the watch has ended. The caller announces
/// every transaction it gets: the core hands each one out once, and has
/// already taken it off its record.
///
/// One caller at a time: with a watch already held, the stream carries
/// a `{"error":{"kind":"live_running"}}` payload and ends. A caller
/// that goes away without [`live_stop`] stops the watch at the next
/// event, so nothing more is taken for nobody; the event in hand then
/// is lost with it, which is why the host stops the watch first.
pub async fn live_run(sink: StreamSink<String>) {
    let manager = match manager() {
        Ok(manager) => manager,
        Err(payload) => {
            let _ = sink.add(payload);
            return;
        }
    };
    let mut events = {
        let mut running = LIVE_RUNNING.lock().await;
        if *running {
            let _ = sink.add(error_json("live_running", "the live watch is held already"));
            return;
        }
        match manager.live_start().await {
            Ok(events) => {
                *running = true;
                events
            }
            Err(e) => {
                let _ = sink.add(core_error_json(&e));
                return;
            }
        }
    };
    while let Some(event) = events.next().await {
        let payload = to_json(&event);
        if !matches!(event, LiveEvent::Transaction(_)) {
            // The screens may not be listening; nothing is lost then.
            let _ = LIVE_EVENTS.send(payload.clone());
        }
        if sink.add(payload).is_err() {
            manager.live_stop().await;
            break;
        }
    }
    *LIVE_RUNNING.lock().await = false;
    let stopped = json!({ "type": "stopped" }).to_string();
    let _ = LIVE_EVENTS.send(stopped.clone());
    let _ = sink.add(stopped);
}

/// Stops the live watch and closes its connection. Returns at once; the
/// stream of [`live_run`] ends right after what the watch still held.
/// Idempotent.
pub async fn live_stop() -> String {
    let manager = try_json!(manager());
    manager.live_stop().await;
    ok_json()
}

/// Checks the connection now: the call an alarm makes every few
/// minutes, and a change of network makes at once, because the timers
/// of a sleeping phone do not run. Cheap, and nothing with no watch.
pub async fn live_tick() -> String {
    let manager = try_json!(manager());
    manager.live_tick().await;
    ok_json()
}

/// Where the watch stands. Returns a serialized `WatchStatus`, whose
/// state is `off` when none runs.
pub async fn live_status() -> String {
    let manager = try_json!(manager());
    to_json(&manager.live_status().await)
}

/// Subscribes this isolate to what the running watch says for the
/// screens (its status, the wallets it synced, blocks), each a
/// serialized `LiveEvent`, plus
/// `{"type":"stopped"}` when the watch ends. Returns once the listener
/// is gone. A listener that lags loses the oldest events, never the
/// watch, and never a transaction to announce.
pub async fn live_events(sink: StreamSink<String>) {
    let mut events = LIVE_EVENTS.subscribe();
    loop {
        match events.recv().await {
            Ok(event) => {
                if sink.add(event).is_err() {
                    return;
                }
            }
            Err(broadcast::error::RecvError::Lagged(_)) => continue,
            Err(broadcast::error::RecvError::Closed) => return,
        }
    }
}

/// What the syncs of one wallet found that nobody has announced yet,
/// taken off the record in the vault: call it after every sync this
/// app runs of that wallet, whatever the report lists, and announce
/// everything it returns, or drop it on purpose (notices off, the app
/// disguised). Nothing it returns is ever returned again, to this
/// caller or to the live watch. Returns a serialized `Vec<LiveTx>`.
pub async fn claim_announcements(wallet_id: String) -> String {
    let manager = try_json!(manager());
    // The claim reads the wallet of the report and nothing else: what
    // the sync found is already in the vault.
    let report = SyncReport {
        wallet_id,
        new_tx_count: 0,
        new_txs: Vec::new(),
        confirmed_txs: Vec::new(),
        balance: Default::default(),
        tip_height: 0,
        took_ms: 0,
        backend: String::new(),
    };
    match manager.claim_announcements(&report).await {
        Ok(claimed) => to_json(&claimed),
        Err(e) => core_error_json(&e),
    }
}

/// Whether anything this app sends has to go through Tor.
pub async fn uses_tor() -> String {
    let manager = try_json!(manager());
    to_json(&manager.uses_tor().await)
}

// --- price and updates -------------------------------------------------

/// Parses one serde snake_case enum value from its string spelling.
fn parse_variant<T: serde::de::DeserializeOwned>(
    name: &str,
    kind: &'static str,
) -> Result<T, String> {
    serde_json::from_value(serde_json::Value::String(name.to_owned()))
        .map_err(|_| error_json("bad_json", format!("unknown {kind} `{name}`")))
}

/// Fetches the current BTC price. `source` is one of `coingecko`,
/// `kraken`, `mempool_space`; `currency` is one of the `FiatCurrency`
/// identifiers. The source must quote the currency: only CoinGecko
/// serves the ones past the first seven. Returns a `PriceQuote`.
///
/// Through the manager, so the request takes the route the syncs take:
/// with a .onion node on any network it goes through Tor, and with Tor
/// out of reach it does not go at all and comes back as `tor`.
pub async fn fetch_price(source: String, currency: String) -> String {
    let source: PriceSource = try_json!(parse_variant(&source, "price source"));
    let currency: FiatCurrency = try_json!(parse_variant(&currency, "currency"));
    let manager = try_json!(manager());
    match manager.fetch_price(source, currency).await {
        Ok(quote) => to_json(&quote),
        Err(e) => core_error_json(&e),
    }
}

/// GitHub repository whose releases this build follows.
const UPDATE_REPO: &str = "gerfaut-wallet/gerfaut-mobile";

/// Checks the latest published release against the running version.
/// Returns a serialized `UpdateCheck`.
///
/// Through the manager, so the request takes the route the syncs take:
/// with an onion backend it goes through Tor, and with Tor out of reach
/// it does not go at all and comes back as `tor`.
pub async fn check_update(current_version: String) -> String {
    let manager = try_json!(manager());
    match manager.check_update(UPDATE_REPO, &current_version).await {
        Ok(check) => to_json(&check),
        Err(e) => core_error_json(&e),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn payload(error: &CoreError) -> Value {
        serde_json::from_str(&core_error_json(error)).expect("the payload is JSON")
    }

    /// A frame of a multi-part UR announcing `total` parts.
    fn frame_of(total: u64) -> String {
        format!(
            "ur:bytes/{}-{total}/lpadascfadaxcywenbpljkhdcahkadaemej",
            total + 1
        )
    }

    fn kind_of(payload: &str) -> Value {
        serde_json::from_str::<Value>(payload).expect("JSON")["error"]["kind"].clone()
    }

    /// One frame announcing four billion parts would make the decoder
    /// ask for tens of gigabytes, and the app would die on the spot.
    /// The core turns away any count past the 5,000 parts it reads,
    /// before it decodes a thing, and the refusal reaches the screens
    /// under a kind of its own, wherever the frame was handed over.
    #[tokio::test]
    async fn a_frame_announcing_too_many_parts_reaches_the_screens_by_name() {
        for total in [5_001, 10_001, 4_294_967_294] {
            let hostile = frame_of(total);
            let alone = serde_json::to_string(&[&hostile]).unwrap();
            assert_eq!(kind_of(&assemble_qr(alone).await), "too_many_parts");
            assert_eq!(
                kind_of(&parse_input(hostile.clone(), None).await),
                "too_many_parts"
            );
            assert_eq!(
                kind_of(&parse_input_with_options(hostile.to_uppercase(), "{}".into()).await),
                "too_many_parts"
            );
        }
        // Among the frames of an honest scan it is passed over, and the
        // scan goes on.
        let frames = serde_json::to_string(&[
            "ur:bytes/1-2/lpadaocfadaxcywenbpljkhdcahkadaemej".to_owned(),
            frame_of(4_294_967_294),
        ])
        .unwrap();
        let progress: Value = serde_json::from_str(&assemble_qr(frames).await).unwrap();
        assert!(progress.get("error").is_none(), "{progress}");
        assert_eq!(progress["total"], 2);
    }

    /// A release build writes nothing to logcat: what the Electrum
    /// client traces is every script and transaction of every wallet.
    /// A debug build keeps the traces a developer reads.
    #[test]
    fn a_release_build_logs_nothing() {
        assert_eq!(console_log_level(false), None);
        assert_eq!(console_log_level(true), Some(log::LevelFilter::Trace));
    }

    /// The kind a screen reads is the core's code, unchanged, with the
    /// core's words beside it. A vault another open holds is its own
    /// kind, a healthy vault no screen may take for one that cannot be
    /// opened; a wrong password, a file that is not a backup and one a
    /// newer Gerfaut wrote are three, so the restore screen says "wrong
    /// password" for the first and for nothing else.
    #[test]
    fn the_core_code_goes_through_as_the_kind() {
        use gerfaut_core::error::VaultError;

        let relayed = |error: CoreError| {
            let sent = payload(&error);
            assert_eq!(sent["error"]["kind"], error.code().as_str());
            assert_eq!(sent["error"]["message"], error.to_string());
            sent["error"]["kind"].as_str().unwrap().to_owned()
        };
        assert_eq!(
            relayed(CoreError::Vault(VaultError::AlreadyOpen)),
            "vault_in_use"
        );
        assert_eq!(
            relayed(CoreError::Vault(VaultError::Kdf("no memory".into()))),
            "vault"
        );
        assert_eq!(
            relayed(CoreError::Vault(VaultError::WrongKeyOrCorrupted)),
            "wrong_key"
        );
        assert_eq!(
            relayed(CoreError::UnreadableBackup(
                "this is not a Gerfaut backup".into()
            )),
            "unreadable_backup"
        );
        assert_eq!(
            relayed(CoreError::NewerBackup(
                "this backup was written by a newer Gerfaut (backup version 2)".into()
            )),
            "newer_format"
        );
        assert_eq!(relayed(CoreError::TooManyParts(6_000)), "too_many_parts");
    }

    /// The isolates of the app call `init_manager` together at a cold
    /// start: every one of them gets the manager, none `vault_in_use`,
    /// and the vault is opened once, so a second opener is still kept
    /// out.
    #[test]
    fn isolates_opening_the_vault_together_share_one_manager() {
        let dir = std::env::temp_dir().join(format!(
            "gerfaut-mobile-init-{}-{}",
            std::process::id(),
            SystemTime::now()
                .duration_since(UNIX_EPOCH)
                .unwrap()
                .as_nanos()
        ));
        std::fs::create_dir_all(&dir).unwrap();
        let key_hex = "07".repeat(32);
        let start = std::sync::Arc::new(std::sync::Barrier::new(8));
        let callers: Vec<_> = (0..8)
            .map(|_| {
                let (dir, key_hex, start) = (dir.clone(), key_hex.clone(), start.clone());
                std::thread::spawn(move || {
                    let runtime = tokio::runtime::Builder::new_current_thread()
                        .build()
                        .unwrap();
                    start.wait();
                    runtime.block_on(init_manager(dir.to_string_lossy().into_owned(), key_hex))
                })
            })
            .collect();
        for caller in callers {
            let answer: Value = serde_json::from_str(&caller.join().unwrap()).unwrap();
            assert_eq!(answer, json!({ "ok": true }), "{answer}");
        }
        let second = WalletManager::open(&dir, VaultKey::Raw([7u8; 32]))
            .err()
            .expect("the vault is held");
        assert_eq!(payload(&second)["error"]["kind"], "vault_in_use");
        // The manager stays open for the process, so a system that keeps
        // open files in place may refuse: the folder is left then.
        let _ = std::fs::remove_dir_all(&dir);
    }

    /// Isolates that find no vault together on a first launch are all
    /// handed the one key, and it is a key: 64 hex characters.
    #[test]
    fn isolates_drawing_a_key_together_get_the_same_one() {
        let start = std::sync::Arc::new(std::sync::Barrier::new(8));
        let callers: Vec<_> = (0..8)
            .map(|_| {
                let start = start.clone();
                std::thread::spawn(move || {
                    let runtime = tokio::runtime::Builder::new_current_thread()
                        .build()
                        .unwrap();
                    start.wait();
                    runtime.block_on(fresh_vault_key())
                })
            })
            .collect();
        let keys: Vec<String> = callers
            .into_iter()
            .map(|caller| {
                let answer: Value = serde_json::from_str(&caller.join().unwrap()).unwrap();
                answer["key"].as_str().expect("a key").to_owned()
            })
            .collect();
        assert!(decode_key(&keys[0]).is_ok(), "{}", keys[0]);
        assert!(keys.iter().all(|key| key == &keys[0]), "{keys:?}");
    }
}
