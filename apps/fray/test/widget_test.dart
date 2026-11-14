import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fray/src/app.dart';
import 'package:fray/src/data.dart';

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
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Duration in minutes'),
      '75',
    );
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

  testWidgets('Sign in offers an explicitly labeled demo', (tester) async {
    final store = FrayStore();
    addTearDown(store.dispose);
    await tester.pumpWidget(FrayApp(store: store));
    expect(find.text('Authenticator or recovery code'), findsOneWidget);
    await tester.ensureVisible(find.text('Explore the demo'));
    await tester.tap(find.text('Explore the demo'));
    await tester.pumpAndSettle();
    expect(store.demo, isTrue);
    expect(find.textContaining('Demo workspace ·'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
