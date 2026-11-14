import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'time_context.dart';

import 'client.dart';
import 'app_config.dart';

String monthKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}';
String dayKey(DateTime day) =>
    '${monthKey(day)}-${day.day.toString().padLeft(2, '0')}';
String durationLabel(int minutes) => '${minutes ~/ 60}h ${minutes % 60}m';

class WorkItem {
  final String id, name, kind, description, hex;
  final bool pinned, archived;
  WorkItem(Map<String, dynamic> data)
    : id = data['id'],
      name = data['name'],
      kind = data['kind'],
      description = data['description'] ?? '',
      hex = data['color'] ?? '#7153E8',
      pinned = data['pinned'] ?? false,
      archived = data['archived'] ?? false;
  Color get color => Color(int.parse('FF${hex.substring(1)}', radix: 16));
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'description': description,
    'color': hex,
    'pinned': pinned,
    'archived': archived,
  };
}

class TimeRecord {
  final String id, itemId, date, mode, notes, timezone;
  final DateTime? start, end;
  final int minutes;
  TimeRecord(Map<String, dynamic> data)
    : id = data['id'],
      itemId = data['item_id'],
      date = data['date'],
      mode = data['mode'],
      notes = data['notes'] ?? '',
      timezone = data['timezone'] ?? 'UTC',
      minutes = data['minutes'],
      start = data['start'] == null
          ? null
          : DateTime.parse(data['start']).toUtc(),
      end = data['end'] == null ? null : DateTime.parse(data['end']).toUtc();
  Map<String, dynamic> toJson() => {
    'id': id,
    'item_id': itemId,
    'date': date,
    'mode': mode,
    'notes': notes,
    'timezone': timezone,
    'minutes': minutes,
    'start': start?.toIso8601String(),
    'end': end?.toIso8601String(),
  };
  String timeLabel(BuildContext context) {
    if (mode == 'duration') return 'Unscheduled time';
    final clock = TimeContext(timezone);
    return '${clockLabel(context, clock.local(start!))} – ${clockLabel(context, clock.local(end!))} · $timezone';
  }
}

class ApiException implements Exception {
  final String message;
  ApiException(this.message);
  @override
  String toString() => message;
}

class FrayStore extends ChangeNotifier {
  TimeContext clock;
  FrayStore({TimeContext? clock, http.Client? client})
    : clock = clock ?? TimeContext.device,
      _client = client ?? createClient();
  final http.Client _client;
  String _csrf = '';
  Future<void>? _authPreparation;
  bool demo = false;
  String? name, email;
  List<WorkItem> items = [];
  List<TimeRecord> entries = [];
  int _sequence = 100;
  int _loadVersion = 0;

