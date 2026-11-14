import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fray/src/data.dart';
import 'package:fray/src/editors.dart';
import 'package:fray/src/time_context.dart';

Future<void> openEditor(
  WidgetTester tester,
  FrayStore store, {
  Locale locale = const Locale('en', 'US'),
  bool use24 = false,
  TimeRecord? entry,
}) async {
  tester.view.physicalSize = const Size(390, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      supportedLocales: const [
        Locale('en', 'US'),
        Locale('en', 'GB'),
        Locale('sl'),
        Locale('hr'),
      ],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: use24),
        child: child!,
      ),
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => EntryEditor(
                store: store,
                day: DateTime(2026, 11, 14),
                entry: entry,
              ),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'Slovenian calendar picker saves a date without parsing display text',
    (tester) async {
      final store = FrayStore(clock: TimeContext('Europe/Ljubljana'))
        ..startDemo();
      addTearDown(store.dispose);
      await openEditor(tester, store, locale: const Locale('sl'));
      expect(find.text('Date (YYYY-MM-DD)'), findsNothing);
      final context = tester.element(find.byKey(const ValueKey('entry-date')));
      expect(
        find.text(
          MaterialLocalizations.of(context)
              .formatCompactDate(DateTime(2026, 11, 14)),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('entry-date')));
      await tester.pumpAndSettle();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      final pickerContext = tester.element(find.byType(DatePickerDialog));
      expect(Localizations.localeOf(pickerContext).languageCode, 'sl');
      await tester.tap(find.text('15').last);
      await tester.tap(
        find.text(MaterialLocalizations.of(pickerContext).okButtonLabel),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Shrani vnos'));
      await tester.pumpAndSettle();
      expect(store.entries.last.date, '2026-11-15');
      expect(store.entries.last.timezone, 'Europe/Ljubljana');
      expect(store.entries.last.start, isNull);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );

  for (final use24 in [false, true]) {
    testWidgets('Time picker follows device 24-hour preference: $use24', (
      tester,
    ) async {
      final store = FrayStore(clock: TimeContext('Europe/Ljubljana'))
        ..startDemo();
      addTearDown(store.dispose);
      await openEditor(tester, store, use24: use24);
      await tester.tap(find.text('Start & end'));
      await tester.pumpAndSettle();
      expect(find.text(use24 ? '09:00' : '9:00 AM'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('entry-start')));
      await tester.pumpAndSettle();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      expect(
        MediaQuery.alwaysUse24HourFormatOf(
          tester.element(find.byType(TimePickerDialog)),
        ),
        use24,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }

  testWidgets(
    'Editing an old UTC entry while travelling preserves date and instants',
    (tester) async {
      final store = FrayStore(clock: TimeContext('Europe/Ljubljana'))
        ..startDemo();
      addTearDown(store.dispose);
      final entry = TimeRecord({
        'id': 'old',
        'item_id': '1',
        'date': '2026-02-13',
        'timezone': 'UTC',
        'mode': 'timed',
        'start': '2026-02-13T23:30:00Z',
        'end': '2026-02-14T00:30:00Z',
        'minutes': 60,
      });
      store.entries = [entry];
      await openEditor(tester, store, entry: entry, use24: true);
      expect(find.text('23:30'), findsOneWidget);
      await tester.tap(find.text('Save entry'));
      await tester.pumpAndSettle();
      expect(store.entries.single.start, entry.start);
      expect(store.entries.single.end, entry.end);
      expect(store.entries.single.date, entry.date);
      expect(store.entries.single.timezone, 'UTC');
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
