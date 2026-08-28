// What the broadcast screen hands the core when a file is imported. The
// core detects the form from the content, never from the extension; the
// only thing to decide here is whether the bytes are text or binary.

import 'dart:convert';
import 'dart:typed_data';

/// PSBT file magic, BIP-174.
const List<int> _psbtMagic = [0x70, 0x73, 0x62, 0x74, 0xff];

/// The text to decode from a file's bytes: a binary PSBT or transaction
/// as hex, anything readable as the text it holds. Bytes that are not
/// printable text (a `.txn` file starts with the version, four raw
/// bytes) also go as hex, since text with control characters in it is
/// neither hex nor base64.
String transactionTextOf(Uint8List bytes) {
  if (bytes.length >= _psbtMagic.length) {
    var magic = true;
    for (var i = 0; i < _psbtMagic.length; i++) {
      if (bytes[i] != _psbtMagic[i]) {
        magic = false;
        break;
      }
    }
    if (magic) return _hex(bytes);
  }
  try {
    final text = utf8.decode(bytes);
    if (text.runes.every(_printable)) return text.trim();
  } on FormatException {
    // Not UTF-8: binary.
  }
  return _hex(bytes);
}

bool _printable(int rune) =>
    rune >= 0x20 || rune == 0x09 || rune == 0x0a || rune == 0x0d;

String _hex(Uint8List bytes) {
  final buffer = StringBuffer();
  for (final byte in bytes) {
    buffer.write(byte.toRadixString(16).padLeft(2, '0'));
  }
  return buffer.toString();
}
