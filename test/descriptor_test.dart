import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/descriptor.dart';

/// A public test key, the one gerfaut-core's tests use.
const String tpub =
    'tpubDDnGNapGEY6AZAdQbfRJgMg9fvz8pUBrLwvyvUqEgcUfgzM6zc2eVK4vY9x9L5FJWdX8WumXuLEDV5zDZnTfbn87vLe9XceCFwTu9so9Kks';

/// Descriptors as the core writes them, checksums computed by
/// rust-miniscript: the ground truth this module is held to.
const String receive = "wpkh([9a6a2580/84'/1'/0']$tpub/0/*)#76ngmkux";
const String change = "wpkh([9a6a2580/84'/1'/0']$tpub/1/*)#0wkfxrv7";

void main() {
  group('the descriptor checksum', () {
    test('is the one BIP 380 and rust-miniscript compute', () {
      // The example of BIP 380.
      expect(descriptorChecksum('raw(deadbeef)'), '89f8spxm');
      for (final (body, checksum) in [
        ("wpkh([9a6a2580/84'/1'/0']$tpub/0/*)", '76ngmkux'),
        ("wpkh([9a6a2580/84'/1'/0']$tpub/1/*)", '0wkfxrv7'),
        ("tr([9a6a2580/86'/1'/0']$tpub/0/*)", '06k0xnt5'),
        ("tr([9a6a2580/86'/1'/0']$tpub/1/*)", '7wnwmxmv'),
        ('wpkh($tpub/0/*)', 'dmh8w44d'),
        ('wpkh($tpub/1/*)', 'u0jxnq94'),
      ]) {
        expect(descriptorChecksum(body), checksum, reason: body);
      }
    });

    test('refuses a character no descriptor holds', () {
      expect(descriptorChecksum('wpkh(é)'), isNull);
    });
  });

  group("one wallet's two branches as one descriptor", () {
    test('writes them as a multipath descriptor, checksum included', () {
      final multipath = multipathDescriptor(receive, change)!;
      final [body, checksum] = multipath.split('#');
      expect(body, "wpkh([9a6a2580/84'/1'/0']$tpub/<0;1>/*)");
      expect(checksum, descriptorChecksum(body));
    });

    test("puts each key's own pair in place, in a multisig", () {
      String multi(int a, int b) =>
          "wsh(multi(1,[9a6a2580/48'/1'/0'/2']$tpub/$a/*,"
          "[00000000/48'/1'/0'/2']$tpub/$b/*))";
      String withChecksum(String body) => '$body#${descriptorChecksum(body)}';
      expect(
        multipathDescriptor(
          withChecksum(multi(0, 2)),
          withChecksum(multi(1, 3)),
        ),
        withChecksum(
          "wsh(multi(1,[9a6a2580/48'/1'/0'/2']$tpub/<0;1>/*,"
          "[00000000/48'/1'/0'/2']$tpub/<2;3>/*))",
        ),
      );
    });

    test('gives up rather than write a descriptor it cannot vouch for', () {
      // A checksum that does not match its descriptor.
      expect(
        multipathDescriptor(receive.replaceAll('76ngmkux', '76ngmkuy'), change),
        isNull,
      );
      // None at all.
      expect(multipathDescriptor(receive.split('#')[0], change), isNull);
      // Two descriptors that are not the same wallet.
      const other = "tr([9a6a2580/86'/1'/0']$tpub/1/*)#7wnwmxmv";
      expect(multipathDescriptor(receive, other), isNull);
      // The same branch twice.
      expect(multipathDescriptor(receive, receive), isNull);
    });
  });
}
