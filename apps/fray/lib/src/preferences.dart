import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../l10n/localization.dart';

class AppPreferences extends ChangeNotifier {
  AppPreferences({SharedPreferencesAsync? storage}) : this._(storage);
  AppPreferences._(this._storage);
  final SharedPreferencesAsync? _storage;
  String language = 'system';
  ThemeMode themeMode = ThemeMode.system;
  bool saving = false;
  static const languages = ['en', 'sl', 'hr'];

  static Future<AppPreferences> load(SharedPreferencesAsync storage) async {
    final preferences = AppPreferences(storage: storage);
    try {
      final language = await storage.getString('fray.language');
      final theme = await storage.getString('fray.theme');
      if (languages.contains(language)) preferences.language = language!;
      preferences.themeMode =
          ThemeMode.values.where((mode) => mode.name == theme).firstOrNull ??
          ThemeMode.system;
    } catch (_) {
      // Unavailable browser/device storage must not prevent opening the app.
    }
    return preferences;
  }

  Locale resolve(List<Locale>? deviceLocales) {
    if (language != 'system') return Locale(language);
    for (final locale in deviceLocales ?? <Locale>[]) {
      if (languages.contains(locale.languageCode)) return locale;
    }
    return const Locale('en');
  }

  Future<void> setLanguage(String value) async {
    if (value != 'system' && !languages.contains(value)) {
      throw ArgumentError.value(value);
    }
    await _save('fray.language', value, () => language = value);
  }

  Future<void> setTheme(ThemeMode value) =>
      _save('fray.theme', value.name, () => themeMode = value);

  Future<void> _save(String key, String value, VoidCallback apply) async {
    if (saving) return;
    saving = true;
    notifyListeners();
    try {
      await _storage?.setString(key, value);
      apply();
    } finally {
      saving = false;
      notifyListeners();
    }
  }
}

class PreferencesScope extends InheritedNotifier<AppPreferences> {
  const PreferencesScope({
    super.key,
    required AppPreferences preferences,
    required super.child,
  }) : super(notifier: preferences);
  static AppPreferences of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<PreferencesScope>()!.notifier!;
}

class PreferencesPanel extends StatelessWidget {
  const PreferencesPanel({super.key});
  Future<void> save(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.tr('Could not save settings. Please try again.'),
            ),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = PreferencesScope.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.tr('Settings'),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<String>(
          key: ValueKey('language-${preferences.language}'),
          initialValue: preferences.language,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: context.tr('Language'),
            prefixIcon: const Icon(Icons.translate),
          ),
          items: [
            DropdownMenuItem(
              value: 'system',
              child: Text(context.tr('System')),
            ),
            const DropdownMenuItem(value: 'en', child: Text('English')),
            const DropdownMenuItem(value: 'sl', child: Text('Slovenščina')),
            const DropdownMenuItem(value: 'hr', child: Text('Hrvatski')),
          ],
          onChanged: preferences.saving
              ? null
              : (value) => save(context, () => preferences.setLanguage(value!)),
        ),
        const SizedBox(height: 18),
        DropdownButtonFormField<ThemeMode>(
          key: ValueKey('theme-${preferences.themeMode.name}'),
          initialValue: preferences.themeMode,
          isExpanded: true,
          decoration: InputDecoration(
            labelText: context.tr('Appearance'),
            prefixIcon: const Icon(Icons.brightness_6_outlined),
          ),
          items: ThemeMode.values
              .map(
                (mode) => DropdownMenuItem(
                  value: mode,
                  child: Text(
                    context.tr(switch (mode) {
                      ThemeMode.system => 'System',
                      ThemeMode.light => 'Light',
                      ThemeMode.dark => 'Dark',
                    }),
                  ),
                ),
              )
              .toList(),
          onChanged: preferences.saving
              ? null
              : (value) => save(context, () => preferences.setTheme(value!)),
        ),
        const SizedBox(height: 12),
        Text(
          context.tr('Saved on this device.'),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class PreferencesButton extends StatelessWidget {
  const PreferencesButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: context.tr('Settings'),
    icon: const Icon(Icons.settings_outlined),
    onPressed: () => showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        content: const SizedBox(
          width: 360,
          child: SingleChildScrollView(child: PreferencesPanel()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(context.tr('Done')),
          ),
        ],
      ),
    ),
  );
}
