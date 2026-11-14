import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fray/src/session_cookies.dart';

void main() {
  test(
    'sessions survive restart, are origin bound, and respect expiry and logout',
    () async {
      final storage = <String, String>{};
      var now = DateTime.utc(2026, 11, 14);
      SessionCookies create() => SessionCookies(
        read: (key) async => storage[key],
        write: (key, value) async {
          storage[key] = value;
        },
        now: () => now,
      );
      final origin = Uri.parse('https://frayapi.klanija.com/api/items');
      final jar = create();
      await jar.receive(origin, [
        Cookie('sessionid', 'test-session')
          ..secure = true
          ..path = '/'
          ..maxAge = 28800,
      ]);
      expect((await create().forRequest(origin)).single.value, 'test-session');
      expect(
        await jar.forRequest(Uri.parse('https://different.example/api/items')),
        isEmpty,
      );
      expect(
        await jar.forRequest(Uri.parse('http://frayapi.klanija.com/api/items')),
        isEmpty,
      );
      now = now.add(const Duration(hours: 9));
      expect(await create().forRequest(origin), isEmpty);
      await jar.receive(origin, [Cookie('sessionid', '')..maxAge = 0]);
      expect(await create().forRequest(origin), isEmpty);
    },
  );
  test('only app cookies persist and path boundaries are enforced', () async {
    final storage = <String, String>{};
    final jar = SessionCookies(
      read: (key) async => storage[key],
      write: (key, value) async {
        storage[key] = value;
      },
    );
    final origin = Uri.parse('https://example.org/api/items');
    await jar.receive(origin, [
      Cookie('sessionid', 's')
        ..path = '/api'
        ..maxAge = 60,
      Cookie('tracking', 'do-not-store')..maxAge = 60,
    ]);
    expect((await jar.forRequest(origin)).map((c) => c.name), ['sessionid']);
    expect(
      await jar.forRequest(Uri.parse('https://example.org/api-else')),
      isEmpty,
    );
    expect(storage.values.single, isNot(contains('do-not-store')));
  });
}
