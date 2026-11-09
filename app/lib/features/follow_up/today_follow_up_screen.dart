import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/api_client.dart';
import '../../core/app_providers.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';

class TodayFollowUpScreen extends ConsumerStatefulWidget {
  const TodayFollowUpScreen({super.key});

  @override
  ConsumerState<TodayFollowUpScreen> createState() =>
      _TodayFollowUpScreenState();
}

class _TodayFollowUpScreenState extends ConsumerState<TodayFollowUpScreen> {
  Timer? _refreshTimer;

  @override
  void initState() {
    super.initState();
    _refreshTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      ref.invalidate(todayFollowUpTasksProvider);
    });
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tasks = ref.watch(todayFollowUpTasksProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(context.l10n.text('todayFollowUp')),
        actions: <Widget>[
          IconButton(
            tooltip: context.l10n.text('refresh'),
            onPressed: () => ref.invalidate(todayFollowUpTasksProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: tasks.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (Object error, StackTrace stackTrace) => _TodayError(
          message: error is ApiException
              ? error.message
              : context.l10n.text('todayLoadError'),
          onRetry: () => ref.invalidate(todayFollowUpTasksProvider),
        ),
        data: (List<FollowUpTask> values) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            unawaited(
              ref
                  .read(deviceNotificationServiceProvider)
                  .syncWindowsTodayTasks(values),
            );
          });
          if (values.isEmpty) {
            return _TodayEmpty(message: context.l10n.text('todayEmpty'));
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(todayFollowUpTasksProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: values.length,
              separatorBuilder: (_, int index) => const SizedBox(height: 10),
              itemBuilder: (BuildContext context, int index) =>
                  _FollowUpTaskCard(
                    task: values[index],
                    onDone: () => _complete(values[index]),
                    onOutcome: () => _completeWithOutcome(values[index]),
                  ),
            ),
          );
        },
      ),
    );
  }

  Future<void> _complete(FollowUpTask task) async {
    try {
      await ref
          .read(followUpRepositoryProvider)
          .complete(task.id, outcome: 'COMPLETED');
      ref.invalidate(todayFollowUpTasksProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_taskLabel(context, task)} ${context.l10n.text('markedDone')}',
            ),
          ),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }

  Future<void> _completeWithOutcome(FollowUpTask task) async {
    final noteController = TextEditingController();
    var outcome = 'COMPLETED';
    final selection =
        await showModalBottomSheet<({String outcome, String? note})>(
          context: context,
          isScrollControlled: true,
          builder: (BuildContext sheetContext) {
            return StatefulBuilder(
              builder: (BuildContext context, StateSetter setSheetState) {
                return Padding(
                  padding: EdgeInsets.fromLTRB(
                    24,
                    24,
                    24,
                    MediaQuery.viewInsetsOf(context).bottom + 24,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Text(
                        context.l10n.text('recordOutcome'),
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                      const SizedBox(height: 16),
                      DropdownButtonFormField<String>(
                        value: outcome,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('outcome'),
                        ),
                        items: _outcomes
                            .map(
                              (String value) => DropdownMenuItem<String>(
                                value: value,
                                child: Text(_outcomeLabel(context, value)),
                              ),
                            )
                            .toList(growable: false),
                        onChanged: (String? value) {
                          if (value != null) {
                            setSheetState(() => outcome = value);
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: noteController,
                        maxLength: 2000,
                        minLines: 2,
                        maxLines: 4,
                        decoration: InputDecoration(
                          labelText: context.l10n.text('noteOptional'),
                          alignLabelWithHint: true,
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton.icon(
                        onPressed: () => Navigator.of(sheetContext).pop((
                          outcome: outcome,
                          note: noteController.text.trim().isEmpty
                              ? null
                              : noteController.text.trim(),
                        )),
                        icon: const Icon(Icons.check),
                        label: Text(context.l10n.text('done')),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
    noteController.dispose();
    if (selection == null) {
      return;
    }
    try {
      await ref
          .read(followUpRepositoryProvider)
          .complete(task.id, outcome: selection.outcome, note: selection.note);
      ref.invalidate(todayFollowUpTasksProvider);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.text('outcomeSaved'))),
        );
      }
    } on ApiException catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(error.message)));
      }
    }
  }
}

class _FollowUpTaskCard extends StatelessWidget {
  const _FollowUpTaskCard({
    required this.task,
    required this.onDone,
    required this.onOutcome,
  });

  final FollowUpTask task;
  final VoidCallback onDone;
  final VoidCallback onOutcome;

  @override
  Widget build(BuildContext context) {
    final due = DateFormat.jm().format(task.dueAt);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    task.convertName,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ),
                Text(due, style: Theme.of(context).textTheme.labelLarge),
              ],
            ),
            const SizedBox(height: 4),
            Text(_taskLabel(context, task)),
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
                  key: ValueKey<String>('follow-up-done-${task.id}'),
                  onPressed: onDone,
                  icon: const Icon(Icons.check_circle_outline),
                  label: Text(context.l10n.text('done')),
                ),
                TextButton(
                  onPressed: onOutcome,
                  child: Text(context.l10n.text('outcomeNote')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _TodayEmpty extends StatelessWidget {
  const _TodayEmpty({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(Icons.task_alt_outlined, size: 56),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _TodayError extends StatelessWidget {
  const _TodayError({required this.message, required this.onRetry});

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
              child: Text(context.l10n.tryAgain),
            ),
          ],
        ),
      ),
    );
  }
}

const List<String> _outcomes = <String>[
  'COMPLETED',
  'NO_CONTACT',
  'RESCHEDULED',
  'DECLINED',
  'OTHER',
];

String _taskLabel(BuildContext context, FollowUpTask task) {
  return switch (task.taskType) {
    'CALL_24H' => context.l10n.text('call24h'),
    'PRAYER_DAY_3' => context.l10n.text('prayerDay3'),
    'VISIT_DAY_7' => context.l10n.text('visitDay7'),
    'WEEKLY_CHECK_IN' => context.l10n.text('weeklyCheckIn'),
    _ => task.taskType,
  };
}

String _outcomeLabel(BuildContext context, String value) {
  return switch (value) {
    'COMPLETED' => context.l10n.text('outcomeCompleted'),
    'NO_CONTACT' => context.l10n.text('outcomeNoContact'),
    'RESCHEDULED' => context.l10n.text('outcomeRescheduled'),
    'DECLINED' => context.l10n.text('outcomeDeclined'),
    'OTHER' => context.l10n.text('outcomeOther'),
    _ => value,
  };
}
