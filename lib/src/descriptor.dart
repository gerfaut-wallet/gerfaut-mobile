// A wallet's two descriptors as one: the receive branch and the change
// branch written as a single BIP-389 multipath descriptor (`/<0;1>/*`),
// the form a wallet is usually imported and exported in. The core keeps
// the two apart; a page that showed only the receive one handed whoever
// copied it a wallet without its change. The desktop app writes it the
// same way, to the character.

/// The characters a descriptor may hold, in the order the BIP-380
/// checksum reads them.
const String _inputCharset =
    "0123456789()[],'/*abcdefgh@:\$%{}"
    'IJKLMNOPQRSTUVWXYZ&+-.;<=>?!^_|~'
    'ijklmnopqrstuvwxyzABCDEFGH`#"\\ ';
const String _checksumCharset = 'qpzry9x8gf2tvdw0s3jn54khce6mua7l';
const List<int> _generator = [
  0xf5dee51989,
  0xa9fdca3312,
  0x1bab10e32d,
  0x3706b1677a,
  0x644d626ffd,
];

int _polymod(int c, int value) {
  final top = c >> 35;
  var next = ((c & 0x7ffffffff) << 5) ^ value;
  for (var i = 0; i < 5; i++) {
    if ((top >> i) & 1 == 1) next ^= _generator[i];
  }
  return next;
}

/// The eight-character BIP-380 checksum of a descriptor written without
/// one, or null when it holds a character no descriptor may.
String? descriptorChecksum(String body) {
  var c = 1;
  var group = 0;
  var count = 0;
  for (final rune in body.runes) {
    final position = _inputCharset.indexOf(String.fromCharCode(rune));
    if (position == -1) return null;
    c = _polymod(c, position & 31);
    group = group * 3 + (position >> 5);
    count += 1;
    if (count == 3) {
      c = _polymod(c, group);
      group = 0;
      count = 0;
    }
  }
  if (count > 0) c = _polymod(c, group);
  for (var i = 0; i < 8; i++) {
    c = _polymod(c, 0);
  }
  c ^= 1;
  final checksum = StringBuffer();
  for (var i = 0; i < 8; i++) {
    checksum.write(_checksumCharset[(c >> (5 * (7 - i))) & 31]);
  }
  return checksum.toString();
}

/// The descriptor without its checksum, when the checksum it carries is
/// the right one; null otherwise.
String? _verifiedBody(String descriptor) {
  final parts = descriptor.split('#');
  if (parts.length != 2) return null;
  return descriptorChecksum(parts[0]) == parts[1] ? parts[0] : null;
}

/// The child step before each wildcard: `/0/*`, `/1/*'`.
final RegExp _step = RegExp(r"/(\d+)/\*(['h]?)");

/// The receive and change descriptors as one multipath descriptor, with
/// its checksum; null when they are not one wallet's two branches, the
/// same text but for the step before each wildcard. Each descriptor's
/// own checksum is checked first, which also checks the one computed
/// here.
String? multipathDescriptor(String external, String internal) {
  final receive = _verifiedBody(external);
  final change = _verifiedBody(internal);
  if (receive == null || change == null) return null;
  final receiveSteps = _step.allMatches(receive).toList();
  final changeSteps = _step.allMatches(change).toList();
  if (receiveSteps.isEmpty || receiveSteps.length != changeSteps.length) {
    return null;
  }
  String bare(String text) =>
      text.replaceAllMapped(_step, (m) => '/*${m.group(2)}');
  if (bare(receive) != bare(change)) return null;
  var differs = false;
  var index = 0;
  final body = receive.replaceAllMapped(_step, (m) {
    final step = m.group(1)!;
    final hardened = m.group(2)!;
    final other = changeSteps[index++].group(1)!;
    if (step == other) return '/$step/*$hardened';
    differs = true;
    return '/<$step;$other>/*$hardened';
  });
  if (!differs) return null;
  final checksum = descriptorChecksum(body);
  return checksum == null ? null : '$body#$checksum';
}
