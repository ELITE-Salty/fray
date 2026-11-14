import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:fray/src/app.dart';
import 'package:fray/src/data.dart';
import 'package:fray/src/editors.dart';
import 'package:fray/src/account_security.dart';
import 'package:fray/src/preferences.dart';
import 'package:fray/src/report_export.dart';
import 'package:fray/l10n/localization.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Detailed PDF handles localized text and long notes', () async {
    await initializeDateFormatting('sl');
    final store = FrayStore()..startDemo();
    addTearDown(store.dispose);
    store.entries = [
      TimeRecord({
        'id': 'test',
        'item_id': '1',
        'mode': 'duration',
        'date': '2026-11-14',
        'minutes': 90,
        'notes': List.filled(100, 'č š ž study notes').join(' '),
      }),
    ];
    final bytes = await reportPdf(
      store,
      DateTime(2026, 11),
      'sl',
      detailed: true,
      notes: true,
    );
    expect(ascii.decode(bytes.take(4).toList()), '%PDF');
    expect(bytes.length, greaterThan(1000));
  });
  for (final language in ['en', 'sl', 'hr']) {
    for (final width in [390.0, 1440.0]) {
      testWidgets(
        '$language new calendar views and security dialog at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final prefs = AppPreferences()
            ..language = language
            ..themeMode = ThemeMode.dark;
          final store = FrayStore()..startDemo();
          addTearDown(store.dispose);
          addTearDown(prefs.dispose);
          final day = store.clock.now();
          store.entries.add(
            TimeRecord({
              'id': 'late',
              'item_id': '1',
              'mode': 'timed',
              'date': dayKey(day),
              'timezone': 'UTC',
              'minutes': 1,
              'start': '${dayKey(day)}T23:59:00Z',
              'end': '${dayKey(day.add(const Duration(days: 1)))}T00:00:00Z',
            }),
          );
          await tester.pumpWidget(FrayApp(store: store, preferences: prefs));
          await tester.pumpAndSettle();
          for (final view in ['Week', 'Day', 'Month']) {
            final finder = find.text(translate(language, view));
            await tester.ensureVisible(finder);
            await tester.tap(finder);
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull, reason: view);
          }
          // Open a duplicate draft and save it: the original remains unchanged.
          final context = tester.element(find.byType(Workspace));
          final original = store.entries.firstWhere(
            (e) => e.mode == 'duration',
          );
          final count = store.entries.length;
          showDialog<void>(
            context: context,
            builder: (_) => EntryEditor(
              store: store,
              day: day,
              entry: original,
              duplicate: true,
            ),
          );
          await tester.pumpAndSettle();
          await tester.tap(find.text(translate(language, 'Save entry')));
          await tester.pumpAndSettle();
          expect(store.entries.length, count + 1);
          expect(store.entries.any((e) => e.id == original.id), isTrue);
          showDialog<void>(
            context: context,
            builder: (_) => AccountSecurityDialog(store: store),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
}
