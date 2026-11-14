import '../l10n/localization.dart';
import 'preferences.dart';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'time_context.dart';

import 'data.dart';
import 'editors.dart';
import 'download.dart';
import 'auth_screen.dart';

const brandPurple = Color(0xFF7153E8);

class FrayApp extends StatefulWidget {
  final FrayStore? store;
  final AppPreferences? preferences;
  const FrayApp({super.key, this.store, this.preferences});
  @override
  State<FrayApp> createState() => _FrayAppState();
}

class _FrayAppState extends State<FrayApp> with WidgetsBindingObserver {
  late final AppPreferences preferences =
      widget.preferences ?? AppPreferences();
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
    if (widget.preferences == null) preferences.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PreferencesScope(
    preferences: preferences,
    child: ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => MaterialApp(
        title: 'Fray',
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('sl'), Locale('hr')],
        locale: preferences.language == 'system'
            ? null
            : Locale(preferences.language),
        localeListResolutionCallback: (locales, supported) =>
            preferences.resolve(locales),
        themeMode: preferences.themeMode,
        theme: frayTheme(Brightness.light),
        darkTheme: frayTheme(Brightness.dark),
        builder: (context, child) {
          store.language = Localizations.localeOf(context).languageCode;
          return child!;
        },
        home: ListenableBuilder(
          listenable: store,
          builder: (context, _) => store.name == null
              ? LoginScreen(store: store)
              : Workspace(key: ValueKey(store.demo), store: store),
        ),
      ),
    ),
  );
}

