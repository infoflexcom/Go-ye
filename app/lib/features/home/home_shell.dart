import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/branding.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../admin/country_selector_screen.dart';
import '../auth/auth_controller.dart';
import '../directory/hierarchy_browser_screen.dart';
import '../converts/converts_list_screen.dart';
import '../converts/new_decision_screen.dart';
import '../converts/unassigned_pool_screen.dart';
import '../follow_up/today_follow_up_screen.dart';

enum _WorkspaceDestination {
  dashboard,
  today,
  newDecision,
  converts,
  unassigned,
  directory,
  countries,
}

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.session, super.key});

  final Session session;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  var _selectedIndex = 0;
  Timer? _windowsNotificationSync;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startPlatformNotifications();
    });
  }

  @override
  void dispose() {
    _windowsNotificationSync?.cancel();
    super.dispose();
  }

  void _startPlatformNotifications() {
    if (Platform.isAndroid) {
      unawaited(ref.read(deviceNotificationServiceProvider).initialize());
      if (_canFollowUpWork(widget.session)) {
        unawaited(
          ref
              .read(pushNotificationRegistrationProvider)
              .registerAndroidDevice(),
        );
      }
    }
    if (Platform.isWindows && _canFollowUpWork(widget.session)) {
      unawaited(_syncWindowsFollowUpNotifications());
      _windowsNotificationSync = Timer.periodic(
        const Duration(minutes: 1),
        (_) {
          unawaited(_syncWindowsFollowUpNotifications());
        },
      );
    }
  }

  Future<void> _syncWindowsFollowUpNotifications() async {
    if (!mounted) {
      return;
    }
    try {
      final tasks = await ref.read(followUpRepositoryProvider).listToday();
      await ref
          .read(deviceNotificationServiceProvider)
          .syncWindowsTodayTasks(tasks);
    } on Object {
      // Windows keeps the authenticated Today screen available for an explicit retry.
    }
  }

  @override
  Widget build(BuildContext context) {
    final destinations = <_WorkspaceDestination>[
      _WorkspaceDestination.dashboard,
      if (_canFollowUpWork(widget.session)) _WorkspaceDestination.today,
      if (_canRegisterConverts(widget.session))
        _WorkspaceDestination.newDecision,
      if (_canRegisterConverts(widget.session)) _WorkspaceDestination.converts,
      if (_canUseUnassignedPool(widget.session))
        _WorkspaceDestination.unassigned,
      _WorkspaceDestination.directory,
      if (widget.session.isGlobalAdmin) _WorkspaceDestination.countries,
    ];
    final selected =
        destinations[_selectedIndex.clamp(0, destinations.length - 1).toInt()];

    final desktopLayout = MediaQuery.sizeOf(context).width >= 800;
    final content = switch (selected) {
      _WorkspaceDestination.dashboard => _DashboardWelcome(
          session: widget.session,
        ),
      _WorkspaceDestination.today => const TodayFollowUpScreen(),
      _WorkspaceDestination.newDecision => NewDecisionScreen(
          isGlobalAdmin: widget.session.isGlobalAdmin,
        ),
      _WorkspaceDestination.converts => const ConvertsListScreen(),
      _WorkspaceDestination.unassigned => const UnassignedPoolScreen(),
      _WorkspaceDestination.directory => const HierarchyBrowserScreen(),
      _WorkspaceDestination.countries => const CountrySelectorScreen(),
    };

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            const GoYeLogo(size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                context.l10n.appName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        actions: <Widget>[
          _LanguageButton(ref: ref),
          IconButton(
            tooltip: context.l10n.toggleDarkMode,
            onPressed: () {
              final current = ref.read(themeModeProvider);
              ref.read(themeModeProvider.notifier).state =
                  current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            },
            icon: Icon(
              ref.watch(themeModeProvider) == ThemeMode.dark
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            tooltip: context.l10n.about,
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AboutGoYeDialog(),
            ),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: context.l10n.signOut,
            onPressed: () =>
                ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: desktopLayout
          ? Row(
              children: <Widget>[
                NavigationRail(
                  extended: MediaQuery.sizeOf(context).width >= 1100,
                  selectedIndex: _selectedIndex,
                  labelType: MediaQuery.sizeOf(context).width >= 1100
                      ? null
                      : NavigationRailLabelType.all,
                  destinations: destinations
                      .map(
                        (destination) =>
                            _navigationRailDestination(context, destination),
                      )
                      .toList(growable: false),
                  onDestinationSelected: (int index) =>
                      setState(() => _selectedIndex = index),
                ),
                const VerticalDivider(width: 1),
                Expanded(child: content),
              ],
            )
          : content,
      bottomNavigationBar: desktopLayout
          ? null
          : NavigationBar(
              selectedIndex: _selectedIndex,
              destinations: destinations
                  .map(
                    (destination) =>
                        _navigationDestination(context, destination),
                  )
                  .toList(),
              onDestinationSelected: (int index) =>
                  setState(() => _selectedIndex = index),
            ),
    );
  }

  NavigationDestination _navigationDestination(
    BuildContext context,
    _WorkspaceDestination destination,
  ) {
    return switch (destination) {
      _WorkspaceDestination.dashboard => NavigationDestination(
          icon: const Icon(Icons.dashboard_outlined),
          label: context.l10n.dashboard,
        ),
      _WorkspaceDestination.today => NavigationDestination(
          icon: const Icon(Icons.today_outlined),
          label: context.l10n.text('todayFollowUp'),
        ),
      _WorkspaceDestination.newDecision => NavigationDestination(
          icon: const Icon(Icons.person_add_alt_1_outlined),
          label: context.l10n.newDecision,
        ),
      _WorkspaceDestination.converts => NavigationDestination(
          icon: const Icon(Icons.people_outline),
          label: context.l10n.converts,
        ),
      _WorkspaceDestination.unassigned => NavigationDestination(
          icon: const Icon(Icons.assignment_late_outlined),
          label: context.l10n.unassigned,
        ),
      _WorkspaceDestination.directory => NavigationDestination(
          icon: const Icon(Icons.account_tree_outlined),
          label: context.l10n.text('hierarchy'),
        ),
      _WorkspaceDestination.countries => NavigationDestination(
          icon: const Icon(Icons.public_outlined),
          label: context.l10n.countries,
        ),
    };
  }

  NavigationRailDestination _navigationRailDestination(
    BuildContext context,
    _WorkspaceDestination destination,
  ) {
    final navigation = _navigationDestination(context, destination);
    return NavigationRailDestination(
      icon: navigation.icon,
      label: Text(navigation.label),
    );
  }

  bool _canFollowUpWork(Session session) {
    const followUpRoles = <String>{
      'COUNTRY_ADMIN',
      'REGION_LEADER',
      'PROVINCE_LEADER',
      'ZONE_LEADER',
      'AREA_LEADER',
      'PARISH_PASTOR',
      'SOUL_WINNER',
      'FOLLOW_UP_WORKER',
    };
    return session.isGlobalAdmin || session.roles.any(followUpRoles.contains);
  }

  bool _canRegisterConverts(Session session) {
    const convertRoles = <String>{
      'COUNTRY_ADMIN',
      'REGION_LEADER',
      'PROVINCE_LEADER',
      'ZONE_LEADER',
      'AREA_LEADER',
      'PARISH_PASTOR',
      'SOUL_WINNER',
      'FOLLOW_UP_WORKER',
    };
    return session.isGlobalAdmin || session.roles.any(convertRoles.contains);
  }

  bool _canUseUnassignedPool(Session session) {
    const poolRoles = <String>{
      'COUNTRY_ADMIN',
      'REGION_LEADER',
      'PROVINCE_LEADER',
      'ZONE_LEADER',
      'AREA_LEADER',
    };
    return session.isGlobalAdmin || session.roles.any(poolRoles.contains);
  }
}

class _DashboardWelcome extends ConsumerWidget {
  const _DashboardWelcome({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(scopedCountProvider(session));
    return ListView(
      padding: const EdgeInsets.all(24),
      children: <Widget>[
        const Icon(Icons.verified_user_outlined, size: 56),
        const SizedBox(height: 16),
        Text(
          context.l10n.signedInSecurely,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          session.roles.isEmpty
              ? context.l10n.noActiveRole
              : session.roles.join(' · '),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),
        count.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (Object error, StackTrace stackTrace) =>
              _CountUnavailable(message: context.l10n.text('countUnavailable')),
          data: (ScopedCount? value) => value == null
              ? _CountUnavailable(
                  message: context.l10n.text('countUnavailable'),
                )
              : _CountCard(count: value),
        ),
      ],
    );
  }
}

class _CountCard extends StatelessWidget {
  const _CountCard({required this.count});

  final ScopedCount count;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              count.scopeName ?? context.l10n.text('yourScope'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              '${count.total}',
              style: Theme.of(context).textTheme.displaySmall,
            ),
            Text(context.l10n.text('activeConverts')),
            if (count.byStage.isNotEmpty) ...<Widget>[
              const Divider(height: 32),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: count.byStage.entries
                    .map(
                      (MapEntry<String, int> entry) => Chip(
                        label: Text(
                          '${entry.key.replaceAll('_', ' ')} · ${entry.value}',
                        ),
                      ),
                    )
                    .toList(growable: false),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CountUnavailable extends StatelessWidget {
  const _CountUnavailable({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _LanguageButton extends StatelessWidget {
  const _LanguageButton({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return PopupMenuButton<Locale>(
      tooltip: context.l10n.language,
      initialValue: locale,
      onSelected: (Locale value) =>
          ref.read(localeProvider.notifier).state = value,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Locale>>[
        PopupMenuItem<Locale>(
          value: const Locale('en'),
          child: Text(context.l10n.english),
        ),
        PopupMenuItem<Locale>(
          value: const Locale('yo'),
          child: Text(context.l10n.yoruba),
        ),
      ],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(locale.languageCode.toUpperCase()),
      ),
    );
  }
}
