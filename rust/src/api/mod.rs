//! JSON-string bridge over the gerfaut-core wallet manager.
//!
//! Every function takes and returns strings carrying JSON, keeping the
//! Dart side decoupled from the core types: success payloads mirror the
//! core structures serialized with serde, failures serialize to
//! `{"error": {"kind": "...", "message": "..."}}`. Nothing panics across
//! the FFI boundary.

use gerfaut_core::chain::BackendConfig;
use gerfaut_core::export::ExportOptions;
use gerfaut_core::input::{ParsedInput, ScriptKind};
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
        CoreError::Descriptor(_) => "descriptor",
        CoreError::Internal(_) => "internal",
    }
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

/// Stores one small app preference in the encrypted vault.
pub async fn set_app_pref(key: String, value: String) -> String {
    let manager = try_json!(manager());
    match manager.set_app_pref(key, value).await {
        Ok(()) => ok_json(),
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
/// `kraken`, `mempool_space`; `currency` one of `eur`, `usd`, `gbp`,
/// `chf`. Returns a serialized `PriceQuote`.
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
