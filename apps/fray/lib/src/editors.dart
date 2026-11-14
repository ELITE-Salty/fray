import '../l10n/localization.dart';

import 'package:flutter/material.dart';

import 'time_context.dart';

import 'data.dart';

class EntryEditor extends StatefulWidget {
  final FrayStore store;
  final DateTime day;
  final TimeRecord? entry;
  final bool duplicate;
  final TimeOfDay? initialStart;
  final Future<void> Function()? onSaved;
  const EntryEditor({
    super.key,
    required this.store,
    required this.day,
    this.entry,
    this.duplicate = false,
    this.onSaved,
    this.initialStart,
  });
  @override
  State<EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<EntryEditor> with LocalizedState {
  final form = GlobalKey<FormState>();
  late final TextEditingController hours, minutes, notes;
  late DateTime day;
  late TimeOfDay start, end;
  late TimeContext clock;
  DateTime? startOccurrence, endOccurrence;
  late String itemId, mode;
  bool overnight = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    final entry = widget.entry;
    clock = widget.entry == null
        ? widget.store.clock
        : TimeContext(entry!.timezone);
    day = entry == null || widget.duplicate
        ? DateUtils.dateOnly(widget.day)
        : DateTime.parse(entry.date);
    start = entry?.start == null
        ? widget.initialStart ?? const TimeOfDay(hour: 9, minute: 0)
        : TimeOfDay.fromDateTime(clock.local(entry!.start!));
    end = entry?.end == null
        ? TimeOfDay(hour: (start.hour + 1) % 24, minute: start.minute)
        : TimeOfDay.fromDateTime(clock.local(entry!.end!));
    startOccurrence = widget.duplicate ? null : entry?.start;
    endOccurrence = widget.duplicate ? null : entry?.end;
    final duration = entry?.minutes ?? 60;
    hours = TextEditingController(text: '${duration ~/ 60}');
    minutes = TextEditingController(text: '${duration % 60}');
    notes = TextEditingController(text: entry?.notes ?? '');
    itemId = entry?.itemId ?? widget.store.items.firstWhere((i) => i.canLog).id;
    mode = entry?.mode ?? (widget.initialStart == null ? 'duration' : 'timed');
    overnight =
        widget.initialStart?.hour == 23 ||
        entry?.start != null &&
            dayKey(clock.local(entry!.start!)) !=
                dayKey(clock.local(entry.end!));
  }

  @override
  void dispose() {
    for (final c in [hours, minutes, notes]) {
      c.dispose();
    }
    super.dispose();
  }

  DateTime get endDay =>
      DateTime(day.year, day.month, day.day + (overnight ? 1 : 0));

  Future<void> pickDate() async {
    final value = await showDatePicker(
      context: context,
      initialDate: day,
      firstDate: DateTime(day.year < 1900 ? day.year : 1900),
      lastDate: DateTime(day.year > 2100 ? day.year : 2100, 12, 31),
    );
    if (value != null && mounted) setState(() => day = value);
  }

  Future<void> pickTime(bool isStart) async {
    final value = await showTimePicker(
      context: context,
      initialTime: isStart ? start : end,
    );
    if (value != null && mounted) {
      setState(() {
        if (isStart) {
          start = value;
        } else {
          end = value;
        }
      });
    }
  }

