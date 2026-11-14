import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fray/l10n/localization.dart';
import 'package:fray/l10n/translations.dart';
import 'package:fray/src/app.dart';
import 'package:fray/src/data.dart';
import 'package:fray/src/preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty(),
  );

  test('Preferences survive restart; bad values fall back to system', () async {
    final storage = SharedPreferencesAsync();
    final first = await AppPreferences.load(storage);
    await first.setLanguage('hr');
    await first.setTheme(ThemeMode.dark);
    final restarted = await AppPreferences.load(storage);
    expect(restarted.language, 'hr');
    expect(restarted.themeMode, ThemeMode.dark);
    await storage.setString('fray.language', 'unsupported');
    await storage.setString('fray.theme', 'invalid');
    final repaired = await AppPreferences.load(storage);
    expect(repaired.language, 'system');
    expect(repaired.themeMode, ThemeMode.system);
    first.dispose();
    restarted.dispose();
    repaired.dispose();
  });

  test(
    'System language resolves supported regional locales, then English',
    () async {
      final preferences = AppPreferences();
      expect(
        preferences.resolve([const Locale('en', 'GB')]),
        const Locale('en', 'GB'),
      );
      expect(
        preferences.resolve([const Locale('de'), const Locale('sl', 'SI')]),
        const Locale('sl', 'SI'),
      );
      expect(preferences.resolve([const Locale('de')]), const Locale('en'));
      await preferences.setLanguage('hr');
      expect(preferences.resolve([const Locale('sl')]), const Locale('hr'));
      preferences.dispose();
    },
  );

  test(
    'Catalogs preserve named placeholders and do not interpret user content',
    () {
      Set<String> placeholders(String text) =>
          RegExp(r'\{\w+\}').allMatches(text).map((m) => m[0]!).toSet();
      for (final entry in translations.entries) {
        expect(entry.value.length, 2);
        for (final text in entry.value) {
          expect(text, isNotEmpty);
          expect(
            placeholders(text),
            placeholders(entry.key),
            reason: entry.key,
          );
        }
      }
      expect(
        translate('sl', 'My workspace  /  {page}', {'page': '{page}'}),
        'Moj delovni prostor  /  {page}',
      );
    },
  );

  for (final language in ['en', 'sl', 'hr']) {
    for (final width in [390.0, 1440.0]) {
      testWidgets(
        '$language dark workspace, navigation and editors at $width',
        (tester) async {
          tester.view.physicalSize = Size(width, 1100);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          final preferences = AppPreferences();
          await preferences.setLanguage(language);
          await preferences.setTheme(ThemeMode.dark);
          final store = FrayStore()..startDemo();
          addTearDown(store.dispose);
          addTearDown(preferences.dispose);
          await tester.pumpWidget(
            FrayApp(store: store, preferences: preferences),
          );
          await tester.pumpAndSettle();
          expect(
            Theme.of(tester.element(find.byType(Workspace))).brightness,
            Brightness.dark,
          );
          expect(store.language, language);
          for (final label in [
            'Entries',
            'Projects',
            'Reports',
            'Profile',
            'Calendar',
          ]) {
            await tester.tap(find.text(translate(language, label)).last);
            await tester.pumpAndSettle();
            expect(
              tester.takeException(),
              isNull,
              reason: '$language $label at $width',
            );
          }
          await tester.tap(find.text(translate(language, 'Add entry')));
          await tester.pumpAndSettle();
          expect(find.text(translate(language, 'Hours')), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.tap(find.text(translate(language, 'Cancel')));
          await tester.pumpAndSettle();
          await tester.tap(find.text(translate(language, 'Projects')).last);
          await tester.pumpAndSettle();
          await tester.tap(find.text(translate(language, 'Activities')));
          await tester.pumpAndSettle();
          expect(
            find.text(translate(language, 'New project / activity')),
            findsOneWidget,
          );
          await tester.tap(
            find.text(translate(language, 'New project / activity')),
          );
          await tester.pumpAndSettle();
          expect(
            find.text(translate(language, 'Description (optional)')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }

  testWidgets(
    'Login settings change immediately, persist and retain entered credentials',
    (tester) async {
      final storage = SharedPreferencesAsync();
      final preferences = await AppPreferences.load(storage);
      final store = FrayStore(
        client: MockClient(
          (r) async => http.Response(
            r.url.path.endsWith('csrf')
                ? '{"csrfToken":"test"}'
                : '{"stage":"credentials"}',
            200,
            headers: {'content-type': 'application/json'},
          ),
        ),
      );
      addTearDown(preferences.dispose);
      addTearDown(store.dispose);
      await tester.pumpWidget(FrayApp(store: store, preferences: preferences));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.widgetWithText(TextField, 'Email'),
        'private@example.test',
      );
      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('language-system')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Slovenščina').last);
      await tester.pumpAndSettle();
      expect(find.text('Nastavitve'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('theme-system')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Temno').last);
      await tester.pumpAndSettle();
      expect(
        Theme.of(tester.element(find.byType(AlertDialog))).brightness,
        Brightness.dark,
      );
      await tester.tap(find.text('Končano'));
      await tester.pumpAndSettle();
      expect(find.text('E-poštni naslov'), findsOneWidget);
      expect(find.text('private@example.test'), findsOneWidget);
      final restarted = await AppPreferences.load(storage);
      expect(restarted.language, 'sl');
      expect(restarted.themeMode, ThemeMode.dark);
      restarted.dispose();
      await tester.pumpWidget(const SizedBox());
    },
  );

  testWidgets(
    'System mode follows live OS changes; explicit light overrides them',
    (tester) async {
      final preferences = AppPreferences();
      final store = FrayStore()..startDemo();
      addTearDown(store.dispose);
      addTearDown(preferences.dispose);
      addTearDown(tester.platformDispatcher.clearAllTestValues);
      tester.platformDispatcher.localesTestValue = [const Locale('sl', 'SI')];
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpWidget(FrayApp(store: store, preferences: preferences));
      await tester.pumpAndSettle();
      BuildContext context() => tester.element(find.byType(Workspace));
      expect(Localizations.localeOf(context()), const Locale('sl', 'SI'));
      expect(Theme.of(context()).brightness, Brightness.dark);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.light;
      tester.platformDispatcher.localesTestValue = [const Locale('hr', 'HR')];
      await tester.pumpAndSettle();
      expect(Theme.of(context()).brightness, Brightness.light);
      expect(Localizations.localeOf(context()), const Locale('hr', 'HR'));
      await preferences.setTheme(ThemeMode.light);
      tester.platformDispatcher.platformBrightnessTestValue = Brightness.dark;
      await tester.pumpAndSettle();
      expect(Theme.of(context()).brightness, Brightness.light);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
