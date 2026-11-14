import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fray/src/data.dart';
import 'package:fray/src/time_context.dart';

void main() {
  final clock = TimeContext('Europe/Ljubljana');
  test('local winter and summer times use their actual offsets', () {
    expect(
      clock.resolve(DateTime(2026, 1, 14), const TimeOfDay(hour: 9, minute: 0)),
      DateTime.utc(2026, 1, 14, 8),
    );
    expect(
      clock.resolve(DateTime(2026, 7, 14), const TimeOfDay(hour: 9, minute: 0)),
      DateTime.utc(2026, 7, 14, 7),
    );
  });
  test('spring gap is rejected instead of moved to another hour', () {
    expect(
      clock.candidates(
        DateTime(2026, 3, 29),
        const TimeOfDay(hour: 2, minute: 30),
      ),
      isEmpty,
    );
    expect(
      () => clock.resolve(
        DateTime(2026, 3, 29),
        const TimeOfDay(hour: 2, minute: 30),
      ),
      throwsFormatException,
    );
  });
  test('autumn repeat requires a choice and preserves an existing instant', () {
    final day = DateTime(2026, 10, 25);
    const time = TimeOfDay(hour: 2, minute: 30);
    final candidates = clock.candidates(day, time);
    expect(candidates, [
      DateTime.utc(2026, 10, 25, 0, 30),
      DateTime.utc(2026, 10, 25, 1, 30),
    ]);
    expect(() => clock.resolve(day, time), throwsFormatException);
    expect(
      clock.resolve(day, time, occurrence: candidates.last),
      candidates.last,
    );
  });
  test('overnight spring interval measures elapsed time', () {
    final start = clock.resolve(
      DateTime(2026, 3, 28),
      const TimeOfDay(hour: 23, minute: 30),
    );
    final end = clock.resolve(
      DateTime(2026, 3, 29),
      const TimeOfDay(hour: 3, minute: 30),
    );
    expect(end.difference(start).inMinutes, 180);
  });
  test('wire dates stay ISO and a date-only record has no timestamps', () {
    expect(dayKey(DateTime(2026, 11, 14)), '2026-11-14');
    final entry = TimeRecord({
      'id': '1',
      'item_id': '1',
      'date': '2026-11-14',
      'timezone': 'Europe/Ljubljana',
      'mode': 'duration',
      'minutes': 75,
    });
    expect(entry.toJson()['start'], isNull);
    expect(entry.toJson()['end'], isNull);
    expect(entry.toJson()['date'], '2026-11-14');
  });
}
