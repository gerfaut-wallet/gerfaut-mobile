// Display formatting. Mirrors gerfaut-core's rules: 8 decimals in BTC,
// never silently rounded; identifiers truncated in the middle only.

import 'package:intl/intl.dart';

import 'models.dart';

const int satsPerBtc = 100000000;

/// No-break space for digit grouping: in the UI face the narrow
/// no-break space collapses and "1 000 000" reads as one blob.
const String groupSeparator = '\u00A0';

/// Masked replacement for any amount.
const String maskedValue = '•••••';

/// `123456` -> `"0.00123456"` — always 8 decimals.
String formatBtc(int sats) {
  final negative = sats < 0;
  final abs = sats.abs();
  final whole = abs ~/ satsPerBtc;
  final frac = (abs % satsPerBtc).toString().padLeft(8, '0');
  return '${negative ? '-' : ''}${groupThousands('$whole')}.$frac';
}

/// Signed variant with an explicit `+` for incoming amounts.
String formatBtcSigned(int sats) =>
    sats < 0 ? formatBtc(sats) : '+${formatBtc(sats)}';

/// `"1234567"` -> `"1 234 567"` (no-break spaces).
String groupThousands(String digits) {
  return digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => groupSeparator,
  );
}

String formatSats(int sats) {
  final sign = sats < 0 ? '-' : '';
  return '$sign${groupThousands('${sats.abs()}')} sats';
}

/// Middle truncation, ends preserved: `bc1qxy...k9fz`.
String truncateMiddle(String value, {int head = 6, int tail = 4}) {
  if (value.length <= head + tail + 3) return value;
  return '${value.substring(0, head)}...${value.substring(value.length - tail)}';
}

/// Preview text for an OP_RETURN payload: the recognized protocol name
/// when there is one, then the decoded text, then a short hex excerpt.
/// Kept short on purpose so a row never pushes its amount out of view.
String opReturnPreview(OpReturnData data) {
  final label = data.label;
  if (label != null) return label;
  final text = data.text;
  if (text != null) return truncateMiddle(text, head: 22, tail: 6);
  return truncateMiddle(data.hex, head: 12, tail: 6);
}

/// Relative freshness for sync stamps: "just now", "2 min ago", ...
String relativeTime(int unixSeconds, {DateTime? now}) {
  final nowMs = (now ?? DateTime.now()).millisecondsSinceEpoch;
  var seconds = nowMs ~/ 1000 - unixSeconds;
  if (seconds < 0) seconds = 0;
  if (seconds < 45) return 'just now';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes < 1 ? 1 : minutes} min ago';
  final hours = minutes ~/ 60;
  if (hours < 24) return '$hours h ago';
  final days = hours ~/ 24;
  return '$days d ago';
}

const List<String> _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// Block timestamp -> local date/time, unambiguous and compact.
String formatTimestamp(int unixSeconds) {
  final local = DateTime.fromMillisecondsSinceEpoch(
    unixSeconds * 1000,
  ).toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_months[local.month - 1]} $day, ${local.year}, $hour:$minute';
}

/// File-name slug of a wallet name: lowercase, runs of anything but
/// letters and digits collapsed to one dash. `"Cold storage"` ->
/// `"cold-storage"`; an empty result falls back to `"wallet"`.
String slugify(String name) {
  final slug = name
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
      .replaceAll(RegExp(r'^-+|-+$'), '');
  return slug.isEmpty ? 'wallet' : slug;
}

/// Display unit for amounts.
enum AmountUnit {
  btc('btc', 'BTC'),
  sats('sats', 'sats');

  const AmountUnit(this.id, this.label);

  final String id;
  final String label;

  static AmountUnit? fromId(String? id) {
    for (final unit in AmountUnit.values) {
      if (unit.id == id) return unit;
    }
    return null;
  }
}

/// Primary amount in the chosen display unit.
String formatAmount(int sats, AmountUnit unit) {
  return unit == AmountUnit.btc ? '${formatBtc(sats)} BTC' : formatSats(sats);
}

/// Signed primary amount in the chosen display unit.
String formatAmountSigned(int sats, AmountUnit unit) {
  if (unit == AmountUnit.btc) return '${formatBtcSigned(sats)} BTC';
  return sats < 0 ? formatSats(sats) : '+${formatSats(sats)}';
}

/// Fiat value of an amount at a given BTC rate, with the currency's
/// symbol. Small values keep four decimals so they never round to zero.
String formatFiat(int sats, double rate, FiatCurrency currency) {
  final value = sats / satsPerBtc * rate;
  final formatter = NumberFormat.simpleCurrency(
    name: currency.code,
    decimalDigits: value.abs() < 1 ? 4 : 2,
  );
  return formatter.format(value);
}
