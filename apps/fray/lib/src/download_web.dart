import 'dart:js_interop';

import 'package:web/web.dart' as web;

Future<String> downloadCsv(String text, String filename) async {
  final blob = web.Blob(
    [text.toJS].toJS,
    web.BlobPropertyBag(type: 'text/csv;charset=utf-8'),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  Future<void>.delayed(
    const Duration(seconds: 10),
    () => web.URL.revokeObjectURL(url),
  );
  return 'CSV download started.';
}
