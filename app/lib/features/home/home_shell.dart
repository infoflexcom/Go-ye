import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/branding.dart';
import '../../core/models.dart';
import '../auth/auth_controller.dart';

class HomeShell extends ConsumerWidget {
  const HomeShell({required this.session, super.key});

  final Session session;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destinations = <NavigationDestination>[
      const NavigationDestination(icon: Icon(Icons.dashboard_outlined), label: 'Dashboard'),
      const NavigationDestination(icon: Icon(Icons.person_add_alt_1_outlined), label: 'New decision'),
      const NavigationDestination(icon: Icon(Icons.people_outline), label: 'Converts'),
      if (session.roles.any(_canUseUnassignedPool))
        const NavigationDestination(icon: Icon(Icons.assignment_late_outlined), label: 'Unassigned'),
      if (session.isGlobalAdmin)
        const NavigationDestination(icon: Icon(Icons.public_outlined), label: 'Countries'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: <Widget>[GoYeLogo(size: 34), SizedBox(width: 10), Text('Go-Ye')],
        ),
        actions: <Widget>[
          IconButton(
            tooltip: 'Toggle dark mode',
            onPressed: () {
              final current = ref.read(themeModeProvider);
              ref.read(themeModeProvider.notifier).state =
                  current == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark;
            },
            icon: Icon(
              ref.watch(themeModeProvider) == ThemeMode.dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
            ),
          ),
          IconButton(
            tooltip: 'About Go-Ye',
            onPressed: () => showDialog<void>(
              context: context,
              builder: (_) => const AboutGoYeDialog(),
            ),
            icon: const Icon(Icons.info_outline),
          ),
          IconButton(
            tooltip: 'Sign out',
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
              Text('Signed in securely', style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              Text(
                session.roles.isEmpty ? 'No active role is assigned.' : session.roles.join(' · '),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              const Text('Role-aware workspace navigation is ready.'),
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
