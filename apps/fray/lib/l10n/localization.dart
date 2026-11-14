import 'package:flutter/material.dart';

import 'translations.dart';

/// English is the source language; sl and hr use matching named placeholders.
String translate(
  String language,
  String source, [
  Map<String, Object> values = const {},
]) {
  final index = switch (language) {
    'sl' => 0,
    'hr' => 1,
    _ => -1,
  };
  final message = index < 0 ? source : translations[source]?[index] ?? source;
  // One pass: user content containing braces must never be interpreted as a template.
  return message.replaceAllMapped(
    RegExp(r'\{(\w+)\}'),
    (match) => values[match[1]]?.toString() ?? match[0]!,
  );
}

extension FrayLocalization on BuildContext {
  String tr(String source, [Map<String, Object> values = const {}]) =>
      translate(Localizations.localeOf(this).languageCode, source, values);
  String duration(int minutes) => tr('{hours}h {minutes}m', {
    'hours': minutes ~/ 60,
    'minutes': minutes % 60,
  });
  Color get ink => Theme.of(this).colorScheme.onSurface;
  Color get muted => Theme.of(this).colorScheme.onSurfaceVariant;
  Color get purple => Theme.of(this).colorScheme.primary;
  Color get lavender => Theme.of(this).colorScheme.primaryContainer;
  Color get line => Theme.of(this).colorScheme.outlineVariant;
  Color get surface => Theme.of(this).colorScheme.surface;
  Color accent(Color color) => Theme.of(this).brightness == Brightness.dark
      ? Color.lerp(color, Colors.white, .4)!
      : color;
}

mixin LocalizedState<T extends StatefulWidget> on State<T> {
  String tr(String source, [Map<String, Object> values = const {}]) =>
      context.tr(source, values);
  Color get ink => context.ink;
  Color get muted => context.muted;
  Color get purple => context.purple;
  Color get lavender => context.lavender;
  Color get line => context.line;
}