  Widget pickerField({
    required Key key,
    required String label,
    required String value,
    required IconData icon,
    required VoidCallback onTap,
  }) => Semantics(
    button: true,
    label: label,
    value: value,
    child: InkWell(
      key: key,
      onTap: busy ? null : onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          suffixIcon: Icon(icon, size: 20),
        ),
        child: Text(value),
      ),
    ),
  );

  Widget occurrencePicker(bool isStart) {
    final options = clock.candidates(
      isStart ? day : endDay,
      isStart ? start : end,
    );
    if (options.length < 2) return const SizedBox.shrink();
    final selected = isStart ? startOccurrence : endOccurrence;
    final matching = options
        .where((o) => selected?.isAtSameMomentAs(o) ?? false)
        .firstOrNull;
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: DropdownButtonFormField<DateTime>(
        key: ValueKey(
          '${isStart ? 'start' : 'end'}-${dayKey(day)}-${isStart ? start : end}-$overnight',
        ),
        initialValue: matching,
        isExpanded: true,
        decoration: InputDecoration(
          labelText: tr(
            isStart
                ? 'Start occurrence (clock change)'
                : 'End occurrence (clock change)',
          ),
        ),
        items: options
            .asMap()
            .entries
            .map(
              (e) => DropdownMenuItem(
                value: e.value,
                child: Text(
                  '${e.key == 0 ? tr('First') : tr('Second')} · ${clock.offsetLabel(e.value)}',
                ),
              ),
            )
            .toList(),
        onChanged: busy
            ? null
            : (value) => setState(() {
                if (isStart) {
                  startOccurrence = value;
                } else {
                  endOccurrence = value;
                }
              }),
      ),
    );
  }

  int? durationPart(TextEditingController controller, int maximum) {
    final text = controller.text.trim();
    if (text.isEmpty) return 0;
    if (!RegExp(r'^[0-9]+$').hasMatch(text)) return null;
    final value = int.tryParse(text);
    return value != null && value <= maximum ? value : null;
  }

  int get enteredDuration {
    final h = durationPart(hours, 24), m = durationPart(minutes, 59);
    if (h == null || m == null) {
      throw FormatException(tr('Enter whole hours (0–24) and minutes (0–59).'));
    }
    return h * 60 + m;
  }

  Widget durationField({required bool isHours}) {
    final controller = isHours ? hours : minutes;
    return TextFormField(
      key: ValueKey(isHours ? 'entry-hours' : 'entry-minutes'),
      controller: controller,
      enabled: !busy,
      onChanged: (_) => setState(() => error = null),
      keyboardType: TextInputType.number,
      textInputAction: TextInputAction.next,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      validator: (_) => durationPart(controller, isHours ? 24 : 59) == null
          ? tr(isHours ? 'Use 0–24 whole hours.' : 'Use 0–59 whole minutes.')
          : null,
      decoration: InputDecoration(
        labelText: tr(isHours ? 'Hours' : 'Minutes'),
        hintText: '0',
        errorMaxLines: 3,
      ),
    );
  }

  String get previewDuration {
    try {
      final duration = mode == 'duration'
          ? enteredDuration
          : clock
                .resolve(endDay, end, occurrence: endOccurrence)
                .difference(
                  clock.resolve(day, start, occurrence: startOccurrence),
                )
                .inMinutes;
      return duration > 0 && duration <= 1440
          ? tr('Total: {duration}', {'duration': context.duration(duration)})
          : tr('Choose an interval between 1 minute and 24 hours.');
    } on FormatException catch (e) {
      return tr(e.message);
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      DateTime? from, to;
      int duration;
      if (mode == 'timed') {
        from = clock.resolve(day, start, occurrence: startOccurrence);
        to = clock.resolve(endDay, end, occurrence: endOccurrence);
        duration = to.difference(from).inMinutes;
      } else {
        duration = enteredDuration;
      }
      if (duration < 1 || duration > 1440) {
        throw FormatException(
          tr('Choose a duration between 1 minute and 24 hours.'),
        );
      }
      await widget.store.saveEntry({
        'item_id': itemId,
        'date': dayKey(day),
        'timezone': clock.zone,
        'mode': mode,
        'start': from?.toIso8601String(),
        'end': to?.toIso8601String(),
        'minutes': duration,
        'notes': notes.text,
        if (!widget.duplicate && widget.entry != null)
          'revision': widget.entry!.revision,
      }, widget.duplicate ? null : widget.entry?.id);
      await widget.onSaved?.call();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(
          () => error = e is FormatException ? tr(e.message) : e.toString(),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> delete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Delete this entry?')),
        content: Text(
          tr('This removes the entry from your calendar and reports.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Keep entry')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.deleteEntry(widget.entry!.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.entry == null || widget.duplicate
          ? tr('Add time entry')
          : tr('Edit time entry'),
    ),
    content: SizedBox(
      width: 440,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: itemId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: tr('Project / activity'),
                ),
                items: widget.store.items
                    .where((i) => i.canLog || i.id == itemId)
                    .map(
                      (i) => DropdownMenuItem(
                        value: i.id,
                        child: Text(i.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: busy ? null : (v) => setState(() => itemId = v!),
              ),
              const SizedBox(height: 16),
              pickerField(
                key: const ValueKey('entry-date'),
                label: tr('Date'),
                value: MaterialLocalizations.of(context).formatCompactDate(day),
                icon: Icons.calendar_month_outlined,
                onTap: pickDate,
              ),
              const SizedBox(height: 18),
              SegmentedButton<String>(
                segments: [
                  ButtonSegment(value: 'duration', label: Text(tr('Duration'))),
                  ButtonSegment(value: 'timed', label: Text(tr('Start & end'))),
                ],
                selected: {mode},
                onSelectionChanged: busy
                    ? null
                    : (v) => setState(() => mode = v.first),
              ),
              const SizedBox(height: 18),
              if (mode == 'duration') ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(child: durationField(isHours: true)),
                    const SizedBox(width: 12),
                    Expanded(child: durationField(isHours: false)),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  tr('No start or end time will be invented.'),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: pickerField(
                        key: const ValueKey('entry-start'),
                        label: tr('Start'),
                        value: start.format(context),
                        icon: Icons.access_time,
                        onTap: () => pickTime(true),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: pickerField(
                        key: const ValueKey('entry-end'),
                        label: tr('End'),
                        value: end.format(context),
                        icon: Icons.access_time,
                        onTap: () => pickTime(false),
                      ),
                    ),
                  ],
                ),
                occurrencePicker(true),
                occurrencePicker(false),
                const SizedBox(height: 10),
                Text(
                  tr('Time zone: {zone}', {'zone': clock.zone}) +
                      (!clock.detected ? tr(' (device zone unavailable)') : ''),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    tr('Ends the following day'),
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: overnight,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => overnight = v!),
                ),
              ],
              Text(
                previewDuration,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: notes,
                maxLines: 3,
                maxLength: 2000,
                decoration: InputDecoration(
                  labelText: tr('Notes (optional)'),
                  alignLabelWithHint: true,
                ),
              ),
              if (error != null)
                Text(
                  tr(error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
            ],
          ),
        ),
      ),
    ),
    actions: [
      if (widget.entry != null && !widget.duplicate)
        TextButton(
          onPressed: busy ? null : delete,
          child: Text(
            tr('Delete'),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? tr('Saving…') : tr('Save entry')),
      ),
    ],
  );
}

