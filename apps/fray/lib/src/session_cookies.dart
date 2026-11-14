import 'dart:convert';
import 'dart:io';

/// An origin-bound cookie jar. Persistence is supplied by platform secure storage.
/// Only Django's session and CSRF cookies are retained, with their expiry dates.
class SessionCookies {
  final Future<String?> Function(String key) read;
  final Future<void> Function(String key, String value) write;
  final DateTime Function() now;
  final Map<String, Map<String, Map<String, dynamic>>> _jars = {};
  final Map<String, Future<void>> _loads = {};
  Future<void> _writes = Future.value();

  SessionCookies({
    required this.read,
    required this.write,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  String _key(String origin) =>
      'fray.cookies.${base64Url.encode(utf8.encode(origin))}';

  Future<void> _load(String origin) => _loads.putIfAbsent(origin, () async {
    final jar = <String, Map<String, dynamic>>{};
    final raw = await read(_key(origin));
    if (raw != null) {
      try {
        final data = jsonDecode(raw) as Map<String, dynamic>;
        for (final name in ['sessionid', 'csrftoken']) {
          if (data[name] is Map) {
            jar[name] = Map<String, dynamic>.from(data[name]);
          }
        }
      } on FormatException {
        /* A corrupt record is treated as signed out. */
      } on TypeError {
        /* A corrupt record is treated as signed out. */
      }
    }
    _jars[origin] = jar;
  });

  Future<List<Cookie>> forRequest(Uri uri) async {
    await _load(uri.origin);
    final jar = _jars[uri.origin]!;
    final result = <Cookie>[];
    for (final entry in jar.entries) {
      final value = entry.value;
      final expires = DateTime.tryParse(value['expires']?.toString() ?? '');
      if (expires == null ||
          !expires.isAfter(now()) ||
          value['value'] is! String) {
        continue;
      }
      if (value['secure'] != false && uri.scheme != 'https') continue;
      final path = value['path'] is String ? value['path'] as String : '/';
      if (uri.path != path &&
          !uri.path.startsWith(path.endsWith('/') ? path : '$path/')) {
        continue;
      }
      result.add(Cookie(entry.key, value['value'] as String));
    }
    return result;
  }

  Future<void> receive(Uri uri, List<Cookie> cookies) async {
    await _load(uri.origin);
    final jar = _jars[uri.origin]!;
    for (final cookie in cookies) {
      if (!['sessionid', 'csrftoken'].contains(cookie.name)) continue;
      final expires = cookie.maxAge != null
          ? now().add(Duration(seconds: cookie.maxAge!))
          : cookie.expires;
      if (cookie.value.isEmpty || expires == null || !expires.isAfter(now())) {
        jar.remove(cookie.name);
      } else {
        jar[cookie.name] = {
          'value': cookie.value,
          'expires': expires.toUtc().toIso8601String(),
          'secure': cookie.secure,
          'path': cookie.path ?? '/',
        };
      }
    }
    // Serialize writes so simultaneous API responses can't restore stale cookies.
    final save = _writes
        .catchError((Object _) {})
        .then((_) => write(_key(uri.origin), jsonEncode(jar)));
    _writes = save;
    await save;
  }
}
