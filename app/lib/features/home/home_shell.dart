import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/branding.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../auth/auth_controller.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({required this.session, super.key});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = <NavigationDestination>[
      NavigationDestination(icon: const Icon(Icons.dashboard_outlined), label: context.l10n.dashboard),
      NavigationDestination(icon: const Icon(Icons.person_add_alt_1_outlined), label: context.l10n.newDecision),
      NavigationDestination(icon: const Icon(Icons.people_outline), label: context.l10n.converts),
      if (session.roles.any(_canUseUnassignedPool))
        NavigationDestination(icon: const Icon(Icons.assignment_late_outlined), label: context.l10n.unassigned),
      if (session.isGlobalAdmin)
        NavigationDestination(icon: const Icon(Icons.public_outlined), label: context.l10n.countries),
    ];

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: <Widget>[const GoYeLogo(size: 34), const SizedBox(width: 10), Text(context.l10n.appName)],
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
      body: Center(
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
      ),
      bottomNavigationBar: destinations.length > 1
          ? NavigationBar(
              selectedIndex: 0,
              destinations: destinations,
              onDestinationSelected: (_) {},
            )
          : null,
    );
  }

  static bool _canUseUnassignedPool(String role) {
    return <String>{
      'GLOBAL_ADMIN',
      'COUNTRY_ADMIN',
      'REGION_LEADER',
      'PROVINCE_LEADER',
      'ZONE_LEADER',
      'AREA_LEADER',
    }.contains(role);
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