ThemeData frayTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(
    seedColor: brandPurple,
    brightness: brightness,
    primary: dark ? const Color(0xFFC9B8FF) : brandPurple,
    primaryContainer: dark ? const Color(0xFF35294F) : const Color(0xFFF1EDFC),
    surface: dark ? const Color(0xFF211D2B) : Colors.white,
    onSurface: dark ? const Color(0xFFEAE4F3) : const Color(0xFF28233E),
    onSurfaceVariant: dark ? const Color(0xFFC5BDD2) : const Color(0xFF6D667A),
    outlineVariant: dark ? const Color(0xFF494152) : const Color(0xFFECE9F3),
  );
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    fontFamily: 'Roboto',
  );
  return base.copyWith(
    scaffoldBackgroundColor: dark
        ? const Color(0xFF17131E)
        : const Color(0xFFFAF9FD),
    textTheme: base.textTheme.copyWith(
      headlineMedium: base.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -1,
      ),
      titleLarge: base.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w700,
      ),
      bodyMedium: base.textTheme.bodyMedium?.copyWith(height: 1.4),
    ),
    dividerColor: scheme.outlineVariant,
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? const Color(0xFF292332) : const Color(0xFFFAF9FD),
      helperMaxLines: 3,
      errorMaxLines: 3,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 19),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
          color: brandPurple,
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Icon(
          Icons.calendar_month_rounded,
          color: Colors.white,
          size: 23,
        ),
      ),
      const SizedBox(width: 11),
      Text(
        'Fray',
        style: TextStyle(
          fontSize: 29,
          fontWeight: FontWeight.w800,
          letterSpacing: -1,
          color: context.ink,
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

class _WorkspaceState extends State<Workspace> with LocalizedState {
  int tab = 0;
  late DateTime selected = DateUtils.dateOnly(store.clock.now());
  late DateTime month = DateTime(selected.year, selected.month);
  String search = '', filter = 'All';
  bool showArchived = false, loading = false;
  String? loadError;
  int loadSequence = 0;
  FrayStore get store => widget.store;
  List<String> get labels => [
    tr('Calendar'),
    tr('Entries'),
    tr('Projects'),
    tr('Reports'),
    tr('Profile'),
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
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(tr(text))));
    }
  }

  Future<void> action(Future<void> Function() run) async {
    try {
      await run();
    } catch (e) {
      message(tr(e.toString()));
    }
  }

  Future<void> editEntry([TimeRecord? entry]) async {
    if (!store.items.any((i) => !i.archived)) {
      message(tr('Create a project or activity first.'));
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
          color: context.surface,
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
                    decoration: BoxDecoration(
                      color: context.surface,
                      border: Border(bottom: BorderSide(color: line)),
                    ),
                    child: Row(
                      children: [
                        if (!wide)
                          const Brand()
                        else
                          Text(
                            tr('My workspace  /  {page}', {
                              'page': labels[tab],
                            }),
                            style: TextStyle(color: muted),
                          ),
                        const Spacer(),
                        Icon(Icons.lock_outline, color: muted, size: 16),
                        const SizedBox(width: 7),
                        if (wide)
                          Text(
                            tr('Personal workspace'),
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        const SizedBox(width: 20),
                        CircleAvatar(
                          radius: 17,
                          backgroundColor: lavender,
                          child: Text(
                            store.name!.substring(0, 1).toUpperCase(),
                            style: TextStyle(color: purple, fontSize: 13),
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
                      child: Text(
                        tr(
                          'Demo workspace · Try adding and editing time. Changes reset when you leave.',
                        ),
                        style: TextStyle(color: purple, fontSize: 12),
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
                                        tr(loadError!),
                                        style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error,
                                        ),
                                      ),
                                      TextButton(
                                        onPressed: load,
                                        child: Text(tr('Retry')),
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
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.spa_outlined,
                                    size: 15,
                                    color: muted,
                                  ),
                                  const SizedBox(width: 8),
                                  Flexible(
                                    child: Text(
                                      tr('A little progress, every day.'),
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
    decoration: BoxDecoration(
      color: context.surface,
      border: Border(right: BorderSide(color: line)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Brand(),
        const SizedBox(height: 47),
        Padding(
          padding: const EdgeInsets.only(left: 13, bottom: 15),
          child: Text(
            tr('WORKSPACE'),
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                  child: Row(
                    children: [
                      Icon(
                        icons[i],
                        size: 21,
                        color: i == tab ? purple : muted,
                      ),
                      const SizedBox(width: 13),
                      Expanded(
                        child: Text(
                          labels[i],
                          style: TextStyle(
                            color: i == tab ? purple : muted,
                            fontWeight: i == tab
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
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
            color: lavender,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.auto_awesome_outlined, color: purple, size: 24),
              const SizedBox(height: 12),
              Text(
                tr('Make room for focus.'),
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              const SizedBox(height: 7),
              Text(
                tr('Notice where your time goes. Make space for what matters.'),
                style: TextStyle(fontSize: 12, color: muted, height: 1.6),
              ),
            ],
          ),
        ),
        const SizedBox(height: 22),
        Center(
          child: Text(
            tr('FRAY  /  TIME WELL SPENT'),
            style: TextStyle(fontSize: 9, color: muted, letterSpacing: 1.2),
          ),
        ),
      ],
    ),
  );

  Widget heading(bool wide) {
    final titles = [
      tr('Your time, at a glance.'),
      tr('Small moments. Real progress.'),
      tr('Space for every kind of work.'),
      tr('See the bigger picture.'),
      tr('Your own quiet corner.'),
    ];
    final subtitles = [
      tr('A clear view of your days, with room for what matters.'),
      tr('Everything you’ve worked on, one entry at a time.'),
      tr('Organize projects and the activities you come back to.'),
      tr('A thoughtful look at where your time went.'),
      tr('Your workspace and account security.'),
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
                style: TextStyle(
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
                style: TextStyle(color: muted, fontSize: 13),
              ),
            ],
          ),
        ),
        if (tab < 2)
          FilledButton.icon(
            onPressed: loading ? null : () => editEntry(),
            icon: const Icon(Icons.add, size: 19),
            label: Text(tr('Add entry')),
          ),
        if (tab == 2)
          FilledButton.icon(
            onPressed: () => editItem(),
            icon: const Icon(Icons.add, size: 19),
            label: Text(tr('New project / activity')),
          ),
        if (tab == 3)
          FilledButton.icon(
            onPressed: export,
            icon: const Icon(Icons.file_download_outlined, size: 19),
            label: Text(tr('Export CSV')),
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
              tr('TIME THIS MONTH'),
              context.duration(total),
              Icons.schedule_outlined,
              compact,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: stat(
              tr('DAYS WITH ENTRIES'),
              '$days',
              Icons.calendar_today_outlined,
              compact,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: stat(
              tr('ITEMS WORKED ON'),
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
        tooltip: tr('Previous month'),
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
        tooltip: tr('Next month'),
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
              child: Text(tr('Today')),
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
                          style: TextStyle(
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
                  label: tr('Select {date}', {
                    'date': DateFormat.yMMMMEEEEd(locale).format(day),
                  }),
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
                            ? lavender.withValues(alpha: .4)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: active
                              ? purple.withValues(alpha: .6)
                              : line.withValues(alpha: .5),
                        ),
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 8),
                      child: Column(
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              color: day.month != month.month
                                  ? muted.withValues(alpha: .6)
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
                              context.duration(
                                records.fold(0, (s, e) => s + e.minutes),
                              ),
                              style: TextStyle(fontSize: 9, color: muted),
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
        Row(
          children: [
            Icon(Icons.circle, size: 7, color: purple),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                tr(
                  'Each color is a project or activity. Select a day to see your time.',
                ),
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
            style: TextStyle(color: muted, fontSize: 10, letterSpacing: 1.5),
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
                Expanded(
                  child: Text(
                    tr('Total tracked'),
                    style: TextStyle(color: purple, fontSize: 12),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  context.duration(rows.fold(0, (s, e) => s + e.minutes)),
                  style: TextStyle(fontWeight: FontWeight.w700, color: purple),
                ),
              ],
            ),
          ),
          const SizedBox(height: 23),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 25),
              child: Text(
                tr(
                  'A little space in your day.\nAdd your first entry when you’re ready.',
                ),
                style: TextStyle(color: muted, height: 1.8),
              ),
            ),
          if (timed.isNotEmpty) ...[
            sectionLabel(tr('ON THE CLOCK')),
            ...timed.map(entryCard),
          ],
          if (unscheduled.isNotEmpty) ...[
            sectionLabel(tr('UNSCHEDULED TIME')),
            ...unscheduled.map(entryCard),
          ],
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => editEntry(),
              icon: const Icon(Icons.add, size: 17),
              label: Text(tr('Add time to this day')),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              tr('Your entries are visible only to you.'),
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
      style: TextStyle(
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
              border: Border(
                left: BorderSide(color: context.accent(item.color), width: 3),
              ),
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
                      context.duration(entry.minutes),
                      style: TextStyle(
                        color: context.accent(item.color),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Text(
                  entry.timeLabel(context),
                  style: TextStyle(color: muted, fontSize: 11),
                ),
                if (entry.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    entry.notes,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: muted, fontSize: 11),
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
            Padding(
              padding: const EdgeInsets.all(30),
              child: Text(
                tr('No entries this month. Start with a small moment.'),
              ),
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
          decoration: InputDecoration(
            hintText: tr('Find a project or activity…'),
            prefixIcon: const Icon(Icons.search),
          ),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 9,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            ...['All', 'Projects', 'Activities'].map(
              (label) => ChoiceChip(
                label: Text(tr(label)),
                selected: filter == label,
                onSelected: (_) => setState(() => filter = label),
              ),
            ),
            FilterChip(
              label: Text(tr('Archived')),
              selected: showArchived,
              onSelected: (v) => setState(() => showArchived = v),
            ),
          ],
        ),
        const SizedBox(height: 22),
        if (items.isEmpty)
          panel(
            Text(
              tr(
                'Nothing here yet. Create a project or activity to get started.',
              ),
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
                      color: context.accent(item.color),
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
                                      ? tr('Personal project')
                                      : tr('Recurring activity'))
                                : item.description,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: muted, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: item.pinned ? tr('Unpin') : tr('Pin'),
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
                      PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                      PopupMenuItem(
                        value: 'archive',
                        child: Text(
                          item.archived ? tr('Unarchive') : tr('Archive'),
                        ),
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
              Text(
                tr('My time'),
                style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 7),
              Text(
                tr(
                  'Personal totals by project and activity. Archived items stay in your reports.',
                ),
                style: TextStyle(color: muted, fontSize: 12),
              ),
              const SizedBox(height: 30),
              if (sorted.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    tr('Your report will take shape as you log time.'),
                  ),
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
                              style: const TextStyle(fontWeight: FontWeight.w500),
                            ),
                          ),
                          Text(
                            context.duration(row.value),
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
                  Expanded(
                    child: Text(
                      tr('Total time'),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    context.duration(total),
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: purple,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Text(
                tr(
                  'CSV exports contain totals in minutes and never include private notes.',
                ),
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
            style: TextStyle(color: purple, fontSize: 25),
          ),
        ),
        const SizedBox(height: 20),
        Text(store.name!, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 5),
        Text(
          store.demo ? tr('Demo workspace') : store.email!,
          style: TextStyle(color: muted),
        ),
        const Divider(height: 40),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.shield_outlined, color: purple),
          title: Text(tr('Two-factor authentication')),
          subtitle: Text(
            tr(
              'Real accounts require an authenticator or a single-use recovery code.',
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.lock_outline, color: purple),
          title: Text(tr('Private time records')),
          subtitle: Text(
            tr(
              'Only you can access your projects, entries, notes, and reports.',
            ),
          ),
        ),
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.public, color: purple),
          title: Text(
            tr('Device time zone: {zone}', {'zone': store.clock.zone}),
          ),
          subtitle: Text(
            store.clock.detected
                ? tr(
                    'Dates follow your selected language. Times follow your device clock preference. Saved entries keep their original timezone.',
                  )
                : tr(
                    'The device timezone could not be detected. New timed entries use UTC and show this in the editor.',
                  ),
          ),
        ),
        const Divider(height: 40),
        const PreferencesPanel(),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => action(store.signOut),
          icon: const Icon(Icons.logout, size: 17),
          label: Text(store.demo ? tr('Leave demo') : tr('Sign out')),
        ),
      ],
    ),
  );
}
