import 'package:flutter/material.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as database;
import 'package:timezone/timezone.dart' as tz;

/// Device timezone for new entries. Existing entries keep their original zone/date.
class TimeContext {
  static bool _initialized = false;
  static TimeContext device = TimeContext('UTC', detected: false);
  final String zone;
  final bool detected;

  TimeContext(this.zone, {this.detected = true}) {
    if (!_initialized) {
      database.initializeTimeZones();
      _initialized = true;
    }
    tz.getLocation(zone); // Fail clearly for unsupported stored zones.
  }

  static Future<TimeContext> detect() async {
    try {
      final info = await FlutterTimezone.getLocalTimezone();
      return TimeContext(info.identifier);
    } catch (_) {
      return TimeContext('UTC', detected: false);
    }
  }

  tz.Location get location => tz.getLocation(zone);
  tz.TZDateTime local(DateTime instant) =>
      tz.TZDateTime.from(instant, location);
  tz.TZDateTime now() => local(DateTime.now());

  /// A wall-clock time can map to zero, one, or two instants across DST changes.
  /// Round-tripping every distinct offset avoids silently moving a missing time
  /// forward or selecting one of two repeated times without the user's choice.
  List<DateTime> candidates(DateTime day, TimeOfDay time) {
    final wall = DateTime.utc(
      day.year,
      day.month,
      day.day,
      time.hour,
      time.minute,
    );
    final result = <DateTime>[];
    for (final offset in location.zones.map((z) => z.offset).toSet()) {
      final instant = wall.subtract(offset);
      final value = local(instant);
      if (value.year == day.year &&
          value.month == day.month &&
          value.day == day.day &&
          value.hour == time.hour &&
          value.minute == time.minute &&
          value.second == 0) {
        result.add(instant);
      }
    }
    return result..sort();
  }

  DateTime resolve(DateTime day, TimeOfDay time, {DateTime? occurrence}) {
    final options = candidates(day, time);
    if (options.isEmpty) {
      throw const FormatException(
        'That time does not exist because the clocks move forward. Choose another time.',
      );
    }
    if (options.length == 1) return options.single;
    for (final option in options) {
      if (occurrence?.isAtSameMomentAs(option) ?? false) return option;
    }
    throw const FormatException(
      'That time occurs twice because the clocks move back. Choose an occurrence below.',
    );
  }

  String offsetLabel(DateTime instant) {
    final minutes = local(instant).timeZoneOffset.inMinutes;
    final absolute = minutes.abs();
    return 'UTC${minutes < 0 ? '-' : '+'}${(absolute ~/ 60).toString().padLeft(2, '0')}:${(absolute % 60).toString().padLeft(2, '0')}';
  }
}

String clockLabel(BuildContext context, DateTime value) =>
    MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(value),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
