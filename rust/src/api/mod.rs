//! JSON-string bridge over the gerfaut-core wallet manager.
//!
//! Every function takes and returns strings carrying JSON, keeping the
//! Dart side decoupled from the core types: success payloads mirror the
//! core structures serialized with serde, failures serialize to
//! `{"error": {"kind": "...", "message": "..."}}`. A panic is not one of
//! those: flutter_rust_bridge catches it at the boundary and raises it on
//! the Dart side as an error of its own, outside this shape, so the Dart
//! code must be ready for a failure that carries no `kind`.

use gerfaut_core::backup::{BackupOptions, ImportChoices};
use gerfaut_core::chain::BackendConfig;
use gerfaut_core::chain::tor::TorSettings;
use gerfaut_core::error::PremiumError;
use gerfaut_core::export::ExportOptions;
use gerfaut_core::input::{ImportOptions, ParsedInput, ScriptKind};
use gerfaut_core::lock::LockKind;
use gerfaut_core::premium::client::{
    DEFAULT_BASE_URL, NTFY_BASE_URL, TELEGRAM_BOT, new_ntfy_topic, ntfy_subscribe_url,
    telegram_link_url,
};
use gerfaut_core::premium::licence::{self, LICENCE_PUBLIC_KEY_HEX};
use gerfaut_core::premium::{Channel, ChannelKind, Event, PremiumClient, PremiumState};
use gerfaut_core::price::{FiatCurrency, PriceSource};
use gerfaut_core::store::VaultKey;
use gerfaut_core::wallet::meta::{WalletIcon, WalletKind};
use gerfaut_core::{CoreError, Network, WalletManager};
use crate::frb_generated::StreamSink;
use gerfaut_core::wallet::snapshot::{NewTx, SyncReport};
use serde_json::json;
use std::sync::LazyLock;
use std::time::{SystemTime, UNIX_EPOCH};
use tokio::sync::{Mutex, OnceCell, broadcast};
use tokio::task::JoinHandle;

/// The process-wide manager, set once by [`init_manager`].
static MANAGER: OnceCell<WalletManager> = OnceCell::const_new();

#[flutter_rust_bridge::frb(init)]
pub fn init_app() {
    flutter_rust_bridge::setup_default_user_utils();
}

// --- helpers -----------------------------------------------------------

fn error_json(kind: &str, message: impl std::fmt::Display) -> String {
    json!({ "error": { "kind": kind, "message": message.to_string() } }).to_string()
}

fn core_error_kind(error: &CoreError) -> &'static str {
    match error {
        CoreError::UnrecognizedInput(_) => "unrecognized_input",
        CoreError::PrivateMaterialRejected => "private_material",
        CoreError::InvalidInput { .. } => "invalid_input",
        CoreError::NetworkMismatch { .. } => "network_mismatch",
        CoreError::WalletNotFound(_) => "wallet_not_found",
        CoreError::DuplicateWallet(_) => "duplicate_wallet",
        CoreError::Vault(_) => "vault",
        CoreError::Sync { .. } => "sync",
        CoreError::BackendUnavailable(_) => "backend_unavailable",
        CoreError::Broadcast { .. } => "broadcast",
        CoreError::Descriptor(_) => "descriptor",
        CoreError::Tor(_) => "tor",
        CoreError::Premium(error) => premium_error_kind(error),
        CoreError::Internal(_) => "internal",
    }
}

/// One kind per thing the screen does about it: an unknown key sends
/// the user back to the field, a key with no paid time to the renewal
/// page, an unreachable server to the "watch is offline" banner.
///
/// Seven, the same the desktop app answers with. A kind the screens
/// act on the same way is a kind they can only print, and what they
/// would print is a parser's complaint: an answer that does not decode
/// is a captive portal's login page where JSON was promised, which is
/// the server out of reach and nothing else. A certificate and a
/// heartbeat that do not check out are one case too — whichever of the
/// two it was, this device cannot trust what it was handed. An id the
/// server has nothing under is a refusal like any other: the screens
/// show it in the server's words, and read what it holds again.
///
/// The match is exhaustive on purpose: a variant added to the core
/// stops the build here until somebody says which of them it is.
fn premium_error_kind(error: &PremiumError) -> &'static str {
    match error {
        PremiumError::NoKey => "premium_no_key",
        PremiumError::UnknownKey => "premium_unknown_key",
        PremiumError::NoPaidTime => "premium_no_paid_time",
        PremiumError::Rejected(_) | PremiumError::NotFound => "premium_rejected",
        PremiumError::RateLimited { .. } => "premium_rate_limited",
        PremiumError::Unreachable(_) | PremiumError::UnexpectedResponse(_) => "premium_unreachable",
        PremiumError::InvalidCertificate(_)
        | PremiumError::InvalidHeartbeat(_)
        | PremiumError::StaleHeartbeat { .. } => "premium_invalid",
    }
}

