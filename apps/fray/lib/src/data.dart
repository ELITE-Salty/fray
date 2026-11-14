import 'dart:convert';
import 'dart:async';

import 'package:uuid/uuid.dart';

import 'workspace_storage.dart';

import '../l10n/localization.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'time_context.dart';

import 'client.dart';
import 'app_config.dart';

String monthKey(DateTime day) =>
    '${day.year.toString().padLeft(4, '0')}-${day.month.toString().padLeft(2, '0')}';
String dayKey(DateTime day) =>
    '${monthKey(day)}-${day.day.toString().padLeft(2, '0')}';

class WorkItem {
  final String id, name, kind, description, hex;
  final bool pinned, archived, canLog;
  final String role;
  final int memberCount;
  WorkItem(Map<String, dynamic> data)
    : id = data['id'],
      name = data['name'],
      kind = data['kind'],
      description = data['description'] ?? '',
      hex = data['color'] ?? '#7153E8',
      pinned = data['pinned'] ?? false,
      archived = data['archived'] ?? false,
      canLog = data['canLog'] ?? !(data['archived'] ?? false),
      role = data['role'] ?? 'owner',
      memberCount = data['memberCount'] ?? 0;
  Color get color => Color(int.parse('FF${hex.substring(1)}', radix: 16));
  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'kind': kind,
    'description': description,
    'color': hex,
    'pinned': pinned,
    'archived': archived,
    'role': role,
    'canLog': canLog,
    'memberCount': memberCount,
  };
}

class TimeRecord {
  final String id, itemId, date, mode, notes, timezone;
  final DateTime? start, end;
  final int minutes, revision;
  TimeRecord(Map<String, dynamic> data)
    : id = data['id'],
      itemId = data['item_id'],
      date = data['date'],
      mode = data['mode'],
      notes = data['notes'] ?? '',
      timezone = data['timezone'] ?? 'UTC',
      minutes = data['minutes'],
      revision = data['revision'] ?? 1,
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
    'revision': revision,
    'start': start?.toIso8601String(),
    'end': end?.toIso8601String(),
  };
  String timeLabel(BuildContext context) {
    if (mode == 'duration') return context.tr('Unscheduled time');
    final clock = TimeContext(timezone);
    return '${clockLabel(context, clock.local(start!))} – ${clockLabel(context, clock.local(end!))} · $timezone';
  }
}

class ApiException implements Exception {
  final String message;
  final int status, retryAfter;
  final String? code;
  ApiException(this.message, {this.status = 0, this.retryAfter = 0, this.code});
  @override
  String toString() => message;
}

class FrayStore extends ChangeNotifier {
  TimeContext clock;
  FrayStore({TimeContext? clock, http.Client? client, this.storage})
    : clock = clock ?? TimeContext.device,
      _client = client ?? createClient();
  final http.Client _client;
  final WorkspaceStorage? storage;
  String? account;
  bool offline = false, syncing = false, needsLogin = false;
  String? syncError;
  List<Map<String, dynamic>> queue = [], templates = [];
  List<String> cachedMonths = [];
  Map<String, dynamic>? runningTimer;
  int weeklyGoalMinutes = 0;
  Future<void> _cacheReady = Future.value(), _writes = Future.value();
  bool _disposed = false;
  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  Map<String, dynamic> checkpoint() => jsonDecode(
    jsonEncode({
      'items': items.map((i) => i.toJson()).toList(),
      'entries': entries.map((e) => e.toJson()).toList(),
      'queue': queue,
      'templates': templates,
      'timer': runningTimer,
      'weeklyGoalMinutes': weeklyGoalMinutes,
      'months': cachedMonths,
    }),
  );

  Future<void> commitLocal(Map<String, dynamic> before) async {
    try {
      await persist();
    } catch (_) {
      applyCache(before);
      notifyListeners();
      throw ApiException(
        'Could not save on this device. Free some storage and try again.',
        status: 507,
      );
    }
  }

  Future<void> persist() {
    if (demo || storage == null || account == null) return Future.value();
    final snapshot = jsonEncode({
      'account': account,
      'name': name,
      'email': email,
      'items': items.map((i) => i.toJson()).toList(),
      'entries': entries.map((e) => e.toJson()).toList(),
      'queue': queue,
      'templates': templates,
      'timer': runningTimer,
      'weeklyGoalMinutes': weeklyGoalMinutes,
      'months': cachedMonths,
    });
    return _writes = _writes
        .catchError((Object _) {})
        .then((_) => storage!.write(snapshot));
  }

