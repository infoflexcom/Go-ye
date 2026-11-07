import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_providers.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';

class UnassignedPoolScreen extends ConsumerWidget {
  const UnassignedPoolScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pool = ref.watch(unassignedConvertsProvider);
    return pool.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => Center(
        child: OutlinedButton.icon(
          onPressed: () => ref.invalidate(unassignedConvertsProvider),
          icon: const Icon(Icons.refresh),
          label: Text(context.l10n.text('tryAgain')),
        ),
      ),
      data: (List<UnassignedConvert> values) {
        if (values.isEmpty) {
          return Center(child: Text(context.l10n.text('poolEmpty')));
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: values.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            final convert = values[index];
            return ListTile(
              leading: const Icon(Icons.assignment_late_outlined),
              title: Text(convert.fullName),
              subtitle: Text(
                '${convert.stage.replaceAll('_', ' ')} · ${convert.unassignedAgeDays} ${context.l10n.text('daysWaiting')}',
              ),
              trailing: FilledButton(
                onPressed: () => _showAssignment(context, ref, convert),
                child: Text(context.l10n.text('assign')),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showAssignment(
    BuildContext context,
    WidgetRef ref,
    UnassignedConvert convert,
  ) async {
    final parish = await showDialog<OrgUnit>(
      context: context,
      builder: (_) => const _ParishPickerDialog(),
    );
    if (parish == null || !context.mounted) {
      return;
    }
    try {
      await ref
          .read(convertsRepositoryProvider)
          .assignToParish(convertId: convert.id, parishId: parish.id);
      ref.invalidate(unassignedConvertsProvider);
      ref.invalidate(convertsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${convert.fullName} ${context.l10n.text('assignedTo')} ${parish.name}',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _ParishPickerDialog extends ConsumerWidget {
  const _ParishPickerDialog();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final units = ref.watch(orgUnitsProvider);
    return AlertDialog(
      title: Text(context.l10n.text('assignToParish')),
      content: SizedBox(
        width: 420,
        child: units.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (Object error, StackTrace stackTrace) =>
              Text(context.l10n.text('unitLoadError')),
          data: (List<OrgUnit> values) {
            final parishes = values
                .where((OrgUnit unit) => unit.type == 'PARISH' && unit.isActive)
                .toList();
            if (parishes.isEmpty) {
              return Text(context.l10n.text('noParishAvailable'));
            }
            return ListView.builder(
              shrinkWrap: true,
              itemCount: parishes.length,
              itemBuilder: (BuildContext context, int index) {
                final parish = parishes[index];
                return ListTile(
                  title: Text(parish.name),
                  subtitle: Text(parish.code),
                  onTap: () => Navigator.of(context).pop(parish),
                );
              },
            );
          },
        ),
      ),
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.l10n.close),
        ),
      ],
    );
  }
}
