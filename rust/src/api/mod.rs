//! JSON-string bridge over the gerfaut-core wallet manager.
//!
//! Every function takes and returns strings carrying JSON, keeping the
//! Dart side decoupled from the core types: success payloads mirror the
//! core structures serialized with serde, failures serialize to
//! `{"error": {"kind": "...", "message": "..."}}`. Nothing panics across
//! the FFI boundary.

use gerfaut_core::backup::{BackupOptions, ImportChoices};
use gerfaut_core::chain::BackendConfig;
use gerfaut_core::export::ExportOptions;
use gerfaut_core::input::{ImportOptions, ParsedInput, ScriptKind};
use gerfaut_core::lock::LockKind;
use gerfaut_core::price::{FiatCurrency, PriceSource};
use gerfaut_core::store::VaultKey;
use gerfaut_core::{CoreError, Network, WalletManager};
use serde_json::json;
use tokio::sync::OnceCell;

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
        CoreError::Internal(_) => "internal",
    }
}

/// Deserializes one JSON argument, naming what it should have been.
fn from_json<T: serde::de::DeserializeOwned>(raw: &str, what: &str) -> Result<T, String> {
    serde_json::from_str(raw).map_err(|e| error_json("bad_json", format!("invalid {what} JSON: {e}")))
}

fn core_error_json(error: &CoreError) -> String {
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
        *byte =
            u8::from_str_radix(pair, 16).map_err(|_| bad("vault key must be hexadecimal"))?;
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

// --- views -------------------------------------------------------------

pub async fn wallet_snapshot(id: String) -> String {
    let manager = try_json!(manager());
    match manager.wallet_snapshot(&id).await {
        Ok(snapshot) => to_json(&snapshot),
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
    match manager.set_app_lock(kind, &secret, current.as_deref()).await {
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

/// Seconds away from the app before it locks again; `None` means only
/// at launch and on request.
pub async fn set_auto_lock(secs: Option<u32>) -> String {
    let manager = try_json!(manager());
    match manager.set_auto_lock(secs).await {
        Ok(()) => ok_json(),
        Err(e) => core_error_json(&e),
    }
}

/// Whether the phone's biometric prompt may stand in for the secret.
pub async fn set_biometric_unlock(enabled: bool) -> String {
    let manager = try_json!(manager());
    match manager.set_biometric_unlock(enabled).await {
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
pub async fn check_update(current_version: String) -> String {
    match gerfaut_core::updates::check_update(UPDATE_REPO, &current_version).await {
        Ok(check) => to_json(&check),
        Err(e) => core_error_json(&e),
    }
}
