import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fray/src/app.dart';
import 'package:fray/src/data.dart';
import 'package:fray/src/time_context.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Device timezone, secure storage, and localized pickers', (
    tester,
  ) async {
    final clock = await TimeContext.detect();
    expect(clock.detected, isTrue);
    const storage = FlutterSecureStorage();
    const key = 'fray.integration.ephemeral';
    try {
      await storage.write(key: key, value: 'device-check');
      expect(await storage.read(key: key), 'device-check');
    } finally {
      await storage.delete(key: key);
    }
    final store = FrayStore(clock: clock)..startDemo();
    await tester.pumpWidget(FrayApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Add entry'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('entry-date')));
    await tester.tap(find.byKey(const ValueKey('entry-date')));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
    final dateContext = tester.element(find.byType(DatePickerDialog));
    await tester.tap(
      find.text(MaterialLocalizations.of(dateContext).okButtonLabel),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Start & end'));
    await tester.tap(find.text('Start & end'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('entry-start')));
    await tester.tap(find.byKey(const ValueKey('entry-start')));
    await tester.pumpAndSettle();
    expect(find.byType(TimePickerDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    store.dispose();
  });
}