/// Deserializes one JSON argument, naming what it should have been.
fn from_json<T: serde::de::DeserializeOwned>(raw: &str, what: &str) -> Result<T, String> {
    serde_json::from_str(raw)
        .map_err(|e| error_json("bad_json", format!("invalid {what} JSON: {e}")))
}

fn core_error_json(error: &CoreError) -> String {
    // A refusal reaches the screen in the server's own sentence: the
    // prefix the error type wraps it in names the layer, not the thing
    // that went wrong, and a card that prints it reads as plumbing.
    // Everything else keeps its wrapper, the unreachable one included:
    // the status it carries is what tells an outage from a server that
    // answered to say it could not do the thing.
    if let CoreError::Premium(PremiumError::Rejected(words)) = error {
        return error_json("premium_rejected", words);
    }
    // A request to slow down carries the wait, in seconds, for the
    // screen to count from; `null` when the server named none.
    if let CoreError::Premium(PremiumError::RateLimited { retry_after }) = error {
        return json!({ "error": {
            "kind": "premium_rate_limited",
            "message": error.to_string(),
            "retry_after": retry_after,
        } })
        .to_string();
    }
    error_json(core_error_kind(error), error)
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
pub async fn init_manager(data_dir: String, key_hex: String) -> String {
    let key = try_json!(decode_key(&key_hex));
    if MANAGER.initialized() {
        return ok_json();
    }
    match WalletManager::open(data_dir, VaultKey::Raw(key)) {
        Ok(manager) => {
            // A concurrent call may have won the race; both used the same
            // key and directory, so either instance is fine.
            let _ = MANAGER.set(manager);
            ok_json()
        }
        Err(e) => core_error_json(&e),
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

/// Classifies wallet material with the advanced choices of the import
/// screen: `options_json` is a serialized `ImportOptions` (script type
/// and derivation paths), both parts optional. Everything the input
/// fixes by itself ignores them.
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

/// Removes a wallet from this device. One the server watched is taken
/// off it too, after the answer: the core queues the message in the
/// same write as the removal, and a server out of reach hears it at
/// the next heartbeat instead.
pub async fn remove_wallet(id: String) -> String {
    let manager = try_json!(manager());
    match manager.remove_wallet(&id).await {
        Ok(()) => {
            // Not awaited, and its result not read: the wallet is gone
            // here whatever the server says, and what could not be told
            // stays queued in the vault until it can be.
            flutter_rust_bridge::spawn(async move {
                let _ = manager.premium_flush_unwatch(PREMIUM_BASE_URL).await;
            });
            ok_json()
        }
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

// --- premium -----------------------------------------------------------

/// The server every premium call goes to.
///
/// Clearnet, which does not settle how the call travels: the manager
/// sends it through Tor when the base URL is an onion and also when the
/// backend of the active network is one, since a person who reaches
/// their own node through Tor did not choose to show their address to
/// this server instead. A Tor that cannot be reached then is a call
/// that does not happen, reported as `tor`; nothing falls back to the
/// clear.
const PREMIUM_BASE_URL: &str = DEFAULT_BASE_URL;

/// Most events the alerts card shows.
const RECENT_EVENTS: usize = 20;

/// The server caps a page of events at this many.
const EVENTS_PAGE: u32 = 500;

/// This device's clock, in unix seconds.
fn now_unix() -> i64 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|d| d.as_secs() as i64)
        .unwrap_or_default()
}

/// The stored account with what the screen reads off it: the claims of
/// the certificate, verified offline against the embedded key, so the
/// licence state shows without a network. A certificate that no longer
/// verifies reads as no certificate.
fn premium_view(state: &PremiumState) -> serde_json::Value {
    let claims = state.certificate.as_deref().and_then(|certificate| {
        licence::verify_certificate(certificate, LICENCE_PUBLIC_KEY_HEX).ok()
    });
    json!({
        "key": state.key,
        "key_display": state.key.as_deref().map(licence::format_key),
        "claims": claims,
        "watched": state.watched,
        "acknowledged_offline_until": state.acknowledged_offline_until,
        "ntfy_base_url": NTFY_BASE_URL,
        "telegram_bot": TELEGRAM_BOT,
    })
}

/// The premium account as the vault keeps it, with its certificate
/// read. Returns a serialized `PremiumView`.
pub async fn premium_state() -> String {
    let manager = try_json!(manager());
    to_json(&premium_view(&manager.premium_state().await))
}

/// A client for the production server carrying the stored key.
async fn premium_client(manager: &WalletManager) -> Result<PremiumClient, String> {
    manager
        .premium_client(PREMIUM_BASE_URL)
        .await
        .map_err(|e| core_error_json(&e))
}

/// Rewrites the stored account state.
async fn store_premium(
    manager: &WalletManager,
    change: impl FnOnce(&mut PremiumState),
) -> Result<PremiumState, String> {
    let mut state = manager.premium_state().await;
    change(&mut state);
    manager
        .set_premium_state(state.clone())
        .await
        .map_err(|e| core_error_json(&e))?;
    Ok(state)
}

/// Enters an account key: checks its shape, asks the server for the
/// licence, verifies the certificate against the embedded key and
/// stores both. Returns the serialized `Licence`. A key the server does
/// not know, or one never paid for, comes back as the error the field
/// shows; nothing is stored then.
pub async fn premium_activate(key: String) -> String {
    let manager = try_json!(manager());
    if !licence::is_well_formed_key(&key) {
        return error_json(
            "invalid_input",
            "an account key is sixteen symbols, shown as xxxx-xxxx-xxxx-xxxx",
        );
    }
    let key = licence::normalize_key(&key);
    // Through the manager, like every other premium call: a key typed on
    // a phone whose node is an onion is checked over Tor too, and the
    // check never reaches the server by the clear route.
    let client = match manager
        .premium_client_with_key(PREMIUM_BASE_URL, Some(key.clone()))
        .await
    {
        Ok(client) => client,
        Err(e) => return core_error_json(&e),
    };
    let licence = match client.licence().await {
        Ok(licence) => licence,
        Err(e) => return core_error_json(&e),
    };
    try_json!(
        store_premium(manager, |state| {
            state.key = Some(key);
            state.certificate = Some(licence.certificate.clone());
            state.acknowledged_offline_until = None;
        })
        .await
    );
    to_json(&licence)
}

/// Fetches the certificate again with the stored key, for the paid
/// time a renewal added, and stores it. Returns the serialized
/// `Licence`.
pub async fn premium_refresh_licence() -> String {
    let manager = try_json!(manager());
    let client = try_json!(premium_client(manager).await);
    let licence = match client.licence().await {
        Ok(licence) => licence,
        Err(e) => return core_error_json(&e),
    };
    try_json!(
        store_premium(manager, |state| {
            state.certificate = Some(licence.certificate.clone());
        })
        .await
    );
    to_json(&licence)
}

/// Drops the key and its certificate from this device. The server goes
/// on watching what it was told to; the consents given here stay, so
/// the same key entered again asks nothing twice.
pub async fn premium_forget_key() -> String {
    let manager = try_json!(manager());
    try_json!(
        store_premium(manager, |state| {
            state.key = None;
            state.certificate = None;
            state.acknowledged_offline_until = None;
        })
        .await
    );
    ok_json()
}

/// Keeps the "watch is offline" banner quiet until `until` (unix
/// seconds), or lets it show again with `None`.
pub async fn premium_acknowledge_offline(until: Option<i64>) -> String {
    let manager = try_json!(manager());
    try_json!(
        store_premium(manager, |state| {
            state.acknowledged_offline_until = until;
        })
        .await
    );
    ok_json()
}

/// `GET /v1/account`: paid time, counts, and the network the server
/// watches. Returns a serialized `Account`.
pub async fn premium_account() -> String {
    let manager = try_json!(manager());
    let client = try_json!(premium_client(manager).await);
    match client.account().await {
        Ok(account) => to_json(&account),
        Err(e) => core_error_json(&e),
    }
}

/// The wallets the server watches for this key. Returns a serialized
/// `Vec<WalletWatch>`.
pub async fn premium_wallets() -> String {
    let manager = try_json!(manager());
    let client = try_json!(premium_client(manager).await);
    match client.wallets().await {
        Ok(wallets) => to_json(&wallets),
        Err(e) => core_error_json(&e),
    }
}

/// Hands one wallet to the server, under the app's own id and name,
/// with its descriptors as the vault holds them: both chains on two
/// lines when the wallet has a change descriptor, the external one
/// alone otherwise, and the address itself for a wallet that is one
/// address. The user's yes is recorded first, dated now; a second yes
/// keeps the first date.
pub async fn premium_watch_wallet(id: String) -> String {
    let manager = try_json!(manager());
    let Some(meta) = manager
        .list_wallets(None)
        .await
        .into_iter()
        .find(|wallet| wallet.id == id)
    else {
        return core_error_json(&CoreError::WalletNotFound(id));
    };
    let input = match &meta.kind {
        WalletKind::Descriptors {
            external,
            internal: Some(internal),
            ..
        } => format!("{external}\n{internal}"),
        WalletKind::Descriptors { external, .. } => external.clone(),
        WalletKind::SingleAddress { address } => address.clone(),
    };
    let now = now_unix();
    try_json!(store_premium(manager, |state| state.consent(&id, now)).await);
    let client = try_json!(premium_client(manager).await);
    match client.put_wallet(&id, &meta.name, &input).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Tells the server to stop watching a wallet and withdraws the consent
/// given for it: the switch going back on asks the question again, and
/// removing the wallet later queues nothing for a server that forgot it.
pub async fn premium_unwatch_wallet(id: String) -> String {
    let manager = try_json!(manager());
    match manager.premium_unwatch_wallet(PREMIUM_BASE_URL, &id).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// A channel as the screen reads it: the server's fields, plus the link
/// that opens the bot with the code filled in while a Telegram channel
/// waits for it.
fn channel_view(channel: &Channel) -> serde_json::Value {
    let mut value = json!(channel);
    if let Some(code) = &channel.link_code {
        value["start_url"] = json!(telegram_link_url(TELEGRAM_BOT, code));
    }
    value
}

/// The account's channels. Returns a serialized `Vec<ChannelView>`.
pub async fn premium_channels() -> String {
    let manager = try_json!(manager());
    let client = try_json!(premium_client(manager).await);
    match client.channels().await {
        Ok(channels) => to_json(&channels.iter().map(channel_view).collect::<Vec<_>>()),
        Err(e) => core_error_json(&e),
    }
}

/// Adds a channel. `kind` is `ntfy`, `telegram`, `email` or `webhook`;
/// `target` is the e-mail address or the webhook URL, nothing for
/// Telegram, and nothing for ntfy either: the topic is drawn here, 24
/// symbols nobody guesses, and returned once with the URL to subscribe
/// to. `secret` is the webhook's HMAC key. Returns
/// `{channel, topic, subscribe_url}`.
pub async fn premium_create_channel(
    kind: String,
    target: Option<String>,
    secret: Option<String>,
) -> String {
    let manager = try_json!(manager());
    let kind: ChannelKind = try_json!(parse_variant(&kind, "channel kind"));
    let (target, topic) = match (kind, target) {
        (ChannelKind::Ntfy, None) => {
            let topic = new_ntfy_topic();
            (Some(topic.clone()), Some(topic))
        }
        (_, target) => (target, None),
    };
    let client = try_json!(premium_client(manager).await);
    match client
        .create_channel(kind, target.as_deref(), secret.as_deref())
        .await
    {
        Ok(channel) => json!({
            "channel": channel_view(&channel),
            "topic": topic,
            "subscribe_url": topic
                .as_deref()
                .map(|topic| ntfy_subscribe_url(NTFY_BASE_URL, topic)),
        })
        .to_string(),
        Err(e) => core_error_json(&e),
    }
}

/// Confirms a channel with the code the server sent to it: the six
/// digits of a confirmation e-mail. Returns the serialized channel,
/// linked. A code that is wrong or past its hour comes back as
/// `premium_rejected` in the server's words, and so does one tried too
/// many times.
pub async fn premium_confirm_channel(id: String, code: String) -> String {
    let manager = try_json!(manager());
    match manager
        .premium_confirm_channel(PREMIUM_BASE_URL, &id, &code)
        .await
    {
        Ok(channel) => channel_view(&channel).to_string(),
        Err(e) => core_error_json(&e),
    }
}

/// Deletes the account on the server — the key, the wallets it watched,
/// the channels, the log — and then forgets it here. Nothing local is
/// dropped unless the server confirmed. There is no way back.
pub async fn premium_delete_account() -> String {
    let manager = try_json!(manager());
    match manager.premium_delete_account(PREMIUM_BASE_URL).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

pub async fn premium_delete_channel(id: String) -> String {
    let manager = try_json!(manager());
    let client = try_json!(premium_client(manager).await);
    match client.delete_channel(&id).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Sends a test message through one channel right away. The provider's
/// refusal comes back as `premium_rejected`, in the server's words.
pub async fn premium_test_channel(id: String) -> String {
    let manager = try_json!(manager());
    let client = try_json!(premium_client(manager).await);
    match client.test_channel(&id).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// The last events of the account, newest first, at most `RECENT_EVENTS`
/// of them. The server serves its log oldest first behind a cursor, so
/// the pages are walked to the end here. Returns a serialized
/// `Vec<Event>`.
pub async fn premium_recent_events() -> String {
    let manager = try_json!(manager());
    let client = try_json!(premium_client(manager).await);
    let mut recent: Vec<Event> = Vec::new();
    let mut after = 0;
    loop {
        let page = match client.events(after, EVENTS_PAGE).await {
            Ok(page) => page,
            Err(e) => return core_error_json(&e),
        };
        let Some(last) = page.last() else { break };
        after = last.id;
        let full = page.len() >= EVENTS_PAGE as usize;
        recent.extend(page);
        if recent.len() > RECENT_EVENTS {
            recent.drain(..recent.len() - RECENT_EVENTS);
        }
        if !full {
            break;
        }
    }
    recent.reverse();
    to_json(&recent)
}

/// `GET /v1/heartbeat`, verified against the embedded key and this
/// device's clock. Returns a serialized `HeartbeatReport`; a server
/// that cannot be reached, or whose answer does not verify, is the
/// error the "watch is offline" banner counts.
pub async fn premium_heartbeat() -> String {
    let manager = try_json!(manager());
    // A wallet removed while the server was out of reach leaves at the
    // next pulse: the queue is tried before the beat, and what still
    // cannot be told waits for the one after. Only the beat says
    // whether the watch is alive; a queue that will not flush does not.
    let _ = manager.premium_flush_unwatch(PREMIUM_BASE_URL).await;
    let client = try_json!(premium_client(manager).await);
    match client.heartbeat(now_unix()).await {
        Ok(report) => to_json(&report),
        Err(e) => core_error_json(&e),
    }
}

// --- live watch --------------------------------------------------------

/// Live events as JSON, for every isolate that listens. The core hands
/// its events to one consumer; that consumer is the task [`live_start`]
/// spawns here, in Rust, and it fans them out. An isolate that comes or
/// goes (the screens, the engine the foreground service hosts) never
/// takes the receiver from another, and never restarts the watch.
static LIVE_EVENTS: LazyLock<broadcast::Sender<String>> =
    LazyLock::new(|| broadcast::channel(256).0);

/// The task that consumes the events of the running watch. Behind an
/// async lock so a start that follows a stop waits for the old task to
/// be gone instead of mistaking it for a live one.
static LIVE_TASK: Mutex<Option<JoinHandle<()>>> = Mutex::const_new(None);

/// Starts the live watch of the active network. Idempotent: with a
/// watch already running, from this isolate or another, nothing is
/// restarted. Returns the serialized `WatchStatus`.
pub async fn live_start() -> String {
    let manager = try_json!(manager());
    let mut task = LIVE_TASK.lock().await;
    if task.as_ref().is_some_and(|running| !running.is_finished()) {
        return to_json(&manager.live_status().await);
    }
    let mut events = match manager.live_start().await {
        Ok(events) => events,
        Err(e) => return core_error_json(&e),
    };
    *task = Some(flutter_rust_bridge::spawn(async move {
        while let Some(event) = events.next().await {
            // Nobody listening is not an error: the watch still syncs,
            // and what it found is in the vault for whoever looks next.
            let _ = LIVE_EVENTS.send(to_json(&event));
        }
        let _ = LIVE_EVENTS.send(json!({ "type": "stopped" }).to_string());
    }));
    to_json(&manager.live_status().await)
}

/// Stops the live watch and closes its connection. Idempotent.
pub async fn live_stop() -> String {
    let manager = try_json!(manager());
    let mut task = LIVE_TASK.lock().await;
    manager.live_stop().await;
    if let Some(running) = task.take() {
        let _ = running.await;
    }
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

/// Subscribes this isolate to the live events, each a serialized
/// `LiveEvent`, plus `{"type":"stopped"}` when the watch ends. Returns
/// once the listener is gone. A listener that lags loses the oldest
/// events, never the watch: what was missed is on disk after the sync
/// that caused it.
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

/// What a sync found worth saying, as the Dart side hands it back: the
/// part of a `SyncReport` an announcement is made of.
#[derive(serde::Deserialize)]
struct Findings {
    wallet_id: String,
    #[serde(default)]
    new_txs: Vec<NewTx>,
    #[serde(default)]
    confirmed_txs: Vec<NewTx>,
}

/// Of what a sync found (`{wallet_id, new_txs, confirmed_txs}`), what
/// nobody has announced yet, now recorded as announced in the vault.
/// Every path that notifies from a sync of its own goes through here
/// first, so a transaction is said once whoever saw it first. Returns a
/// serialized `Vec<LiveTx>`.
pub async fn claim_announcements(findings_json: String) -> String {
    let manager = try_json!(manager());
    let findings: Findings = try_json!(from_json(&findings_json, "findings"));
    // The claim reads the wallet and the two lists; the rest of the
    // report is not its business and stays empty.
    let report = SyncReport {
        wallet_id: findings.wallet_id,
        new_tx_count: findings.new_txs.len() as u32,
        new_txs: findings.new_txs,
        confirmed_txs: findings.confirmed_txs,
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
pub async fn fetch_price(source: String, currency: String) -> String {
    let source: PriceSource = try_json!(parse_variant(&source, "price source"));
    let currency: FiatCurrency = try_json!(parse_variant(&currency, "currency"));
    match gerfaut_core::price::fetch_price(source, currency).await {
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

    fn payload(error: &CoreError) -> Value {
        serde_json::from_str(&core_error_json(error)).expect("the payload is JSON")
    }

    /// The words of a refusal are the server's own, and nothing else:
    /// they are what the card prints under "The Gerfaut server refused".
    #[test]
    fn a_refusal_carries_the_servers_words_alone() {
        let refused =
            CoreError::Premium(PremiumError::Rejected("wrong or expired code".to_owned()));
        let value = payload(&refused);
        assert_eq!(value["error"]["kind"], "premium_rejected");
        assert_eq!(value["error"]["message"], "wrong or expired code");
    }

    /// An answer that does not decode is the server out of reach: on a
    /// phone it is a hotel's login page, and a parser's complaint is
    /// not something to put in front of anybody.
    #[test]
    fn an_answer_that_does_not_decode_is_the_server_out_of_reach() {
        let portal = CoreError::Premium(PremiumError::UnexpectedResponse(
            "expected value at line 1 column 1".to_owned(),
        ));
        assert_eq!(payload(&portal)["error"]["kind"], "premium_unreachable");
    }

    /// A certificate and a heartbeat that do not check out are one case:
    /// this device cannot trust what it was handed.
    #[test]
    fn what_does_not_verify_is_one_kind() {
        let certificate = CoreError::Premium(PremiumError::InvalidCertificate("bad".to_owned()));
        let heartbeat = CoreError::Premium(PremiumError::InvalidHeartbeat("bad".to_owned()));
        let stale = CoreError::Premium(PremiumError::StaleHeartbeat { skew: 900 });
        for error in [certificate, heartbeat, stale] {
            assert_eq!(payload(&error)["error"]["kind"], "premium_invalid");
        }
    }

    /// A 5xx keeps its wrapper: the status is the only sign that the
    /// server answered, and the screen reads the sentence after it.
    #[test]
    fn an_unreachable_server_keeps_the_status_it_answered_with() {
        let down = CoreError::Premium(PremiumError::Unreachable(
            "HTTP 502: the confirmation e-mail could not be sent".to_owned(),
        ));
        let value = payload(&down);
        assert_eq!(value["error"]["kind"], "premium_unreachable");
        assert_eq!(
            value["error"]["message"],
            "the premium server is unreachable: HTTP 502: the confirmation e-mail could not be sent"
        );
    }
}
