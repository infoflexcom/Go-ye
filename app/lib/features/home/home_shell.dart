import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/branding.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../admin/country_selector_screen.dart';
import '../auth/auth_controller.dart';
import '../directory/hierarchy_browser_screen.dart';

enum _WorkspaceDestination { dashboard, directory, countries }

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({required this.session, super.key});

  final Session session;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  var _selectedIndex = 0;

  @override
  Widget build(BuildContext context) {
    final destinations = <_WorkspaceDestination>[
      _WorkspaceDestination.dashboard,
      _WorkspaceDestination.directory,
      if (widget.session.isGlobalAdmin) _WorkspaceDestination.countries,
    ];
    final selected = destinations[_selectedIndex.clamp(0, destinations.length - 1).toInt()];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[
            const GoYeLogo(size: 34),
            const SizedBox(width: 10),
            Text(context.l10n.appName),
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
            onPressed: () => ref.read(authControllerProvider.notifier).signOut(),
            icon: const Icon(Icons.logout),
          ),
        ],
      ),
      body: switch (selected) {
        _WorkspaceDestination.dashboard => _DashboardWelcome(session: widget.session),
        _WorkspaceDestination.directory => const HierarchyBrowserScreen(),
        _WorkspaceDestination.countries => const CountrySelectorScreen(),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedIndex,
        destinations: destinations.map((destination) => _navigationDestination(context, destination)).toList(),
        onDestinationSelected: (int index) => setState(() => _selectedIndex = index),
      ),
    );
  }

  NavigationDestination _navigationDestination(BuildContext context, _WorkspaceDestination destination) {
    return switch (destination) {
      _WorkspaceDestination.dashboard => NavigationDestination(
          icon: const Icon(Icons.dashboard_outlined),
          label: context.l10n.dashboard,
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
}

class _DashboardWelcome extends StatelessWidget {
  const _DashboardWelcome({required this.session});

  final Session session;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.verified_user_outlined, size: 56),
            const SizedBox(height: 16),
            Text(context.l10n.signedInSecurely, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 8),
            Text(
              session.roles.isEmpty ? context.l10n.noActiveRole : session.roles.join(' · '),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Text(context.l10n.workspaceReady),
          ],
        ),
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
      onSelected: (Locale value) => ref.read(localeProvider.notifier).state = value,
      itemBuilder: (BuildContext context) => <PopupMenuEntry<Locale>>[
        PopupMenuItem<Locale>(value: const Locale('en'), child: Text(context.l10n.english)),
        PopupMenuItem<Locale>(value: const Locale('yo'), child: Text(context.l10n.yoruba)),
      ],
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(locale.languageCode.toUpperCase()),
      ),
    );
  }
}
