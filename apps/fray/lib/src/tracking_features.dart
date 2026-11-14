import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../l10n/localization.dart';
import 'data.dart';
import 'auth_screen.dart';
import 'editors.dart';
import 'time_context.dart';

Future<String?> askText(
  BuildContext context,
  String title, {
  String initial = '',
  bool numeric = false,
}) async {
  final controller = TextEditingController(text: initial);
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(context.tr(title)),
      content: TextField(
        controller: controller,
        autofocus: true,
        maxLength: numeric ? 5 : 120,
        keyboardType: numeric ? TextInputType.number : TextInputType.text,
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(context.tr('Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(context.tr('Save')),
        ),
      ],
    ),
  );
  // The outgoing dialog may still be animating; its TextField retains the controller.
  await Future<void>.delayed(const Duration(milliseconds: 300));
  controller.dispose();
  return result;
}

class TimerPanel extends StatefulWidget {
  final FrayStore store;
  const TimerPanel({super.key, required this.store});
  @override
  State<TimerPanel> createState() => _TimerPanelState();
}

class _TimerPanelState extends State<TimerPanel> with LocalizedState {
  Timer? ticker;
  String? selected, error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && widget.store.runningTimer != null) setState(() {});
    });
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  Future<void> action(Future<void> Function() run) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await run();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> stop() async {
    final store = widget.store, running = widget.store.runningTimer!;
    final exact = DateTime.parse(running['start']).toUtc();
    final start = DateTime.utc(
      exact.year,
      exact.month,
      exact.day,
      exact.hour,
      exact.minute,
    );
    final now = store.clock.now().toUtc();
    final end = DateTime.fromMillisecondsSinceEpoch(
      ((now.millisecondsSinceEpoch / 60000).ceil() * 60000).clamp(
        start.millisecondsSinceEpoch + 60000,
        8640000000000000,
      ),
      isUtc: true,
    );
    final minutes = end.difference(start).inMinutes;
    if (minutes > 1440) {
      throw ApiException(
        'This timer exceeds 24 hours. Record it as separate entries before discarding the timer.',
      );
    }
    final clock = TimeContext(running['timezone']);
    final entry = TimeRecord({
      'id': '',
      'item_id': running['item_id'],
      'date': dayKey(clock.local(start)),
      'timezone': running['timezone'],
      'mode': 'timed',
      'minutes': minutes,
      'start': start.toIso8601String(),
      'end': end.toIso8601String(),
      'notes': '',
    });
    await showDialog<void>(
      context: context,
      builder: (_) => EntryEditor(
        store: store,
        day: clock.local(start),
        entry: entry,
        duplicate: true,
        onSaved: store.clearTimer,
      ),
    );
  }

  Future<void> discard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr('Discard running timer?')),
        content: Text(tr('No time entry will be saved.')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(tr('Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(tr('Discard')),
          ),
        ],
      ),
    );
    if (confirmed == true) await widget.store.clearTimer();
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store, running = widget.store.runningTimer;
    final items = store.items.where((i) => i.canLog).toList();
    final current = items.any((i) => i.id == selected)
        ? selected
        : items.firstOrNull?.id;
    final elapsed = running == null
        ? Duration.zero
        : store.clock.now().toUtc().difference(
            DateTime.parse(running['start']),
          );
    final seconds = elapsed.inSeconds.clamp(0, 999999999);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          tr('Timer on this device'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        if (running == null)
          Wrap(
            spacing: 12,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: MediaQuery.sizeOf(context).width < 600 ? 250 : 320,
                child: DropdownButtonFormField<String>(
                  key: ValueKey(current),
                  initialValue: current,
                  isExpanded: true,
                  decoration: InputDecoration(
                    labelText: tr('Project / activity'),
                  ),
                  items: items
                      .map(
                        (i) => DropdownMenuItem(
                          value: i.id,
                          child: Text(i.name, overflow: TextOverflow.ellipsis),
                        ),
                      )
                      .toList(),
                  onChanged: busy ? null : (v) => setState(() => selected = v),
                ),
              ),
              FilledButton.icon(
                onPressed: current == null || busy
                    ? null
                    : () => action(() => store.startTimer(current)),
                icon: const Icon(Icons.play_arrow),
                label: Text(tr('Start timer')),
              ),
            ],
          )
        else ...[
          Text(
            store.items
                    .where((i) => i.id == running['item_id'])
                    .firstOrNull
                    ?.name ??
                tr('Project unavailable'),
          ),
          Text(
            '${seconds ~/ 3600}:${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          Text(
            tr(
              'The timer keeps its start time when you close the app. Review whole minutes before saving.',
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 12,
            children: [
              FilledButton.icon(
                onPressed: busy ? null : () => action(stop),
                icon: const Icon(Icons.stop),
                label: Text(tr('Stop and review')),
              ),
              TextButton(
                onPressed: busy ? null : () => action(discard),
                child: Text(tr('Discard')),
              ),
            ],
          ),
        ],
        if (error != null)
          Text(
            tr(error!),
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
      ],
    );
  }
}

