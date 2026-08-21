// Public explorer links, per network. Regtest has none.

import 'models.dart';

/// Explorer page of a transaction, or null when no public explorer
/// exists for the network.
String? explorerTxUrl(Network network, String txid) {
  return switch (network) {
    Network.mainnet => 'https://mempool.space/tx/$txid',
    Network.signet => 'https://mempool.space/signet/tx/$txid',
    Network.testnet4 => 'https://mempool.space/testnet4/tx/$txid',
    Network.regtest => null,
  };
}
