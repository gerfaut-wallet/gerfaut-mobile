import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/format.dart';
import 'package:gerfaut/src/models.dart';

void main() {
  group('formatBtc', () {
    test('keeps all 8 decimals', () {
      expect(formatBtc(0), '0.00000000');
      expect(formatBtc(1), '0.00000001');
      expect(formatBtc(123456), '0.00123456');
      expect(formatBtc(100000000), '1.00000000');
    });

    test('groups whole bitcoins with no-break spaces', () {
      expect(formatBtc(2100000000000000), '21\u00A0000\u00A0000.00000000');
    });

    test('signs explicitly', () {
      expect(formatBtcSigned(123456), '+0.00123456');
      expect(formatBtcSigned(-123456), '-0.00123456');
    });
  });

  group('formatSats', () {
    test('groups thousands with a no-break space', () {
      expect(formatSats(1234567), '1\u00A0234\u00A0567 sats');
      expect(formatSats(-500), '-500 sats');
    });
  });

  group('groupThousands', () {
    test('leaves short numbers alone', () {
      expect(groupThousands('999'), '999');
    });

    test('separates with a no-break space, never a narrow one', () {
      expect(groupSeparator, ' ');
      expect(groupThousands('1000000'), contains(' '));
      expect(groupThousands('1000000'), isNot(contains(' ')));
    });
  });

  group('truncateMiddle', () {
    test('keeps both ends', () {
      expect(
        truncateMiddle('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'),
        'bc1qw5...f3t4',
      );
    });

    test('never lengthens', () {
      expect(truncateMiddle('short'), 'short');
    });
  });

  group('shortenBranchLabel', () {
    const txid =
        'a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4e5f60718293a4b5c6d7e8f90';

    test('keeps the whole index, however many digits it runs to', () {
      // The bug this exists for: a fixed tail count keeps `:0` by luck
      // and swallows anything longer into the txid's tail.
      expect(shortenBranchLabel('$txid:0'), 'a1b2c3...8f90:0');
      expect(shortenBranchLabel('$txid:12'), 'a1b2c3...8f90:12');
      expect(shortenBranchLabel('$txid:345'), 'a1b2c3...8f90:345');
      expect(shortenBranchLabel('$txid:1000000'), 'a1b2c3...8f90:1000000');
    });

    test('cuts the txid alone, at the size it is given', () {
      expect(
        shortenBranchLabel('$txid:12', head: 10, tail: 8),
        'a1b2c3d4e5...6d7e8f90:12',
      );
    });

    test('leaves anything that is not an outpoint to the middle cut', () {
      // An output is named by its address, and no address carries a
      // colon.
      expect(
        shortenBranchLabel('bc1qw508d6qejxtdg4y5r3zarvary0c5xw7kv8f3t4'),
        'bc1qw5...f3t4',
      );
      expect(shortenBranchLabel('OP_RETURN'), 'OP_RETURN');
      expect(shortenBranchLabel('Coinbase'), 'Coinbase');
      // A colon with nothing numeric behind it names no index.
      expect(outpointSuffix('Unknown input'), '');
      expect(outpointSuffix('$txid:beef'), '');
      expect(outpointSuffix('$txid:12'), ':12');
    });
  });

  group('formatLocktime', () {
    test('reads a value under the threshold as a height', () {
      expect(formatLocktime(840000), 'block 840 000');
      expect(locktimeIsTime(840000), isFalse);
      expect(
        locktimeHint(840000),
        'Earliest block this transaction could be mined in',
      );
    });

    test('reads a value at or above the threshold as a moment', () {
      // Printed raw, 1 755 000 000 reads as an absurd block height.
      expect(formatLocktime(1755000000), formatTimestamp(1755000000));
      expect(locktimeIsTime(locktimeThreshold), isTrue);
      expect(
        locktimeHint(1755000000),
        'Earliest time this transaction could be mined',
      );
    });

    test('says none when there is none', () {
      expect(formatLocktime(0), 'none');
    });
  });

  group('relativeTime', () {
    final now = DateTime.fromMillisecondsSinceEpoch(1755000000000);
    final nowSecs = 1755000000;

    test('reads naturally', () {
      expect(relativeTime(nowSecs - 10, now: now), 'just now');
      expect(relativeTime(nowSecs - 120, now: now), '2 min ago');
      expect(relativeTime(nowSecs - 7200, now: now), '2 h ago');
      expect(relativeTime(nowSecs - 172800, now: now), '2 d ago');
    });
  });

  group('formatAmount', () {
    test('follows the display unit', () {
      expect(formatAmount(123456, AmountUnit.btc), '0.00123456 BTC');
      expect(formatAmount(123456, AmountUnit.sats), formatSats(123456));
    });

    test('signs explicitly in both units', () {
      expect(formatAmountSigned(123456, AmountUnit.btc), '+0.00123456 BTC');
      expect(formatAmountSigned(-123456, AmountUnit.btc), '-0.00123456 BTC');
      expect(
        formatAmountSigned(123456, AmountUnit.sats),
        '+${formatSats(123456)}',
      );
      expect(formatAmountSigned(-123456, AmountUnit.sats), formatSats(-123456));
    });
  });

  group('formatFiat', () {
    test('applies the rate with the currency symbol', () {
      expect(formatFiat(100000000, 50000, FiatCurrency.usd), r'$50,000.00');
      expect(formatFiat(100000000, 50000, FiatCurrency.eur), '€50,000.00');
    });

    test('small values keep four decimals', () {
      expect(formatFiat(100, 50000, FiatCurrency.usd), r'$0.0500');
      expect(formatFiat(-100, 50000, FiatCurrency.usd), r'-$0.0500');
    });

    test('a currency without a minor unit gets no decimals', () {
      // The yen, the won, the dong and the rupiah have no cents: two
      // forced decimals would be a number that does not exist.
      for (final currency in [
        FiatCurrency.jpy,
        FiatCurrency.krw,
        FiatCurrency.vnd,
        FiatCurrency.idr,
      ]) {
        final formatted = formatFiat(100000000, 7654321, currency);
        expect(formatted, contains('7,654,321'));
        expect(formatted, isNot(contains('.')));
      }
      expect(formatFiat(100000000, 1234.6, FiatCurrency.jpy), '¥1,235');
    });

    test('a small value in a whole currency still shows', () {
      // Under one unit the four decimals win over the convention: a
      // rounded zero would read as no value at all.
      expect(formatFiat(1, 15000000, FiatCurrency.jpy), '¥0.1500');
    });
  });

  group('formatDuration', () {
    test('rounds one unit once the lead count reaches three', () {
      expect(formatDuration(10 * 86400), 'about 10 days');
      expect(formatDuration(3 * 3600), 'about 3 hours');
      expect(formatDuration(365 * 86400), 'about 1 year');
      // 1,432 blocks and 20,440 blocks at ten minutes each.
      expect(formatDuration(1432 * 600), 'about 10 days');
      expect(formatDuration(20440 * 600), 'about 142 days');
      // 100 units of 512 seconds, the shortest time-based lock shape.
      expect(formatDuration(51200), 'about 14 hours');
      expect(formatDuration(5 * 60), 'about 5 minutes');
    });

    test('keeps two units while the lead count is one or two', () {
      expect(formatDuration(425 * 86400), 'about 1 year 2 months');
      expect(formatDuration(36 * 3600), 'about 1 day 12 hours');
      expect(formatDuration(80 * 60), 'about 1 hour 20 minutes');
      expect(formatDuration(2 * 86400), 'about 2 days');
    });

    test('has the minute for a floor', () {
      expect(formatDuration(59), 'under a minute');
      expect(formatDuration(0), 'under a minute');
      expect(formatDuration(60), 'about 1 minute');
    });

    test('carries a twelfth month into the year', () {
      // 365-day years and 30-day months leave room for a twelfth month
      // past the eleventh: it is a year, never "1 year 12 months".
      expect(formatDuration((365 + 362) * 86400), 'about 2 years');
      expect(formatDuration((365 + 335) * 86400), 'about 1 year 11 months');
      expect(formatDuration((2 * 365 + 362) * 86400), 'about 3 years');
    });
  });

  group('formatBlocks', () {
    test('groups thousands and agrees in number', () {
      expect(formatBlocks(1432), '1 432 blocks');
      expect(formatBlocks(52560), '52 560 blocks');
      expect(formatBlocks(1), '1 block');
    });
  });

  group('formatDate', () {
    test('reads like the timestamp without its hour', () {
      // Noon UTC, so the day holds in any zone the tests run in.
      expect(formatDate(1899979200), 'Mar 17, 2030');
    });
  });
}
