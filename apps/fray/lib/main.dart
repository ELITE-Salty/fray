import 'package:flutter/material.dart';

import 'src/app.dart';
import 'src/time_context.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  TimeContext.device = await TimeContext.detect();
  runApp(const FrayApp());
}
