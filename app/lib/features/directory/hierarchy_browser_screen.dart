import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/models.dart';

class HierarchyBrowserScreen extends ConsumerWidget {
  const HierarchyBrowserScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(orgUnitsProvider);
    return units.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => _LoadError(
        message: 'Could not load the organisation hierarchy.',
        retry: () => ref.invalidate(orgUnitsProvider),
      ),
      data: (List<OrgUnit> values) => ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: values.length,
        separatorBuilder: (_, __) => const Divider(height: 1),
        itemBuilder: (BuildContext context, int index) {
          final unit = values[index];
          final depth = unit.path.split('.').length - 1;
          return Padding(
            padding: EdgeInsetsDirectional.only(start: depth * 16.0),
            child: ListTile(
              leading: Icon(_iconFor(unit.type)),
              title: Text(unit.name),
              subtitle: Text('${unit.type} · ${unit.code}'),
              trailing: unit.isActive
                  ? const Icon(Icons.check_circle_outline, semanticLabel: 'Active')
                  : const Icon(Icons.pause_circle_outline, semanticLabel: 'Inactive'),
            ),
          );
        },
      ),
    );
  }

  IconData _iconFor(String type) {
    return switch (type) {
      'COUNTRY' => Icons.public_outlined,
      'REGION' => Icons.map_outlined,
      'PROVINCE' => Icons.account_tree_outlined,
      'ZONE' => Icons.hub_outlined,
      'AREA' => Icons.location_city_outlined,
      'PARISH' => Icons.church_outlined,
      _ => Icons.business_outlined,
    };
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.retry});

  final String message;
  final VoidCallback retry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton.icon(onPressed: retry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
          ],
        ),
      ),
    );
  }
}
