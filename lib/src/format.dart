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

/// An index at the end of a label, after the last colon.
final RegExp _outpointIndex = RegExp(r'^\d+$');

/// The `:12` an outpoint ends with, empty for anything else — an
/// address carries no colon, and neither does `OP_RETURN`.
///
/// It is never cut, so whoever budgets room for a label sets it aside
/// before counting the characters it may drop.
String outpointSuffix(String value) {
  final colon = value.lastIndexOf(':');
  if (colon > 0 && _outpointIndex.hasMatch(value.substring(colon + 1))) {
    return value.substring(colon);
  }
  return '';
}

/// A branch label cut to size, with an outpoint's index kept whole:
/// `a1b2c3...8f90:12`.
///
/// Two inputs can carry the same address, never the same outpoint, so
/// the index is the half that names one. A fixed tail count keeps `:0`
/// by luck and loses the index the moment the vout runs to two digits:
/// it is swallowed into the txid's tail and the reader can no longer
/// tell where it starts. Split on the last colon, cut the txid, put the
/// whole index back. Anything without one is cut in the middle as usual.
String shortenBranchLabel(String value, {int head = 6, int tail = 4}) {
  final suffix = outpointSuffix(value);
  if (suffix.isEmpty) return truncateMiddle(value, head: head, tail: tail);
  final txid = value.substring(0, value.length - suffix.length);
  return '${truncateMiddle(txid, head: head, tail: tail)}$suffix';
}

/// Block heights and unix times share the locktime field: below this
/// value it names a block, at or above it a moment (BIP-65).
const int locktimeThreshold = 500000000;

/// True when a locktime names a moment rather than a block.
bool locktimeIsTime(int locktime) => locktime >= locktimeThreshold;

/// A locktime in the terms it was written in. Printed raw, a
/// time-based one reads as an absurd block height — the two surfaces
/// that show it must not each decode it their own way, or one of them
/// will not decode it at all.
String formatLocktime(int locktime) {
  if (locktime <= 0) return 'none';
  if (locktimeIsTime(locktime)) return formatTimestamp(locktime);
  return 'block ${groupThousands('$locktime')}';
}

/// What a locktime promises, which is not the same thing on either
/// side of the threshold: a block below it, a clock above it.
String locktimeHint(int locktime) => locktimeIsTime(locktime)
    ? 'Earliest time this transaction could be mined'
    : 'Earliest block this transaction could be mined in';

/// A certificate fingerprint in rows two eyes can compare: eight byte
/// pairs a line, the colons the core stores kept, so what is on screen
/// is what `openssl x509 -noout -fingerprint -sha256` prints.
String groupFingerprint(String fingerprint) {
  final pairs = fingerprint.split(':');
  final lines = <String>[];
  for (var i = 0; i < pairs.length; i += 8) {
    final end = i + 8 < pairs.length ? i + 8 : pairs.length;
    lines.add(pairs.sublist(i, end).join(':'));
  }
  return lines.join('\n');
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
  final local = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000)
      .toLocal();
  final day = local.day.toString().padLeft(2, '0');
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_months[local.month - 1]} $day, ${local.year}, $hour:$minute';
}

/// A day alone, in the language and order of [formatTimestamp]:
/// `Mar 17, 2030`. For a deadline the hour would only pretend to a
/// precision an estimate does not have.
String formatDate(int unixSeconds) {
  final local = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000)
      .toLocal();
  final day = local.day.toString().padLeft(2, '0');
  return '${_months[local.month - 1]} $day, ${local.year}';
}

/// A clock time in the reader's zone, 24-hour, no date: `12:40`. For a
/// figure whose freshness matters more than its day.
String formatClock(int unixSeconds) {
  final local = DateTime.fromMillisecondsSinceEpoch(unixSeconds * 1000)
      .toLocal();
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// A fee rate in sat/vB: whole when it is whole, else one decimal.
/// `12.0` -> `"12 sat/vB"`, `8.5` -> `"8.5 sat/vB"`.
String formatFeeRate(double rate) {
  final digits = rate == rate.roundToDouble()
      ? rate.toStringAsFixed(0)
      : rate.toStringAsFixed(1);
  return '$digits sat/vB';
}

/// A byte count the way a file manager states it: whole bytes under a
/// kilobyte, then one decimal in binary units. `1229` -> `"1.2 KB"`.
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)} KB';
  return '${(kb / 1024).toStringAsFixed(1)} MB';
}

/// A block count with its unit: `1 432 blocks`, `1 block`.
String formatBlocks(int blocks) =>
    '${groupThousands('$blocks')} ${blocks == 1 ? 'block' : 'blocks'}';

const int _minute = 60;
const int _hour = 60 * _minute;
const int _day = 24 * _hour;
const int _month = 30 * _day;
const int _year = 365 * _day;

/// A duration as an estimate, always said as one: `about 10 days`,
/// `about 3 hours`, `about 1 year 2 months`.
///
/// Two units while the leading count is one or two — "about 1 day 12
/// hours" is where rounding to a day would be a third off — and one
/// rounded unit from three on, where the smaller unit is noise. Years
/// carry months, days carry hours, hours carry minutes; the minute is
/// the floor, and under it there is nothing worth a figure.
String formatDuration(int seconds) {
  if (seconds < _minute) return 'under a minute';
  String unit(int count, String name) => '$count $name${count == 1 ? '' : 's'}';
  String twoOrOne(int big, String bigName, int small, String smallName) {
    final lead = seconds ~/ big;
    if (lead >= 3) return 'about ${unit((seconds / big).round(), bigName)}';
    final rest = (seconds - lead * big) ~/ small;
    final head = unit(lead, bigName);
    return rest == 0 ? 'about $head' : 'about $head ${unit(rest, smallName)}';
  }

  if (seconds >= _year) return twoOrOne(_year, 'year', _month, 'month');
  if (seconds >= _day) return twoOrOne(_day, 'day', _hour, 'hour');
  if (seconds >= _hour) return twoOrOne(_hour, 'hour', _minute, 'minute');
  return 'about ${unit(seconds ~/ _minute, 'minute')}';
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

/// One formatter pair per currency: building a [NumberFormat] parses a
/// pattern, and every amount on screen asks for one.
final Map<FiatCurrency, ({NumberFormat natural, NumberFormat precise})>
_fiatFormatters = {};

/// Formatter for a currency, in its own convention or in the finer one
/// small values need.
NumberFormat _fiatFormatter(FiatCurrency currency, {required bool precise}) {
  final pair = _fiatFormatters.putIfAbsent(currency, () {
    // No decimalDigits: the currency's own convention applies, two for
    // the euro, none for the yen.
    final natural = NumberFormat.simpleCurrency(name: currency.code);
    return (
      natural: natural,
      precise: (natural.decimalDigits ?? 2) >= 4
          ? natural
          : NumberFormat.simpleCurrency(name: currency.code, decimalDigits: 4),
    );
  });
  return precise ? pair.precise : pair.natural;
}

/// Fiat value of an amount at a given BTC rate, with the currency's
/// symbol and its own number of decimals — never two forced on a
/// currency that has none. Small values keep four decimals so they
/// never round to zero.
String formatFiat(int sats, double rate, FiatCurrency currency) {
  final value = sats / satsPerBtc * rate;
  return _fiatFormatter(currency, precise: value.abs() < 1).format(value);
}