  Future<Map<String, dynamic>?> readCache() async {
    if (storage == null) return null;
    final raw = await storage!.read();
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw));
    } catch (_) {
      return null;
    }
  }

  void applyCache(Map<String, dynamic> cache) {
    items = (cache['items'] as List? ?? [])
        .map((j) => WorkItem(Map<String, dynamic>.from(j)))
        .toList();
    entries = (cache['entries'] as List? ?? [])
        .map((j) => TimeRecord(Map<String, dynamic>.from(j)))
        .toList();
    queue = (cache['queue'] as List? ?? [])
        .map((j) => Map<String, dynamic>.from(j))
        .toList();
    templates = (cache['templates'] as List? ?? [])
        .map((j) => Map<String, dynamic>.from(j))
        .toList();
    runningTimer = cache['timer'] == null
        ? null
        : Map<String, dynamic>.from(cache['timer']);
    weeklyGoalMinutes = cache['weeklyGoalMinutes'] ?? 0;
    cachedMonths = List<String>.from(cache['months'] ?? []);
  }

  Future<void> activate(Map<String, dynamic> user) async {
    final next = user['id']?.toString() ?? user['email'];
    final cache = await readCache();
    if (cache != null &&
        cache['account'] != next &&
        ((cache['queue'] as List? ?? []).isNotEmpty ||
            cache['timer'] != null)) {
      throw ApiException(
        'Sign in to the original account to sync these entries.',
        status: 401,
      );
    }
    account = next;
    needsLogin = false;
    name = user['name'];
    email = user['email'];
    demo = false;
    offline = false;
    if (cache?['account'] == account) {
      applyCache(cache!);
    } else {
      items = [];
      entries = [];
      queue = [];
      templates = [];
      cachedMonths = [];
      runningTimer = null;
      weeklyGoalMinutes = 0;
    }
    await persist();
  }

  Future<dynamic> api(
    String method,
    String path, [
    Map<String, dynamic>? body,
  ]) => _request(method, path, body);

  String _csrf = '';
  String language = 'en';
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
      'Accept-Language': language,
    });
    if (body != null) request.body = jsonEncode(body);
    late http.Response response;
    try {
      response = await _client
          .send(request)
          .then(http.Response.fromStream)
          .timeout(const Duration(seconds: 20));
    } on TimeoutException {
      throw ApiException(
        'Could not connect. Check your connection and try again.',
      );
    } on http.ClientException {
      throw ApiException(
        'Could not connect. Check your connection and try again.',
      );
    }
    if (response.statusCode >= 400) {
      String message = translate(
        language,
        'Request failed ({status}). Please try again.',
        {'status': response.statusCode},
      );
      Map<String, dynamic> details = {};
      try {
        details = Map<String, dynamic>.from(jsonDecode(response.body));
        message = details['error'] ?? message;
      } catch (_) {}
      throw ApiException(
        message,
        status: response.statusCode,
        code: details['code'],
        retryAfter: details['retryAfter'] is num
            ? (details['retryAfter'] as num).toInt()
            : int.tryParse(response.headers['retry-after'] ?? '') ?? 0,
      );
    }
    if (response.headers['content-type']?.contains('text/csv') ?? false) {
      return response.body;
    }
    try {
      final result = jsonDecode(response.body);
      if (result is Map && result['csrfToken'] is String) {
        _csrf = result['csrfToken'];
      }
      return result;
    } catch (_) {
      throw ApiException(
        'The API is unavailable. Start the backend or try the demo.',
      );
    }
  }

  Future<void> restore() async {
    try {
      await prepareAuth();
      final user = Map<String, dynamic>.from(
        await _request('GET', '/api/auth/me'),
      );
      await activate(user);
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 0 || e.status >= 500) {
        final cache = await readCache();
        if (cache != null) {
          account = cache['account'];
          name = cache['name'];
          email = cache['email'];
          applyCache(cache);
          offline = true;
          notifyListeners();
        }
      }
      // Authentication failures never unlock a cached account.
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
    await activate(Map<String, dynamic>.from(result));
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

  Future<void> completeAuth(Map<String, dynamic> result) async {
    _cacheReady = activate(result);
    await _cacheReady;
    notifyListeners();
  }

  Future<void> signOut() async {
    if (queue.isNotEmpty || runningTimer != null) {
      throw ApiException(
        'Sync or discard pending entries and stop the timer before signing out.',
      );
    }
    if (!demo) await _request('POST', '/api/auth/logout');
    await forgetWorkspace();
  }

  Future<void> forgetWorkspace() async {
    _loadVersion++;
    await _writes.catchError((Object _) {});
    await storage?.clear();
    account = name = email = null;
    items = [];
    entries = [];
    queue = [];
    templates = [];
    cachedMonths = [];
    runningTimer = null;
    weeklyGoalMinutes = 0;
    offline = false;
    demo = false;
    syncError = null;
    needsLogin = false;
    _authPreparation = null;
    notifyListeners();
  }

  void startDemo() {
    demo = true;
    name = 'Alex';
    email = 'Demo workspace';
    account = null;
    queue = [];
    templates = [];
    runningTimer = null;
    weeklyGoalMinutes = 0;
    offline = false;
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
    await _cacheReady;
    final version = ++_loadVersion;
    try {
      await sync();
      if (needsLogin) throw ApiException(syncError!, status: 401);
      final from = DateTime(
        month.year,
        month.month,
        1,
      ).subtract(const Duration(days: 7));
      final to = DateTime(
        month.year,
        month.month + 1,
        1,
      ).add(const Duration(days: 7));
      final result = await Future.wait([
        _request('GET', '/api/items'),
        _request('GET', '/api/entries?from=${dayKey(from)}&to=${dayKey(to)}'),
        _request('GET', '/api/templates'),
        _request('GET', '/api/preferences'),
      ]);
      if (version != _loadVersion) return;
      final freshItems = (result[0]['items'] as List)
          .map((j) => WorkItem(j))
          .toList();
      final ids = freshItems.map((i) => i.id).toSet();
      // Keep labels for cached history and unsynced work after membership changes.
      items = [
        ...freshItems,
        ...items
            .where((i) => !ids.contains(i.id))
            .map(
              (i) =>
                  WorkItem({...i.toJson(), 'canLog': false, 'role': 'history'}),
            ),
      ];
      final pendingIds = queue.map((q) => q['localId']).toSet();
      entries.removeWhere(
        (e) =>
            !pendingIds.contains(e.id) &&
            e.date.compareTo(dayKey(from)) >= 0 &&
            e.date.compareTo(dayKey(to)) < 0,
      );
      final deletedIds = queue
          .where((q) => q['method'] == 'DELETE')
          .map((q) => q['localId'])
          .toSet();
      entries.addAll(
        (result[1]['entries'] as List)
            .map((j) => TimeRecord(j))
            .where(
              (e) => !pendingIds.contains(e.id) && !deletedIds.contains(e.id),
            ),
      );
      templates = (result[2]['templates'] as List)
          .map((j) => Map<String, dynamic>.from(j))
          .toList();
      weeklyGoalMinutes = result[3]['weeklyGoalMinutes'] ?? 0;
      cachedMonths.remove(monthKey(month));
      cachedMonths.add(monthKey(month));
      while (cachedMonths.length > 12) {
        final removed = cachedMonths.removeAt(0);
        entries.removeWhere(
          (e) => e.date.startsWith(removed) && !pendingIds.contains(e.id),
        );
      }
      offline = false;
      await persist();
      notifyListeners();
    } on ApiException catch (e) {
      if (e.status == 0 || e.status >= 500) {
        offline = true;
        notifyListeners();
        if (items.isNotEmpty) return;
      }
      rethrow;
    }
  }

  Future<void> sync() async {
    if (demo || syncing) return;
    syncing = true;
    syncError = null;
    needsLogin = false;
    notifyListeners();
    try {
      // Revalidate the session before replaying a queue, including after an offline restart.
      final me = await _request('GET', '/api/auth/me');
      if ((me['id']?.toString() ?? me['email']) != account) {
        throw ApiException(
          'Sign in to the original account to sync these entries.',
          status: 401,
        );
      }
      await prepareAuth();
      while (queue.isNotEmpty) {
        final op = queue.first;
        try {
          final result = await _request(
            op['method'],
            op['path'],
            Map<String, dynamic>.from(op['body']),
          );
          final before = checkpoint();
          entries.removeWhere(
            (e) => e.id == op['localId'] || e.id == result['id'],
          );
          if (op['method'] != 'DELETE') entries.add(TimeRecord(result));
          queue.removeAt(0);
          offline = false;
          await commitLocal(before);
        } on ApiException catch (e) {
          if (e.status == 404 && op['method'] == 'DELETE') {
            final before = checkpoint();
            queue.removeAt(0);
            await commitLocal(before);
            continue;
          }
          if (e.status == 507) {
            syncError = e.message;
            break;
          }
          needsLogin =
              e.status == 401 ||
              e.status == 403 && e.code == 'authentication_required';
          offline = e.status == 0 || e.status >= 500 && e.status != 507;
          op['error'] = e.message;
          syncError = e.message;
          await persist();
          break;
        }
      }
    } on ApiException catch (e) {
      needsLogin = e.status == 401;
      offline = e.status == 0 || e.status >= 500 && e.status != 507;
      syncError = e.message;
    } finally {
      syncing = false;
      notifyListeners();
    }
  }

  bool isPending(String id) => queue.any((q) => q['localId'] == id);

  Future<void> discardPending(String id) async {
    if (syncing) return;
    final before = checkpoint();
    final op = queue.firstWhere((q) => q['localId'] == id);
    queue.remove(op);
    entries.removeWhere((e) => e.id == id);
    if (op['before'] != null) {
      entries.add(TimeRecord(Map<String, dynamic>.from(op['before'])));
    }
    await commitLocal(before);
    notifyListeners();
  }

  Future<void> startTimer(String itemId) async {
    if (runningTimer != null) {
      throw ApiException('A timer is already running on this device.');
    }
    final before = checkpoint();
    runningTimer = {
      'item_id': itemId,
      'start': clock.now().toUtc().toIso8601String(),
      'timezone': clock.zone,
    };
    await commitLocal(before);
    notifyListeners();
  }

  Future<void> clearTimer() async {
    final before = checkpoint();
    runningTimer = null;
    await commitLocal(before);
    notifyListeners();
  }

  Future<void> saveGoal(int minutes) async {
    if (!demo) {
      await _request('PATCH', '/api/preferences', {
        'weeklyGoalMinutes': minutes,
      });
    }
    weeklyGoalMinutes = minutes;
    await persist();
    notifyListeners();
  }

  Future<void> addTemplate(String name, TimeRecord entry) async {
    final body = {
      'name': name,
      'item_id': entry.itemId,
      'minutes': entry.minutes,
      'notes': entry.notes,
    };
    final result = demo
        ? {...body, 'id': const Uuid().v4()}
        : await _request('POST', '/api/templates', body);
    templates.add(Map<String, dynamic>.from(result));
    await persist();
    notifyListeners();
  }

  Future<void> deleteTemplate(String id) async {
    if (!demo) await _request('DELETE', '/api/templates/$id');
    templates.removeWhere((t) => t['id'] == id);
    await persist();
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
    await persist();
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
    if (demo || storage == null) {
      final result = demo
          ? {...data, 'id': id ?? '${_sequence++}'}
          : await _request(
              id == null ? 'POST' : 'PATCH',
              '/api/entries${id == null ? '' : '/$id'}',
              data,
            );
      entries.removeWhere((e) => e.id == result['id']);
      entries.add(TimeRecord(result));
      notifyListeners();
      return;
    }
    if (syncing) throw ApiException('Please wait for syncing to finish.');
    final checkpointBefore = checkpoint();
    final existing = queue.where((q) => q['localId'] == id).firstOrNull;
    final before = entries.where((e) => e.id == id).firstOrNull?.toJson();
    final operation = const Uuid().v4();
    final localId = id ?? 'local-$operation';
    final body = {...data};
    if (existing != null) {
      // Keep the operation identity: a changed ambiguous POST becomes an explicit conflict.
      if (existing['method'] == 'POST') {
        body['operation'] = existing['body']['operation'];
      }
      existing['body'] = body;
      existing.remove('error');
    } else {
      if (id == null) body['operation'] = operation;
      queue.add({
        'localId': localId,
        'method': id == null ? 'POST' : 'PATCH',
        'path': '/api/entries${id == null ? '' : '/$id'}',
        'body': body,
        'before': before,
      });
    }
    entries.removeWhere((e) => e.id == localId);
    entries.add(TimeRecord({...data, 'id': localId}));
    await commitLocal(checkpointBefore);
    notifyListeners();
    await sync();
  }

  Future<void> deleteEntry(String id) async {
    if (isPending(id)) {
      throw ApiException(
        'Review or discard this pending change before deleting the entry.',
      );
    }
    if (demo || storage == null) {
      if (!demo) await _request('DELETE', '/api/entries/$id');
      entries.removeWhere((e) => e.id == id);
      notifyListeners();
      return;
    }
    if (syncing) throw ApiException('Please wait for syncing to finish.');
    final checkpointBefore = checkpoint();
    final before = entries.firstWhere((e) => e.id == id);
    queue.add({
      'localId': id,
      'method': 'DELETE',
      'path': '/api/entries/$id',
      'body': {'revision': before.revision},
      'before': before.toJson(),
    });
    entries.removeWhere((e) => e.id == id);
    await commitLocal(checkpointBefore);
    notifyListeners();
    await sync();
  }

  Future<String> csv(DateTime month) async {
    if (!demo && !offline && queue.isEmpty) {
      return await _request(
        'GET',
        '/api/reports/monthly?month=${monthKey(month)}&format=csv',
      );
    }
    final rows = [
      [
        'Project / activity',
        'Type',
        'Minutes',
      ].map((key) => translate(language, key)).join(','),
    ];
    for (final work in items) {
      final minutes = inMonth(month)
          .where((e) => e.itemId == work.id)
          .fold(0, (sum, e) => sum + e.minutes);
      if (minutes == 0) continue;
      var safe = work.name.replaceAll('"', '""');
      if (RegExp(r'^\s*[=+@\-]').hasMatch(safe)) safe = "'$safe";
      rows.add('"$safe",${translate(language, work.kind)},$minutes');
    }
    return '\ufeff${rows.join('\r\n')}';
  }

  @override
  void dispose() {
    _disposed = true;
    _client.close();
    super.dispose();
  }
}
