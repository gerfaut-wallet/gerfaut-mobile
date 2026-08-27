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
      expect(
        formatAmountSigned(-123456, AmountUnit.sats),
        formatSats(-123456),
      );
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
}
