import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../l10n/localization.dart';
import 'data.dart';
import 'time_context.dart';

Future<Uint8List> reportPdf(
  FrayStore store,
  DateTime month,
  String locale, {
  bool detailed = false,
  bool notes = false,
}) async {
  final font = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Regular.ttf'),
  );
  final bold = pw.Font.ttf(
    await rootBundle.load('assets/fonts/Roboto-Bold.ttf'),
  );
  final language = locale.split('_').first;
  String tr(String source) => translate(language, source);
  final entries = store.inMonth(month)
    ..sort((a, b) => a.date.compareTo(b.date));
  final totals = <String, int>{};
  for (final entry in entries) {
    totals[entry.itemId] = (totals[entry.itemId] ?? 0) + entry.minutes;
  }
  final doc = pw.Document(
    title: 'Fray — ${DateFormat.yMMMM(locale).format(month)}',
  );
  doc.addPage(
    pw.MultiPage(
      maxPages: 1000,
      pageFormat: PdfPageFormat.a4,
      theme: pw.ThemeData.withFont(base: font, bold: bold),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          '${context.pageNumber} / ${context.pagesCount}',
          style: const pw.TextStyle(fontSize: 9),
        ),
      ),
      build: (_) => [
        pw.Text(
          'Fray',
          style: pw.TextStyle(fontSize: 28, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          DateFormat.yMMMM(locale).format(month),
          style: const pw.TextStyle(fontSize: 18),
        ),
        pw.SizedBox(height: 12),
        if (store.queue.isNotEmpty)
          pw.Text(tr('Includes pending local entries.')),
        pw.Text(
          '${tr('Total time')}: ${translate(language, '{hours}h {minutes}m', {'hours': entries.fold(0, (s, e) => s + e.minutes) ~/ 60, 'minutes': entries.fold(0, (s, e) => s + e.minutes) % 60})}',
        ),
        pw.SizedBox(height: 20),
        pw.TableHelper.fromTextArray(
          headers: [tr('Project / activity'), tr('Minutes')],
          data: totals.entries
              .map((e) => [store.item(e.key).name, '${e.value}'])
              .toList(),
        ),
        if (detailed) ...[
          pw.SizedBox(height: 20),
          pw.Text(
            tr('Entries'),
            style: pw.TextStyle(fontSize: 18, fontWeight: pw.FontWeight.bold),
          ),
          pw.TableHelper.fromTextArray(
            headers: [
              tr('Date'),
              tr('Project / activity'),
              tr('Start & end'),
              tr('Minutes'),
            ],
            data: entries.map((e) {
              final clock = TimeContext(e.timezone);
              final interval = e.start == null
                  ? tr('Unscheduled time')
                  : '${DateFormat.yMd(locale).add_Hm().format(clock.local(e.start!))} – ${DateFormat.yMd(locale).add_Hm().format(clock.local(e.end!))} (${e.timezone})';
              return [
                DateFormat.yMd(locale).format(DateTime.parse(e.date)),
                store.item(e.itemId).name,
                interval,
                '${e.minutes}',
              ];
            }).toList(),
          ),
          if (notes)
            ...entries
                .where((e) => e.notes.isNotEmpty)
                .expand(
                  (e) => [
                    pw.SizedBox(height: 10),
                    pw.Text('${e.date} · ${store.item(e.itemId).name}'),
                    for (var offset = 0; offset < e.notes.length; offset += 300)
                      pw.Text(
                        e.notes.substring(
                          offset,
                          (offset + 300).clamp(0, e.notes.length),
                        ),
                      ),
                  ],
                ),
        ],
      ],
    ),
  );
  return doc.save();
}
