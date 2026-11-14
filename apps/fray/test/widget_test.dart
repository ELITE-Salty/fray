import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fray/src/app.dart';
import 'package:fray/src/data.dart';
import 'package:fray/src/editors.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  for (final width in [390.0, 1440.0]) {
    testWidgets('Demo navigation and layout at $width', (tester) async {
      tester.view.physicalSize = Size(width, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FrayStore()..startDemo();
      addTearDown(store.dispose);
      await tester.pumpWidget(FrayApp(store: store));
      await tester.pumpAndSettle();
      expect(find.text('Your time, at a glance.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      for (final label in [
        'Entries',
        'Projects',
        'Reports',
        'Profile',
        'Calendar',
      ]) {
        await tester.tap(find.text(label).last);
        await tester.pumpAndSettle();
        expect(
          tester.takeException(),
          isNull,
          reason: '$label should fit at $width',
        );
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets('Duration editor persists notes and never invents timestamps', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1440, 1200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = FrayStore()..startDemo();
    addTearDown(store.dispose);
    final count = store.entries.length;
    await tester.pumpWidget(FrayApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextFormField, 'Hours'), '1');
    await tester.enterText(find.widgetWithText(TextFormField, 'Minutes'), '15');
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Notes (optional)'),
      'A useful study session',
    );
    await tester.tap(find.text('Save entry'));
    await tester.pumpAndSettle();
    expect(store.entries.length, count + 1);
    expect(store.entries.last.minutes, 75);
    expect(store.entries.last.notes, 'A useful study session');
    expect(store.entries.last.start, isNull);
    expect(store.entries.last.end, isNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
    'Existing duration splits into fields and blank hours save minutes only',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FrayStore()..startDemo();
      addTearDown(store.dispose);
      final original = TimeRecord({
        'id': 'duration-edit',
        'item_id': '1',
        'date': dayKey(store.clock.now()),
        'mode': 'duration',
        'minutes': 135,
      });
      store.entries.add(original);
      await tester.pumpWidget(FrayApp(store: store));
      await tester.pumpAndSettle();
      showDialog<void>(
        context: tester.element(find.byType(Workspace)),
        builder: (_) =>
            EntryEditor(store: store, day: store.clock.now(), entry: original),
      );
      await tester.pumpAndSettle();
      final hours = find.byKey(const ValueKey('entry-hours'));
      final minutes = find.byKey(const ValueKey('entry-minutes'));
      expect(tester.widget<TextFormField>(hours).controller!.text, '2');
      expect(tester.widget<TextFormField>(minutes).controller!.text, '15');
      await tester.enterText(hours, '');
      await tester.enterText(minutes, '45');
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      final saved = store.entries.singleWhere((e) => e.id == original.id);
      expect(saved.minutes, 45);
      expect(saved.start, isNull);
      expect(saved.end, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'Duration rejects invalid parts and totals while accepting exactly 24 hours',
    (tester) async {
      tester.view.physicalSize = const Size(390, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final store = FrayStore()..startDemo();
      addTearDown(store.dispose);
      final count = store.entries.length;
      await tester.pumpWidget(FrayApp(store: store));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add entry'));
      await tester.pumpAndSettle();
      final hours = find.byKey(const ValueKey('entry-hours'));
      final minutes = find.byKey(const ValueKey('entry-minutes'));
      for (final values in [
        ['0', '0'],
        ['24', '1'],
        ['25', '0'],
        ['1', '60'],
        ['-1', '30'],
        ['1.5', '0'],
      ]) {
        await tester.enterText(hours, values[0]);
        await tester.enterText(minutes, values[1]);
        await tester.tap(find.text('Save entry'));
        await tester.pumpAndSettle();
        expect(store.entries.length, count, reason: '$values must not save');
        expect(find.byType(EntryEditor), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
      await tester.enterText(hours, '24');
      await tester.enterText(minutes, '');
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      expect(store.entries.length, count + 1);
      expect(store.entries.last.minutes, 1440);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets('Sign in offers an explicitly labeled demo', (tester) async {
    final store = FrayStore(
      client: MockClient(
        (request) async => http.Response(
          request.url.path.endsWith('/csrf')
              ? '{"csrfToken":"test"}'
              : '{"stage":"credentials"}',
          200,
          headers: {'content-type': 'application/json'},
        ),
      ),
    );
    addTearDown(store.dispose);
    await tester.pumpWidget(FrayApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Authenticator or recovery code'), findsNothing);
    expect(find.text('Create an account'), findsOneWidget);
    await tester.ensureVisible(find.text('Explore the demo'));
    await tester.tap(find.text('Explore the demo'));
    await tester.pumpAndSettle();
    expect(store.demo, isTrue);
    expect(find.textContaining('Demo workspace ·'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
