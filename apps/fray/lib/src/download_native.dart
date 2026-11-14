import 'package:flutter/services.dart';

Future<String> downloadCsv(String text, String filename) async {
  await Clipboard.setData(ClipboardData(text: text));
  return 'CSV copied to clipboard. File downloads are available on web.';
}
