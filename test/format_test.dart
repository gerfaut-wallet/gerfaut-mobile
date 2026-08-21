import 'package:flutter_test/flutter_test.dart';
import 'package:gerfaut/src/format.dart';

void main() {
  group('formatBtc', () {
    test('keeps all 8 decimals', () {
      expect(formatBtc(0), '0.00000000');
      expect(formatBtc(1), '0.00000001');
      expect(formatBtc(123456), '0.00123456');
      expect(formatBtc(100000000), '1.00000000');
    });

    test('groups whole bitcoins with narrow no-break spaces', () {
      expect(formatBtc(2100000000000000), '21 000 000.00000000');
    });

    test('signs explicitly', () {
      expect(formatBtcSigned(123456), '+0.00123456');
      expect(formatBtcSigned(-123456), '-0.00123456');
    });
  });

  group('formatSats', () {
    test('groups thousands with a narrow space', () {
      expect(formatSats(1234567), '1 234 567 sats');
      expect(formatSats(-500), '-500 sats');
    });
  });

  group('groupThousands', () {
    test('leaves short numbers alone', () {
      expect(groupThousands('999'), '999');
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
}
