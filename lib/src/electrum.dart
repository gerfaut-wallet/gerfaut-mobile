// Electrum URL helpers: the settings form edits host, port, and TLS
// separately; the core stores one `ssl://` or `tcp://` URL.

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
