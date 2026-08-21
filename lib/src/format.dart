// Display formatting. Mirrors gerfaut-core's rules: 8 decimals in BTC,
// never silently rounded; identifiers truncated in the middle only.

const int satsPerBtc = 100000000;

/// Narrow no-break space, used for digit grouping.
const String narrowSpace = ' ';

/// Masked replacement for any amount.
const String masked = '•••••';

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

/// `"1234567"` -> `"1 234 567"` (narrow no-break spaces).
String groupThousands(String digits) {
  return digits.replaceAllMapped(
    RegExp(r'\B(?=(\d{3})+(?!\d))'),
    (_) => narrowSpace,
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
