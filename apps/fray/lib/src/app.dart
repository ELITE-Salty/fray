import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'time_context.dart';

import 'data.dart';
import 'editors.dart';
import 'download.dart';
import 'auth_screen.dart';

const purple = Color(0xFF7153E8);
const ink = Color(0xFF28233E);
const muted = Color(0xFF777286);
const lavender = Color(0xFFF1EDFC);
const line = Color(0xFFECE9F3);

class FrayApp extends StatefulWidget {
  final FrayStore? store;
  const FrayApp({super.key, this.store});
  @override
  State<FrayApp> createState() => _FrayAppState();
}

class _FrayAppState extends State<FrayApp> with WidgetsBindingObserver {
  late final FrayStore store = widget.store ?? FrayStore();
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (widget.store == null) {
      if (const bool.fromEnvironment('FRAY_DEMO')) {
        store.startDemo();
      } else {
        store.restore();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.store == null) {
      TimeContext.detect().then((clock) {
        if (mounted) setState(() => store.clock = clock);
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.store == null) store.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Fray · Make time for what matters',
    debugShowCheckedModeBanner: false,
    localizationsDelegates: GlobalMaterialLocalizations.delegates,
    supportedLocales: kMaterialSupportedLanguages.map(
      (language) => Locale(language),
    ),
    localeListResolutionCallback: (locales, supported) {
      for (final locale in locales ?? <Locale>[]) {
        if (GlobalMaterialLocalizations.delegate.isSupported(locale)) {
          return locale;
        }
      }
      return const Locale('en');
    },
    theme: ThemeData(
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xFFFAF9FD),
      colorScheme: ColorScheme.fromSeed(
        seedColor: purple,
        primary: purple,
        surface: Colors.white,
      ),
      fontFamily: 'Roboto',
      textTheme: const TextTheme(
        headlineMedium: TextStyle(
          fontWeight: FontWeight.w700,
          color: ink,
          letterSpacing: -1,
        ),
        titleLarge: TextStyle(fontWeight: FontWeight.w700, color: ink),
        bodyMedium: TextStyle(color: ink, height: 1.4),
      ),
      dividerColor: line,
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFFAF9FD),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    ),
    home: ListenableBuilder(
      listenable: store,
      builder: (context, _) => store.name == null
          ? LoginScreen(store: store)
          : Workspace(key: ValueKey(store.demo), store: store),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: purple,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.calendar_month_rounded,
          color: Colors.white,
          size: 23,
        ),
      ),
      const SizedBox(width: 11),
      const Text(
        'Fray',
        style: TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: ink,
        ),
      ),
    ],
  );
}

class Workspace extends StatefulWidget {
  final FrayStore store;
  const Workspace({super.key, required this.store});
  @override
  State<Workspace> createState() => _WorkspaceState();
}

