/// Calendar dates and exam countdown wording shared by notes and the planner.
library;

/// A local calendar day as a sortable key.
///
/// Calendar days retain their date across timezone and daylight-saving changes.
String dayKey(DateTime d) => '${d.year.toString().padLeft(4, '0')}-'
    '${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Parse a [dayKey] back to local midnight. Null if it isn't one.
DateTime? parseDayKey(String s) {
  final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(s);
  if (m == null) return null;
  final y = int.parse(m.group(1)!);
  final mo = int.parse(m.group(2)!);
  final d = int.parse(m.group(3)!);
  if (mo < 1 || mo > 12 || d < 1 || d > 31) return null;
  final out = DateTime(y, mo, d);
  // Dart rolls 31 February over into March rather than rejecting it.
  return (out.month == mo && out.day == d) ? out : null;
}

/// Whole calendar days from [from] to [to], ignoring the time of day.
///
/// Computed through UTC on purpose. Subtracting two local `DateTime`s and
/// reading `inDays` is wrong twice a year: a spring-forward day is 23 hours,
/// so "tomorrow" comes out as 0 days away and an exam countdown skips a
/// number. Normalising to UTC midnight first makes every day exactly 24 hours.
int daysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

/// The countdown as a student would say it out loud.
String formatCountdown(int daysLeft) {
  if (daysLeft < 0) {
    final ago = -daysLeft;
    if (ago == 1) return 'yesterday';
    return ago < 14 ? '$ago days ago' : 'passed';
  }
  return switch (daysLeft) {
    0 => 'today',
    1 => 'tomorrow',
    _ => '$daysLeft days',
  };
}

/// A date the way it appears next to the countdown: `12 Aug`, or `12 Aug 2027`
/// when it isn't the year we're in (an exam eight months out is common enough
/// that dropping the year would be genuinely ambiguous).
String formatExamDate(DateTime d, DateTime today) {
  const months = [
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
  final base = '${d.day} ${months[d.month - 1]}';
  return d.year == today.year ? base : '$base ${d.year}';
}