class ItemEditor extends StatefulWidget {
  final FrayStore store;
  final WorkItem? item;
  const ItemEditor({super.key, required this.store, this.item});
  @override
  State<ItemEditor> createState() => _ItemEditorState();
}

class _ItemEditorState extends State<ItemEditor> with LocalizedState {
  late final TextEditingController name = TextEditingController(
    text: widget.item?.name ?? '',
  );
  late final TextEditingController description = TextEditingController(
    text: widget.item?.description ?? '',
  );
  late String kind = widget.item?.kind ?? 'project',
      color = widget.item?.hex ?? '#7153E8';
  bool busy = false;
  String? error;
  @override
  void dispose() {
    name.dispose();
    description.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (name.text.trim().isEmpty) {
      setState(() => error = 'Give your work a name.');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.store.saveItem({
        ...?widget.item?.toJson(),
        'name': name.text.trim(),
        'description': description.text,
        'kind': kind,
        'color': color,
      }, widget.item?.id);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text(
      widget.item == null
          ? tr('A new space for your work')
          : tr('Edit project / activity'),
    ),
    content: SizedBox(
      width: 400,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SegmentedButton<String>(
              segments: [
                ButtonSegment(value: 'project', label: Text(tr('Project'))),
                ButtonSegment(value: 'activity', label: Text(tr('Activity'))),
              ],
              selected: {kind},
              onSelectionChanged: busy
                  ? null
                  : (v) => setState(() => kind = v.first),
            ),
            const SizedBox(height: 20),
            TextField(
              controller: name,
              maxLength: 120,
              decoration: InputDecoration(labelText: tr('Name')),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: description,
              maxLines: 2,
              maxLength: 500,
              decoration: InputDecoration(
                labelText: tr('Description (optional)'),
              ),
            ),
            const SizedBox(height: 16),
            Text(tr('Color')),
            const SizedBox(height: 10),
            Wrap(
              spacing: 10,
              children: ['#7153E8', '#D88A40', '#398E7A', '#538BC4', '#C75A87']
                  .map(
                    (hex) => Semantics(
                      label: tr('Color {hex}', {'hex': hex}),
                      selected: color == hex,
                      child: InkWell(
                        onTap: () => setState(() => color = hex),
                        borderRadius: BorderRadius.circular(20),
                        child: CircleAvatar(
                          radius: 19,
                          backgroundColor: Color(
                            int.parse('FF${hex.substring(1)}', radix: 16),
                          ),
                          child: color == hex
                              ? const Icon(
                                  Icons.check,
                                  color: Colors.white,
                                  size: 20,
                                )
                              : null,
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.only(top: 16),
                child: Text(
                  tr(error!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: busy ? null : () => Navigator.pop(context),
        child: Text(tr('Cancel')),
      ),
      FilledButton(
        onPressed: busy ? null : save,
        child: Text(busy ? tr('Saving…') : tr('Save')),
      ),
    ],
  );
}