class _WorkspaceState extends State<Workspace> {
  int tab = 0;
  late DateTime selected = DateUtils.dateOnly(store.clock.now());
  late DateTime month = DateTime(selected.year, selected.month);
  String search = '', filter = 'All';
  bool showArchived = false, loading = false;
  String? loadError;
  int loadSequence = 0;
  FrayStore get store => widget.store;
  static const labels = [
    'Calendar',
    'Entries',
    'Projects',
    'Reports',
    'Profile',
  ];
  static const icons = [
    Icons.calendar_month_outlined,
    Icons.schedule_rounded,
    Icons.folder_outlined,
    Icons.bar_chart_rounded,
    Icons.person_outline_rounded,
  ];
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    final version = ++loadSequence;
    setState(() {
      loading = true;
      loadError = null;
    });
    try {
      await store.load(month);
    } catch (e) {
      if (mounted && version == loadSequence) {
        setState(() => loadError = e.toString());
      }
    } finally {
      if (mounted && version == loadSequence) setState(() => loading = false);
    }
  }

  void moveMonth(int offset) {
    setState(() {
      month = DateTime(month.year, month.month + offset);
      selected = month;
    });
    load();
  }

  void message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> action(Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      message(e.toString());
    }
  }

  Future<void> editEntry([TimeRecord? entry]) async {
    if (!store.items.any((i) => !i.archived)) {
      message('Create a project or activity first.');
      await editItem();
      return;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => EntryEditor(store: store, day: selected, entry: entry),
    );
  }

  Future<void> editItem([WorkItem? item]) => showDialog<void>(
    context: context,
    builder: (_) => ItemEditor(store: store, item: item),
  );
  String get locale => Localizations.localeOf(context).toString();
  int get firstWeekday => MaterialLocalizations.of(context).firstDayOfWeekIndex;
  int get monthOffset => (month.weekday % 7 - firstWeekday + 7) % 7;

  int get total => store.inMonth(month).fold(0, (sum, e) => sum + e.minutes);
  Widget panel(Widget child, {EdgeInsets padding = const EdgeInsets.all(24)}) =>
      Container(
        padding: padding,
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border.all(color: line),
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      );

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 1000;
    return Scaffold(
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: tab,
              onDestinationSelected: (i) => setState(() => tab = i),
              destinations: List.generate(
                labels.length,
                (i) => NavigationDestination(
                  icon: Icon(icons[i]),
                  label: labels[i],
                ),
              ),
            ),
      body: SafeArea(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide) sidebar(),
            Expanded(
              child: Column(
                children: [
                  Container(
                    padding: EdgeInsets.symmetric(
                      horizontal: wide ? 36 : 20,
                      vertical: 19,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(bottom: BorderSide(color: line)),
                    ),
                    child: Row(
                      children: [
                        if (!wide)
                          const Brand()
                        else
                          Text(
                            'My workspace  /  ${labels[tab]}',
                            style: const TextStyle(color: muted),
                          ),
                        const Spacer(),
                        const Icon(Icons.lock_outline, color: muted, size: 16),
                        const SizedBox(width: 7),
                        if (wide)
                          const Text(
                            'Personal workspace',
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        const SizedBox(width: 20),
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: lavender,
                          child: Text(
                            store.name!.substring(0, 1).toUpperCase(),
                            style: const TextStyle(color: purple, fontSize: 13),
                          ),
                        ),
                        if (wide) ...[
                          const SizedBox(width: 9),
                          Text(
                            store.name!,
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (store.demo)
                    Container(
                      width: double.infinity,
                      color: lavender,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 9,
                      ),
                      child: const Text(
                        'Demo workspace · Try adding and editing time. Changes reset when you leave.',
                        style: TextStyle(
                          color: Color(0xFF6149AB),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  if (loading) const LinearProgressIndicator(minHeight: 2),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.all(wide ? 36 : 18),
                      child: Center(
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 1450),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              if (loadError != null) ...[
                                panel(
                                  Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        loadError!,
                                        style: const TextStyle(
                                          color: Colors.red,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: load,
                                        child: const Text('Retry'),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 20),
                              ],
                              heading(wide),
                              const SizedBox(height: 26),
                              switch (tab) {
                                0 => calendarPage(wide),
                                1 => entriesPage(),
                                2 => projectsPage(),
                                3 => reportsPage(),
                                _ => profilePage(),
                              },
                              const SizedBox(height: 26),
                              const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.spa_outlined,
                                    size: 15,
                                    color: muted,
                                  ),
                                  SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      'A little progress, every day.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget sidebar() => Container(
    width: 224,
    padding: const EdgeInsets.fromLTRB(23, 30, 23, 22),
    decoration: const BoxDecoration(
      color: Colors.white,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Brand(),
        const SizedBox(height: 47),
        const Padding(
          padding: EdgeInsets.only(left: 13, bottom: 15),
          child: Text(
            'WORKSPACE',
            style: TextStyle(
              fontSize: 10,
              letterSpacing: 1.8,
              color: muted,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        ...List.generate(
          labels.length,
          (i) => Padding(
            padding: const EdgeInsets.only(bottom: 7),
            child: Material(
              color: i == tab ? lavender : Colors.transparent,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => tab = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 14,
                  ),
                  child: Row(
                    children: [
                      Icon(
                        icons[i],
                        size: 21,
                        color: i == tab ? purple : muted,
                      ),
                      const SizedBox(width: 13),
                      Text(
                        labels[i],
                        style: TextStyle(
                          color: i == tab ? purple : muted,
                          fontWeight: i == tab
                              ? FontWeight.w700
                              : FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.all(17),
          decoration: BoxDecoration(
            color: const Color(0xFFF8F6FE),
            borderRadius: BorderRadius.circular(16),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_outlined, color: purple, size: 24),
              SizedBox(height: 12),
              Text(
                'Make room for focus.',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              SizedBox(height: 7),
              Text(
                'Notice where your time goes. Make space for what matters.',
                style: TextStyle(fontSize: 12, color: muted, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        const Center(
          child: Text(
            'FRAY  /  TIME WELL SPENT',
            style: TextStyle(fontSize: 9, color: muted, letterSpacing: 1.2),
          ),
        ),
      ],
    ),
  );

  Widget heading(bool wide) {
    final titles = [
      'Your time, at a glance.',
      'Small moments. Real progress.',
      'Space for every kind of work.',
      'See the bigger picture.',
      'Your own quiet corner.',
    ];
    final subtitles = [
      'A clear view of your days, with room for what matters.',
      'Everything you’ve worked on, one entry at a time.',
      'Organize projects and the activities you come back to.',
      'A thoughtful look at where your time went.',
      'Your workspace and account security.',
    ];
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 24,
      runSpacing: 20,
      children: [
        SizedBox(
          width: wide ? 490 : MediaQuery.sizeOf(context).width - 36,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                DateFormat.yMMMMEEEEd(locale)
                    .format(store.clock.now())
                    .toUpperCase(),
                style: const TextStyle(
                  color: muted,
                  fontSize: 10,
                  letterSpacing: 1.6,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 11),
              Text(
                titles[tab],
                style: Theme.of(context).textTheme.headlineMedium
                    ?.copyWith(fontSize: wide ? 30 : 25),
              ),
              const SizedBox(height: 9),
              Text(
                subtitles[tab],
                style: const TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (tab < 2)
          FilledButton.icon(
            onPressed: loading ? null : () => editEntry(),
            icon: const Icon(Icons.add, size: 19),
            label: const Text('Add entry'),
          ),
        if (tab == 2)
          FilledButton.icon(
            onPressed: () => editItem(),
            icon: const Icon(Icons.add, size: 19),
            label: const Text('New project / activity'),
          ),
        if (tab == 3)
          FilledButton.icon(
            onPressed: export,
            icon: const Icon(Icons.file_download_outlined, size: 19),
            label: const Text('Export CSV'),
          ),
      ],
    );
  }

  Widget stats() => LayoutBuilder(
    builder: (context, constraints) {
      final rows = store.inMonth(month);
      final days = rows.map((e) => e.date).toSet().length;
      final count = rows.map((e) => e.itemId).toSet().length;
      final compact = constraints.maxWidth < 550;
      return Row(
        children: [
          Expanded(
            child: stat(
              'TIME THIS MONTH',
              durationLabel(total),
              Icons.schedule_outlined,
              compact,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: stat(
              'DAYS WITH ENTRIES',
              '$days',
              Icons.calendar_today_outlined,
              compact,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: stat(
              'ITEMS WORKED ON',
              '$count',
              Icons.folder_outlined,
              compact,
            ),
          ),
        ],
      );
    },
  );
  Widget stat(String label, String value, IconData icon, bool compact) => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: purple, size: 20),
        const SizedBox(height: 15),
        Text(
          value,
          style: TextStyle(
            fontSize: compact ? 18 : 27,
            fontWeight: FontWeight.w700,
            color: ink,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          label,
          style: TextStyle(
            color: muted,
            fontSize: compact ? 8 : 9,
            letterSpacing: .6,
          ),
        ),
      ],
    ),
    padding: EdgeInsets.all(compact ? 14 : 22),
  );

  Widget monthPicker() => Row(
    children: [
      IconButton(
        tooltip: 'Previous month',
        onPressed: () => moveMonth(-1),
        icon: const Icon(Icons.chevron_left, size: 20),
      ),
      Expanded(
        child: Text(
          DateFormat.yMMMM(locale).format(month),
          textAlign: TextAlign.center,
          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      IconButton(
        tooltip: 'Next month',
        onPressed: () => moveMonth(1),
        icon: const Icon(Icons.chevron_right, size: 20),
      ),
    ],
  );

  Widget calendarPage(bool wide) => Column(
    children: [
      stats(),
      const SizedBox(height: 24),
      if (wide)
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 7, child: calendar()),
            const SizedBox(width: 22),
            Expanded(flex: 4, child: dayPanel()),
          ],
        )
      else ...[
        calendar(),
        const SizedBox(height: 20),
        dayPanel(),
      ],
    ],
  );

  Widget calendar() => panel(
    Column(
      children: [
        Row(
          children: [
            Expanded(child: monthPicker()),
            const SizedBox(width: 16),
            OutlinedButton(
              onPressed: () {
                final now = DateUtils.dateOnly(store.clock.now());
                setState(() {
                  month = DateTime(now.year, now.month);
                  selected = now;
                });
                load();
              },
              child: const Text('Today'),
            ),
          ],
        ),
        const SizedBox(height: 25),
        Row(
          children:
              List.generate(
                    7,
                    (index) => DateFormat.E(locale)
                        .format(
                          DateTime(2023, 1, 1 + (index + firstWeekday) % 7),
                        )
                        .toUpperCase(),
                  )
                  .map(
                    (d) => Expanded(
                      child: Center(
                        child: Text(
                          d,
                          style: const TextStyle(
                            fontSize: 9,
                            letterSpacing: .6,
                            fontWeight: FontWeight.w600,
                            color: muted,
                          ),
                        ),
                      ),
                    ),
                  )
                  .toList(),
        ),
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final start = DateTime(month.year, month.month, 1 - monthOffset);
            final count =
                ((monthOffset + DateTime(month.year, month.month + 1, 0).day) /
                        7)
                    .ceil() *
                7;
            final small = constraints.maxWidth < 500;
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: count,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: small ? 64 : 90,
              ),
              itemBuilder: (context, index) {
                final day = DateTime(
                  start.year,
                  start.month,
                  start.day + index,
                );
                final active = dayKey(day) == dayKey(selected);
                final today = dayKey(day) == dayKey(store.clock.now());
                final records = store.onDay(day);
                return Semantics(
                  button: true,
                  selected: active,
                  label: 'Select ${dayKey(day)}',
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        selected = day;
                      });
                      if (day.month != month.month) {
                        month = DateTime(day.year, day.month);
                        load();
                      }
                    },
                    borderRadius: BorderRadius.circular(10),
                    child: Container(
                      margin: const EdgeInsets.all(2),
                      decoration: BoxDecoration(
                        color: active
                            ? lavender
                            : today
                            ? const Color(0xFFFAF8FF)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? purple.withValues(alpha: .6)
                              : line.withValues(alpha: .5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 3,
                        vertical: 8,
                      ),
                      child: Column(
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: day.month != month.month
                                  ? const Color(0xFFB8B3C5)
                                  : active
                                  ? purple
                                  : ink,
                              fontWeight: active || today
                                  ? FontWeight.w700
                                  : FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (records.isNotEmpty)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: records
                                  .take(3)
                                  .map(
                                    (e) => Container(
                                      width: 5,
                                      height: 5,
                                      margin: const EdgeInsets.symmetric(
                                        horizontal: 2,
                                      ),
                                      decoration: BoxDecoration(
                                        color: store.item(e.itemId).color,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  )
                                  .toList(),
                            ),
                          if (!small && records.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Text(
                              durationLabel(
                                records.fold(0, (s, e) => s + e.minutes),
                              ),
                              style: const TextStyle(fontSize: 9, color: muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
        const SizedBox(height: 20),
        const Row(
          children: [
            Icon(Icons.circle, size: 7, color: purple),
            SizedBox(width: 8),
            Flexible(
              child: Text(
                'Each color is a project or activity. Select a day to see your time.',
                style: TextStyle(color: muted, fontSize: 10),
              ),
            ),
          ],
        ),
      ],
    ),
    padding: const EdgeInsets.all(18),
  );

  Widget dayPanel() {
    final rows = store.onDay(selected);
    final timed = rows.where((e) => e.mode == 'timed').toList();
    final unscheduled = rows.where((e) => e.mode == 'duration').toList();
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            DateFormat.EEEE(locale).format(selected).toUpperCase(),
            style: const TextStyle(
              color: muted,
              fontSize: 10,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 7),
          Text(
            DateFormat.MMMMd(locale).format(selected),
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 23),
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: lavender,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                const Text(
                  'Total tracked',
                  style: TextStyle(color: purple, fontSize: 12),
                ),
                const Spacer(),
                Text(
                  durationLabel(rows.fold(0, (s, e) => s + e.minutes)),
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: purple,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 23),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 25),
              child: Text(
                'A little space in your day.\nAdd your first entry when you’re ready.',
                style: TextStyle(color: muted, height: 1.8),
              ),
            ),
          if (timed.isNotEmpty) ...[
            sectionLabel('ON THE CLOCK'),
            ...timed.map(entryCard),
          ],
          if (unscheduled.isNotEmpty) ...[
            sectionLabel('UNSCHEDULED TIME'),
            ...unscheduled.map(entryCard),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => editEntry(),
              icon: const Icon(Icons.add, size: 17),
              label: const Text('Add time to this day'),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Text(
              'Your entries are visible only to you.',
              style: TextStyle(color: muted, fontSize: 10),
            ),
          ),
        ],
      ),
      padding: const EdgeInsets.all(22),
    );
  }

  Widget sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 9,
        letterSpacing: 1.2,
        color: muted,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
  Widget entryCard(TimeRecord entry) {
    final item = store.item(entry.itemId);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: item.color.withValues(alpha: .06),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: () => editEntry(entry),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              border: Border(left: BorderSide(color: item.color, width: 3)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      durationLabel(entry.minutes),
                      style: TextStyle(
                        color: item.color,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  entry.timeLabel(context),
                  style: const TextStyle(color: muted, fontSize: 11),
                ),
                if (entry.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    entry.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: muted, fontSize: 11),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget entriesPage() {
    final rows = store.inMonth(month)..sort((a, b) => b.date.compareTo(a.date));
    return panel(
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 310, child: monthPicker()),
          const Divider(height: 32),
          if (rows.isEmpty)
            const Padding(
              padding: EdgeInsets.all(30),
              child: Text('No entries this month. Start with a small moment.'),
            ),
          for (final day in rows.map((e) => e.date).toSet()) ...[
            sectionLabel(
              DateFormat.yMMMMEEEEd(locale)
                  .format(DateTime.parse(day))
                  .toUpperCase(),
            ),
            ...rows.where((e) => e.date == day).map(entryCard),
            const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget projectsPage() {
    final items =
        store.items
            .where(
              (i) =>
                  i.archived == showArchived &&
                  i.name.toLowerCase().contains(search.toLowerCase()) &&
                  (filter == 'All' ||
                      i.kind ==
                          (filter == 'Projects' ? 'project' : 'activity')),
            )
            .toList()
          ..sort(
            (a, b) => a.pinned != b.pinned
                ? (a.pinned ? -1 : 1)
                : a.name.compareTo(b.name),
          );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          onChanged: (v) => setState(() => search = v),
          decoration: const InputDecoration(
            hintText: 'Find a project or activity…',
            prefixIcon: Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 9,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...['All', 'Projects', 'Activities'].map(
              (label) => ChoiceChip(
                label: Text(label),
                selected: filter == label,
                onSelected: (_) => setState(() => filter = label),
              ),
            ),
            FilterChip(
              label: const Text('Archived'),
              selected: showArchived,
              onSelected: (v) => setState(() => showArchived = v),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (items.isEmpty)
          panel(
            const Text(
              'Nothing here yet. Create a project or activity to get started.',
            ),
          ),
        ...items.map(
          (item) => Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: panel(
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(13),
                    decoration: BoxDecoration(
                      color: item.color.withValues(alpha: .1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(
                      item.kind == 'project'
                          ? Icons.folder_outlined
                          : Icons.repeat,
                      color: item.color,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: InkWell(
                      onTap: () => editItem(item),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.name,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            item.description.isEmpty
                                ? (item.kind == 'project'
                                      ? 'Personal project'
                                      : 'Recurring activity')
                                : item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: item.pinned ? 'Unpin' : 'Pin',
                    onPressed: () => action(
                      () => store.saveItem({
                        ...item.toJson(),
                        'pinned': !item.pinned,
                      }, item.id),
                    ),
                    icon: Icon(
                      item.pinned
                          ? Icons.star_rounded
                          : Icons.star_border_rounded,
                      color: item.pinned ? purple : muted,
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') {
                        editItem(item);
                      } else {
                        action(
                          () => store.saveItem({
                            ...item.toJson(),
                            'archived': !item.archived,
                          }, item.id),
                        );
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('Edit')),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(item.archived ? 'Unarchive' : 'Archive'),
                      ),
                    ],
                  ),
                ],
              ),
              padding: const EdgeInsets.all(20),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> export() async => action(() async {
    message(
      await downloadCsv(await store.csv(month), 'fray-${monthKey(month)}.csv'),
    );
  });
  Widget reportsPage() {
    final rows = store.inMonth(month);
    final totals = <WorkItem, int>{};
    for (final entry in rows) {
      final item = store.item(entry.itemId);
      totals[item] = (totals[item] ?? 0) + entry.minutes;
    }
    final sorted = totals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return Column(
      children: [
        stats(),
        const SizedBox(height: 24),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 310, child: monthPicker()),
              const SizedBox(height: 22),
              const Text(
                'My time',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              const Text(
                'Personal totals by project and activity. Archived items stay in your reports.',
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 30),
              if (sorted.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Text('Your report will take shape as you log time.'),
                ),
              ...sorted.map(
                (row) => Padding(
                  padding: const EdgeInsets.only(bottom: 25),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          Icon(Icons.circle, color: row.key.color, size: 9),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              row.key.name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            durationLabel(row.value),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                      const SizedBox(height: 11),
                      LinearProgressIndicator(
                        value: row.value / total,
                        color: row.key.color,
                        backgroundColor: row.key.color.withValues(alpha: .09),
                        minHeight: 7,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ],
                  ),
                ),
              ),
              const Divider(height: 30),
              Row(
                children: [
                  const Text(
                    'Total time',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  const Spacer(),
                  Text(
                    durationLabel(total),
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Text(
                'CSV exports contain totals in minutes and never include private notes.',
                style: TextStyle(fontSize: 11, color: muted),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget profilePage() => panel(
    Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 30,
          backgroundColor: lavender,
          child: Text(
            store.name!.substring(0, 1).toUpperCase(),
            style: const TextStyle(color: purple, fontSize: 25),
          ),
        ),
        const SizedBox(height: 20),
        Text(store.name!, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(store.email!, style: const TextStyle(color: muted)),
        const Divider(height: 40),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.shield_outlined, color: purple),
          title: Text('Two-factor authentication'),
          subtitle: Text(
            'Real accounts require an authenticator or a single-use recovery code.',
          ),
        ),
        const ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.lock_outline, color: purple),
          title: Text('Private time records'),
          subtitle: Text(
            'Only you can access your projects, entries, notes, and reports.',
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.public, color: purple),
          title: Text('Device time zone: ${store.clock.zone}'),
          subtitle: Text(
            store.clock.detected
                ? 'Dates and times follow your device locale. Saved entries keep the timezone in which they were recorded.'
                : 'The device timezone could not be detected. New timed entries use UTC and show this in the editor.',
          ),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => action(store.signOut),
          icon: const Icon(Icons.logout, size: 17),
          label: Text(store.demo ? 'Leave demo' : 'Sign out'),
        ),
      ],
    ),
  );
}
