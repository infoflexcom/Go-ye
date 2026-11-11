import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api_client.dart';
import '../../core/app_providers.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';
import '../converts/converts_list_screen.dart';

/// Supervisor-only follow-up risk views. The API remains the source of truth:
/// each refresh recomputes overdue and neglected status from pending tasks.
class FollowUpRisksScreen extends StatelessWidget {
  const FollowUpRisksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: Text(context.l10n.text('followUpRisks')),
          bottom: TabBar(
            tabs: <Widget>[
              Tab(text: context.l10n.text('escalations')),
              Tab(text: context.l10n.text('neglected')),
            ],
          ),
        ),
        body: const TabBarView(
          children: <Widget>[_EscalationsList(), _NeglectedConvertsList()],
        ),
      ),
    );
  }
}

class _EscalationsList extends ConsumerWidget {
  const _EscalationsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(followUpEscalationsProvider);
    return page.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => _RiskError(
        message: error is ApiException
            ? error.message
            : context.l10n.text('followUpRiskLoadError'),
        onRetry: () => ref.invalidate(followUpEscalationsProvider),
      ),
      data: (FollowUpRiskPage<OverdueFollowUpTask> value) {
        if (value.items.isEmpty) {
          return _RiskEmpty(
            icon: Icons.verified_user_outlined,
            message: context.l10n.text('escalationsEmpty'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(followUpEscalationsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: value.items.length + 1,
            separatorBuilder: (_, int index) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return Text(
                  '${value.total} ${context.l10n.text('overdueEscalations')}',
                  style: Theme.of(context).textTheme.titleMedium,
                );
              }
              return _EscalationCard(item: value.items[index - 1]);
            },
          ),
        );
      },
    );
  }
}

class _EscalationCard extends ConsumerWidget {
  const _EscalationCard({required this.item});

  final OverdueFollowUpTask item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final task = item.task;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              task.convertName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text('${_taskLabel(context, task.taskType)} · ${item.parishName}'),
            const SizedBox(height: 4),
            Text(
              _elapsedLabel(context, item.overdueMinutes),
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.error,
                  ),
            ),
            if (task.phone != null) ...<Widget>[
              const SizedBox(height: 4),
              Text(task.phone!, style: Theme.of(context).textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: <Widget>[
                FilledButton.icon(
                  key: ValueKey<String>('escalation-done-${task.id}'),
                  onPressed: () => _complete(context, ref),
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(context.l10n.text('done')),
                ),
                TextButton(
                  onPressed: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ConvertDetailScreen(convertId: task.convertId),
                    ),
                  ),
                  child: Text(context.l10n.text('convertDetail')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _complete(BuildContext context, WidgetRef ref) async {
    try {
      await ref
          .read(followUpRepositoryProvider)
          .complete(item.task.id, outcome: 'COMPLETED');
      ref.invalidate(followUpEscalationsProvider);
      ref.invalidate(neglectedConvertsProvider);
      ref.invalidate(todayFollowUpTasksProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('escalationResolved'))),
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

class _NeglectedConvertsList extends ConsumerWidget {
  const _NeglectedConvertsList();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final page = ref.watch(neglectedConvertsProvider);
    return page.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => _RiskError(
        message: error is ApiException
            ? error.message
            : context.l10n.text('followUpRiskLoadError'),
        onRetry: () => ref.invalidate(neglectedConvertsProvider),
      ),
      data: (FollowUpRiskPage<NeglectedConvert> value) {
        if (value.items.isEmpty) {
          return _RiskEmpty(
            icon: Icons.volunteer_activism_outlined,
            message: context.l10n.text('neglectedEmpty'),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(neglectedConvertsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: value.items.length + 1,
            separatorBuilder: (_, int index) => const SizedBox(height: 10),
            itemBuilder: (BuildContext context, int index) {
              if (index == 0) {
                return Text(
                  '${value.total} ${context.l10n.text('neglectedConverts')}',
                  style: Theme.of(context).textTheme.titleMedium,
                );
              }
              final convert = value.items[index - 1];
              return Card(
                child: ListTile(
                  leading: const Icon(Icons.person_search_outlined),
                  title: Text(convert.convertName),
                  subtitle: Text(
                    <String>[
                      '${_taskLabel(context, convert.oldestOverdueTaskType)} · ${convert.parishName}',
                      '${_elapsedLabel(context, convert.neglectedForMinutes)} · ${convert.overdueTaskCount} ${context.l10n.text('overdueTasks')}',
                      if (convert.phone != null) convert.phone!,
                    ].join('\n'),
                  ),
                  isThreeLine: convert.phone != null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          ConvertDetailScreen(convertId: convert.convertId),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}

class _RiskEmpty extends StatelessWidget {
  const _RiskEmpty({required this.icon, required this.message});

  final IconData icon;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 56),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _RiskError extends StatelessWidget {
  const _RiskError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(context.l10n.text('tryAgain')),
            ),
          ],
        ),
      ),
    );
  }
}

String _taskLabel(BuildContext context, String taskType) {
  return switch (taskType) {
    'CALL_24H' => context.l10n.text('call24h'),
    'PRAYER_DAY_3' => context.l10n.text('prayerDay3'),
    'VISIT_DAY_7' => context.l10n.text('visitDay7'),
    'WEEKLY_CHECK_IN' => context.l10n.text('weeklyCheckIn'),
    _ => taskType,
  };
}

String _elapsedLabel(BuildContext context, int minutes) {
  final days = minutes ~/ (24 * 60);
  final hours = (minutes % (24 * 60)) ~/ 60;
  if (days > 0) {
    return '$days${context.l10n.text('shortDays')} $hours${context.l10n.text('shortHours')} ${context.l10n.text('overdue')}';
  }
  if (hours > 0) {
    return '$hours${context.l10n.text('shortHours')} ${context.l10n.text('overdue')}';
  }
  return '$minutes${context.l10n.text('shortMinutes')} ${context.l10n.text('overdue')}';
}
