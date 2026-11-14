import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

Future<String> downloadBytes(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  final blob = web.Blob([bytes.toJS].toJS, web.BlobPropertyBag(type: mimeType));
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  anchor.click();
  Future<void>.delayed(
    const Duration(seconds: 10),
    () => web.URL.revokeObjectURL(url),
  );
  return 'Download started.';
}

Future<String> downloadCsv(String text, String filename) => downloadBytes(
  Uint8List.fromList(utf8.encode(text)),
  filename,
  'text/csv;charset=utf-8',
);