class SyncPanel extends StatelessWidget {
  final FrayStore store;
  final VoidCallback reload;
  const SyncPanel({super.key, required this.store, required this.reload});
  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Icon(
                store.offline ? Icons.cloud_off : Icons.sync,
                color: Theme.of(context).colorScheme.primary,
              ),
              Text(
                context.tr(
                  store.syncing
                      ? 'Syncing…'
                      : store.offline
                      ? 'Offline · showing saved data'
                      : 'Pending changes',
                ),
              ),
              if (store.queue.isNotEmpty)
                Text(
                  context.tr('Pending entries: {count}', {
                    'count': store.queue.length,
                  }),
                ),
              TextButton(
                onPressed: store.syncing ? null : reload,
                child: Text(context.tr('Sync now')),
              ),
            ],
          ),
          if (store.syncError != null) Text(context.tr(store.syncError!)),
          if (store.needsLogin)
            TextButton(
              onPressed: () async {
                await Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (context) => LoginScreen(
                      store: store,
                      onAuthenticated: () => Navigator.pop(context),
                    ),
                  ),
                );
                reload();
              },
              child: Text(context.tr('Sign in again')),
            ),
          for (final op in store.queue)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${op['body']['date'] ?? op['before']?['date'] ?? ''} · ${context.tr(op['error'] ?? 'Waiting to sync')}',
                  ),
                  Wrap(
                    spacing: 12,
                    children: [
                      if (op['method'] != 'DELETE')
                        TextButton(
                          onPressed: store.syncing
                              ? null
                              : () {
                                  final entry = store.entries
                                      .where((e) => e.id == op['localId'])
                                      .firstOrNull;
                                  if (entry != null) {
                                    showDialog<void>(
                                      context: context,
                                      builder: (_) => EntryEditor(
                                        store: store,
                                        day: DateTime.parse(entry.date),
                                        entry: entry,
                                      ),
                                    );
                                  }
                                },
                          child: Text(context.tr('Review entry')),
                        ),
                      TextButton(
                        onPressed: store.syncing
                            ? null
                            : () async {
                                final yes = await showDialog<bool>(
                                  context: context,
                                  builder: (context) => AlertDialog(
                                    title: Text(
                                      context.tr('Discard pending change?'),
                                    ),
                                    content: Text(
                                      context.tr(
                                        'The local change will be removed. A change already received by the server is kept there.',
                                      ),
                                    ),
                                    actions: [
                                      TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: Text(context.tr('Cancel')),
                                      ),
                                      FilledButton(
                                        onPressed: () =>
                                            Navigator.pop(context, true),
                                        child: Text(context.tr('Discard')),
                                      ),
                                    ],
                                  ),
                                );
                                if (yes == true) {
                                  await store.discardPending(op['localId']);
                                  reload();
                                }
                              },
                        child: Text(context.tr('Discard')),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (store.offline)
            Text(
              context.tr(
                'New entries are saved on this device and retried when you reconnect. Keep the app installed until syncing completes.',
              ),
            ),
        ],
      ),
    ),
  );
}

class GoalPanel extends StatelessWidget {
  final FrayStore store;
  final DateTime day;
  const GoalPanel({super.key, required this.store, required this.day});
  @override
  Widget build(BuildContext context) {
    final first = DateUtils.dateOnly(day)
            .subtract(Duration(days: day.weekday - 1)),
        end = DateUtils.dateOnly(day).add(Duration(days: 8 - day.weekday));
    final minutes = store.entries
        .where(
          (e) =>
              e.date.compareTo(dayKey(first)) >= 0 &&
              e.date.compareTo(dayKey(end)) < 0,
        )
        .fold(0, (sum, e) => sum + e.minutes);
    final locale = Localizations.localeOf(context).toString();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              context.tr('Weekly goal'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            Text(
              '${DateFormat.MMMd(locale).format(first)} – ${DateFormat.MMMd(locale).format(end.subtract(const Duration(days: 1)))}',
            ),
            TextButton(
              onPressed: () async {
                final raw = await askText(
                  context,
                  'Weekly goal in minutes (0 disables it)',
                  initial: '${store.weeklyGoalMinutes}',
                  numeric: true,
                );
                if (raw == null) return;
                final target = int.tryParse(raw);
                if (target == null || target < 0 || target > 10080) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          context.tr(
                            'Weekly goals must be between 0 and 10080 minutes.',
                          ),
                        ),
                      ),
                    );
                  }
                  return;
                }
                try {
                  await store.saveGoal(target);
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(context.tr(e.toString()))),
                    );
                  }
                }
              },
              child: Text(context.tr('Set goal')),
            ),
          ],
        ),
        if (store.weeklyGoalMinutes > 0) ...[
          Text(
            '${context.duration(minutes)} / ${context.duration(store.weeklyGoalMinutes)}',
          ),
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: (minutes / store.weeklyGoalMinutes).clamp(0, 1),
          ),
        ] else
          Text(
            context.tr(
              'Choose a weekly target for your personal tracked time.',
            ),
          ),
      ],
    );
  }
}
