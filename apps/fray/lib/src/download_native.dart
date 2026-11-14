import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:share_plus/share_plus.dart';

Future<String> downloadBytes(
  Uint8List bytes,
  String filename,
  String mimeType,
) async {
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile.fromData(bytes, mimeType: mimeType)],
      fileNameOverrides: [filename],
      sharePositionOrigin: const Rect.fromLTWH(24, 24, 1, 1),
    ),
  );
  return 'File ready to share.';
}

Future<String> downloadCsv(String text, String filename) =>
    downloadBytes(Uint8List.fromList(utf8.encode(text)), filename, 'text/csv');
