import 'package:flutter_test/flutter_test.dart';

import 'package:openote/study/study_stats.dart';

void main() {
  group('day keys', () {
    test('are zero-padded and sort lexicographically', () {
      expect(dayKey(DateTime(2026, 8, 4)), '2026-08-04');
      expect(dayKey(DateTime(2026, 12, 25)), '2026-12-25');
      final keys = [
        dayKey(DateTime(2026, 9, 1)),
        dayKey(DateTime(2026, 8, 31)),
        dayKey(DateTime(2026, 10, 1)),
      ]..sort();
      expect(keys, ['2026-08-31', '2026-09-01', '2026-10-01']);
    });

    test('round-trip, and reject what is not a day', () {
      expect(parseDayKey('2026-08-04'), DateTime(2026, 8, 4));
      expect(parseDayKey('2026-8-4'), isNull, reason: 'unpadded');
      expect(parseDayKey('not a date'), isNull);
      expect(parseDayKey('2026-13-01'), isNull, reason: 'no thirteenth month');
      // Dart would happily roll this into March; a settings blob containing it
      // is corrupt, and silently accepting it invents a day that never was.
      expect(parseDayKey('2026-02-31'), isNull);
    });
  });

  group('daysBetween', () {
    test('counts calendar days, not elapsed hours', () {
      expect(daysBetween(DateTime(2026, 8, 4), DateTime(2026, 8, 4)), 0);
      expect(daysBetween(DateTime(2026, 8, 4), DateTime(2026, 8, 5)), 1);
      expect(
          daysBetween(DateTime(2026, 8, 4, 23, 59), DateTime(2026, 8, 5, 0, 1)),
          1,
          reason: 'two minutes apart, but a day apart');
      expect(daysBetween(DateTime(2026, 8, 5), DateTime(2026, 8, 4)), -1);
    });

    test('crosses a month and a year boundary', () {
      expect(daysBetween(DateTime(2026, 8, 31), DateTime(2026, 9, 1)), 1);
      expect(daysBetween(DateTime(2026, 12, 31), DateTime(2027, 1, 1)), 1);
      expect(daysBetween(DateTime(2028, 2, 28), DateTime(2028, 3, 1)), 2,
          reason: '2028 is a leap year');
    });

    // The bug this rules out: `to.difference(from).inDays` on local times
    // truncates a 23-hour spring-forward day to 0, so an exam "tomorrow" reads
    // as "today" for everyone in a DST timezone on exactly one day a year.
    test('survives a daylight-saving transition', () {
      for (final d in [
        DateTime(2026, 3, 8), // US spring forward
        DateTime(2026, 4, 5), // AU autumn back
        DateTime(2026, 10, 4), // AU spring forward
        DateTime(2026, 10, 25), // EU autumn back
      ]) {
        expect(daysBetween(d, DateTime(d.year, d.month, d.day + 1)), 1,
            reason: 'the day after $d is one day away');
      }
    });
  });

  group('wording', () {
    test('counts down the way a student would say it', () {
      expect(formatCountdown(0), 'today');
      expect(formatCountdown(1), 'tomorrow');
      expect(formatCountdown(14), '14 days');
      expect(formatCountdown(-1), 'yesterday');
      expect(formatCountdown(-3), '3 days ago');
      expect(formatCountdown(-90), 'passed');
    });

    test('shows the year only when it is not this one', () {
      final today = DateTime(2026, 8, 4);
      expect(formatExamDate(DateTime(2026, 8, 12), today), '12 Aug');
      expect(formatExamDate(DateTime(2027, 2, 3), today), '3 Feb 2027');
    });
  });
}
