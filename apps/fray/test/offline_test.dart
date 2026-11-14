import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:fray/src/data.dart';
import 'package:fray/src/workspace_storage.dart';

class MemoryWorkspace implements WorkspaceStorage {
  String? value;
  bool fail = false;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String data) async {
    if (fail) throw StateError('disk full');
    value = data;
  }

  @override
  Future<void> clear() async => value = null;
}

const user = {'id': '1', 'name': 'Test', 'email': 'test@example.test'};
const entry = {
  'item_id': 'project',
  'date': '2026-11-14',
  'timezone': 'UTC',
  'mode': 'duration',
  'minutes': 60,
  'notes': 'Private',
};
http.Response json(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json'},
);
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late MemoryWorkspace disk;
  late bool connected, wrongAccount, conflict, lostResponse;
  late List<Map<String, dynamic>> posts;
  late List<String> reads;
  http.Client client() => MockClient((request) async {
    reads.add(request.url.path);
    if (!connected) throw http.ClientException('offline');
    if (request.url.path == '/api/auth/csrf') {
      return json({'csrfToken': 'test'});
    }
    if (request.url.path == '/api/auth/me') {
      return json({...user, if (wrongAccount) 'id': '2'});
    }
    if (request.url.path == '/api/items') return json({'items': []});
    if (request.url.path == '/api/templates') return json({'templates': []});
    if (request.url.path == '/api/preferences') {
      return json({'weeklyGoalMinutes': 0});
    }
    if (request.method == 'GET') return json({'entries': []});
    final body = Map<String, dynamic>.from(jsonDecode(request.body));
    posts.add(body);
    if (conflict) {
      return json({
        'error':
            'This entry changed on another device. Reload it before saving.',
        'code': 'sync_conflict',
      }, 409);
    }
    if (lostResponse) {
      lostResponse = false;
      throw http.ClientException('response lost');
    }
    return json({...body, 'id': 'server-entry', 'revision': 1}, 201);
  });
  Future<FrayStore> fresh() async {
    final store = FrayStore(storage: disk, client: client());
    await store.activate(user);
    store.items = [
      WorkItem({'id': 'project', 'name': 'Project', 'kind': 'project'}),
    ];
    await store.persist();
    addTearDown(store.dispose);
    return store;
  }

  setUp(() {
    disk = MemoryWorkspace();
    connected = true;
    wrongAccount = conflict = lostResponse = false;
    posts = [];
    reads = [];
  });

  test('Offline entry and running timer survive restart and reconnect exactly once', () async {
    final first = await fresh();
    connected = false;
    await first.startTimer('project');
    await first.saveEntry(entry);
    expect(first.queue, hasLength(1));
    expect(first.entries.single.notes, 'Private');
    final restarted = FrayStore(storage: disk, client: client());
    addTearDown(restarted.dispose);
    await restarted.restore();
    expect(restarted.offline, isTrue);
    expect(restarted.runningTimer, isNotNull);
    expect(restarted.queue, hasLength(1));
    connected = true;
    await restarted.sync();
    await restarted.sync();
    expect(posts, hasLength(1));
    expect(restarted.queue, isEmpty);
    expect(restarted.entries.single.id, 'server-entry');
    final saved = jsonDecode(disk.value!);
    expect(saved['queue'], isEmpty);
    expect(saved['entries'].single['id'], 'server-entry');
  });
  test('Lost response retries the same operation UUID', () async {
    final store = await fresh();
    lostResponse = true;
    await store.saveEntry(entry);
    expect(store.queue, hasLength(1));
    await store.sync();
    expect(posts, hasLength(2));
    expect(posts[0]['operation'], posts[1]['operation']);
    expect(store.entries, hasLength(1));
  });
  test(
    'Another account cannot receive queued changes or replace cached history',
    () async {
      final store = await fresh();
      connected = false;
      await store.saveEntry(entry);
      connected = true;
      wrongAccount = true;
      reads.clear();
      await expectLater(
        store.load(DateTime(2026, 11)),
        throwsA(isA<ApiException>()),
      );
      expect(store.needsLogin, isTrue);
      expect(posts, isEmpty);
      expect(reads, isNot(contains('/api/items')));
      expect(store.entries.single.notes, 'Private');
      await expectLater(
        store.activate({...user, 'id': '2'}),
        throwsA(isA<ApiException>()),
      );
      expect(store.account, '1');
      expect(store.queue, hasLength(1));
    },
  );
  test(
    'Failed local write rolls back optimistic changes and never sends them',
    () async {
      final store = await fresh();
      disk.fail = true;
      await expectLater(store.saveEntry(entry), throwsA(isA<ApiException>()));
      expect(store.queue, isEmpty);
      expect(store.entries, isEmpty);
      expect(posts, isEmpty);
      await expectLater(
        store.startTimer('project'),
        throwsA(isA<ApiException>()),
      );
      expect(store.runningTimer, isNull);
      disk.fail = false;
      await store.saveEntry(entry);
      expect(posts, hasLength(1));
    },
  );
  test(
    'Conflicting patch preserves local work until explicit discard',
    () async {
      final store = await fresh();
      store.entries = [
        TimeRecord({...entry, 'id': 'existing', 'revision': 3}),
      ];
      conflict = true;
      await store.saveEntry({
        ...entry,
        'notes': 'Edited',
        'revision': 3,
      }, 'existing');
      expect(store.queue.single['error'], isNotNull);
      expect(store.entries.single.notes, 'Edited');
      await store.discardPending('existing');
      expect(store.queue, isEmpty);
      expect(store.entries.single.notes, 'Private');
      expect(store.entries.single.revision, 3);
    },
  );
  test('Removed membership retains labels for pending entries; logout protects unsynced work', () async {
    final store = await fresh();
    connected = false;
    await store.saveEntry(entry);
    connected = true;
    conflict = true;
    await store.load(DateTime(2026, 11));
    expect(store.item('project').name, 'Project');
    expect(store.item('project').canLog, isFalse);
    await expectLater(store.signOut(), throwsA(isA<ApiException>()));
    expect(store.queue, hasLength(1));
  });
}
