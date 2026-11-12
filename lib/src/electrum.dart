// Server URL helpers: the settings form edits an Electrum server's host,
// port, and TLS separately, while the core stores one `ssl://` or
// `tcp://` URL; and it says when an Esplora address goes in the clear.

/// Parts of an Electrum server URL.
typedef ElectrumParts = ({String host, String port, bool tls});

/// Splits an Electrum URL into host, port, and TLS flag.
ElectrumParts parseElectrumUrl(String url) {
  final tls = !url.startsWith('tcp://');
  final rest = url.replaceFirst(RegExp(r'^(ssl|tcp)://'), '');
  final colon = rest.indexOf(':');
  if (colon < 0) return (host: rest, port: '', tls: tls);
  return (
    host: rest.substring(0, colon),
    port: rest.substring(colon + 1),
    tls: tls,
  );
}

/// Builds the URL the core expects.
String buildElectrumUrl(String host, String port, bool tls) {
  return '${tls ? 'ssl' : 'tcp'}://${host.trim()}:${port.trim()}';
}

/// Whether an Esplora address is read over plain HTTP outside Tor: an
/// `http://` server whose host is not a `.onion`, which Tor carries
/// encrypted whatever the scheme. What anything on the path reads is
/// then what an Electrum server without TLS would give it.
bool isPlainHttp(String url) {
  final parsed = Uri.tryParse(url.trim());
  if (parsed == null || parsed.scheme.toLowerCase() != 'http') return false;
  var host = parsed.host.toLowerCase();
  if (host.endsWith('.')) host = host.substring(0, host.length - 1);
  return !host.endsWith('.onion');
}
