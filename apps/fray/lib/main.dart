import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/preferences.dart';

import 'package:shared_preferences/shared_preferences.dart';

import 'src/time_context.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TimeContext.device = await TimeContext.detect();
  final preferences = await AppPreferences.load(SharedPreferencesAsync());
  runApp(FrayApp(preferences: preferences));
}