  Future<dynamic> _request(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) async {
    final request = http.Request(method, apiUri(path));
    request.headers.addAll({
      'Content-Type': 'application/json',
      'X-CSRFToken': _csrf,
    });
    if (body != null) request.body = jsonEncode(body);
    final response = await _client
        .send(request)
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 20));
    if (response.statusCode >= 400) {
      String message =
          'Request failed (${response.statusCode}). Please try again.';
      try {
        message = jsonDecode(response.body)['error'] ?? message;
      } catch (_) {}
      throw ApiException(message);
    }
    if (response.headers['content-type']?.contains('text/csv') ?? false) {
      return response.body;
    }
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw ApiException(
        'The API is unavailable. Start the backend or try the demo.',
      );
    }
  }

  Future<void> restore() async {
    try {
      await prepareAuth();
      final user = await _request('GET', '/api/auth/me');
      name = user['name'];
      email = user['email'];
      notifyListeners();
    } catch (_) {
      /* A missing or expired session opens the sign-in screen. */
    }
  }

  Future<void> signIn(String email, String password, String code) async {
    final csrf = await _request('GET', '/api/auth/csrf');
    _csrf = csrf['csrfToken'];
    final result = await _request('POST', '/api/auth/login', {
      'email': email,
      'password': password,
      'code': code,
    });
    _csrf = result['csrfToken'];
    name = result['name'];
    this.email = result['email'];
    demo = false;
    notifyListeners();
  }

  Future<void> prepareAuth() => _authPreparation ??= () async {
    try {
      final result = await _request('GET', '/api/auth/csrf');
      _csrf = result['csrfToken'];
    } catch (_) {
      _authPreparation = null;
      rethrow;
    }
  }();

  Future<Map<String, dynamic>> authStatus() async {
    await prepareAuth();
    return Map<String, dynamic>.from(
      await _request('GET', '/api/auth/challenge'),
    );
  }

  Future<Map<String, dynamic>> beginSignIn(
    String email,
    String password,
  ) async {
    await prepareAuth();
    return Map<String, dynamic>.from(
      await _request('POST', '/api/auth/login/start', {
        'email': email,
        'password': password,
      }),
    );
  }

  Future<Map<String, dynamic>> beginSignUp(
    String name,
    String email,
    String password,
  ) async {
    await prepareAuth();
    return Map<String, dynamic>.from(
      await _request('POST', '/api/auth/signup', {
        'name': name,
        'email': email,
        'password': password,
      }),
    );
  }

  Future<Map<String, dynamic>> verifyEmail(String code) async =>
      Map<String, dynamic>.from(
        await _request('POST', '/api/auth/signup/email', {'code': code}),
      );

  Future<void> resendEmail() async {
    await _request('POST', '/api/auth/signup/resend');
  }

  Future<void> cancelAuth() async {
    await _request('POST', '/api/auth/cancel');
  }

  Future<Map<String, dynamic>> verifySecurityCode(
    String code, {
    required bool enrolling,
  }) async {
    final result = Map<String, dynamic>.from(
      await _request(
        'POST',
        enrolling ? '/api/auth/signup/finish' : '/api/auth/login/verify',
        {'code': code},
      ),
    );
    _csrf = result['csrfToken'];
    return result;
  }

  void completeAuth(Map<String, dynamic> result) {
    name = result['name'];
    email = result['email'];
    demo = false;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (!demo) await _request('POST', '/api/auth/logout');
    _loadVersion++;
    name = null;
    email = null;
    items = [];
    entries = [];
    demo = false;
    notifyListeners();
  }

  void startDemo() {
    demo = true;
    name = 'Alex';
    email = 'Demo workspace';
    items = [
      WorkItem({
        'id': '1',
        'name': 'Website redesign',
        'kind': 'project',
        'color': '#7153E8',
        'pinned': true,
        'description': 'A fresh home for a good idea.',
      }),
      WorkItem({
        'id': '2',
        'name': 'Faculty project',
        'kind': 'project',
        'color': '#D88A40',
        'description': 'Build, learn, and document the journey.',
      }),
      WorkItem({
        'id': '3',
        'name': 'Office work',
        'kind': 'activity',
        'color': '#398E7A',
        'description': 'Keep the everyday things moving.',
      }),
      WorkItem({
        'id': '4',
        'name': 'Reading & research',
        'kind': 'activity',
        'color': '#538BC4',
      }),
    ];
    final now = clock.now();
    entries = [];
    for (int offset = 0; offset < 18; offset++) {
      final day = DateTime(now.year, now.month, now.day - offset);
      if (day.weekday > 5 && offset != 0) continue;
      for (int i = 0; i < 2; i++) {
        final start = clock.resolve(day, TimeOfDay(hour: 9 + i * 4, minute: 0));
        entries.add(
          TimeRecord({
            'id': '${_sequence++}',
            'item_id': items[(offset + i) % items.length].id,
            'date': dayKey(day),
            'timezone': clock.zone,
            'mode': i == 0 ? 'timed' : 'duration',
            'minutes': i == 0 ? 120 : 45 + offset % 3 * 15,
            'start': i == 0 ? start.toIso8601String() : null,
            'end': i == 0
                ? start.add(const Duration(hours: 2)).toIso8601String()
                : null,
            'notes': i == 0 ? 'Focused work, one thing at a time.' : '',
          }),
        );
      }
    }
    notifyListeners();
  }

  Future<void> load(DateTime month) async {
    if (demo) return;
    final version = ++_loadVersion;
    final result = await Future.wait([
      _request('GET', '/api/items'),
      _request('GET', '/api/entries?month=${monthKey(month)}'),
    ]);
    if (version != _loadVersion) return;
    items = (result[0]['items'] as List).map((j) => WorkItem(j)).toList();
    entries = (result[1]['entries'] as List).map((j) => TimeRecord(j)).toList();
    notifyListeners();
  }

  WorkItem item(String id) => items.firstWhere((item) => item.id == id);
  List<TimeRecord> inMonth(DateTime month) =>
      entries.where((e) => e.date.startsWith(monthKey(month))).toList();
  List<TimeRecord> onDay(DateTime day) =>
      entries.where((e) => e.date == dayKey(day)).toList()..sort((a, b) {
        if (a.start == null) return b.start == null ? 0 : 1;
        if (b.start == null) return -1;
        return a.start!.compareTo(b.start!);
      });

  Future<void> saveItem(Map<String, dynamic> data, [String? id]) async {
    final result = demo
        ? {...data, 'id': id ?? '${_sequence++}'}
        : await _request(
            id == null ? 'POST' : 'PATCH',
            '/api/items${id == null ? '' : '/$id'}',
            data,
          );
    items.removeWhere((item) => item.id == result['id']);
    items.add(WorkItem(result));
    notifyListeners();
  }

  Future<void> saveEntry(Map<String, dynamic> data, [String? id]) async {
    if (demo && data['mode'] == 'timed') {
      final start = DateTime.parse(data['start']);
      final end = DateTime.parse(data['end']);
      if (entries.any(
        (e) =>
            e.id != id &&
            e.start != null &&
            e.start!.isBefore(end) &&
            e.end!.isAfter(start),
      )) {
        throw ApiException('This interval overlaps another timed entry.');
      }
    }
    final result = demo
        ? {...data, 'id': id ?? '${_sequence++}'}
        : await _request(
            id == null ? 'POST' : 'PATCH',
            '/api/entries${id == null ? '' : '/$id'}',
            data,
          );
    entries.removeWhere((entry) => entry.id == result['id']);
    entries.add(TimeRecord(result));
    notifyListeners();
  }

  Future<void> deleteEntry(String id) async {
    if (!demo) await _request('DELETE', '/api/entries/$id');
    entries.removeWhere((e) => e.id == id);
    notifyListeners();
  }

  Future<String> csv(DateTime month) async {
    if (!demo) {
      return await _request(
        'GET',
        '/api/reports/monthly?month=${monthKey(month)}&format=csv',
      );
    }
    final rows = ['Project / activity,Type,Minutes'];
    for (final work in items) {
      final minutes = inMonth(month)
          .where((e) => e.itemId == work.id)
          .fold(0, (sum, e) => sum + e.minutes);
      if (minutes == 0) continue;
      var safe = work.name.replaceAll('"', '""');
      if (RegExp(r'^\s*[=+@\-]').hasMatch(safe)) safe = "'$safe";
      rows.add('"$safe",${work.kind},$minutes');
    }
    return '\ufeff${rows.join('\r\n')}';
  }

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }
}
