import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/models.dart';
import '../../l10n/app_localizations.dart';

class ConvertsListScreen extends ConsumerWidget {
  const ConvertsListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final converts = ref.watch(convertsProvider);
    return converts.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => Center(
        child: OutlinedButton.icon(
          onPressed: () => ref.invalidate(convertsProvider),
          icon: const Icon(Icons.refresh),
          label: Text(context.l10n.text('tryAgain')),
        ),
      ),
      data: (ConvertPage page) => RefreshIndicator(
        onRefresh: () async => ref.invalidate(convertsProvider),
        child: ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: page.items.length + 1,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (BuildContext context, int index) {
            if (index == 0) {
              return ListTile(
                title: Text(context.l10n.converts),
                subtitle: Text('${page.total} ${context.l10n.text('visibleRecords')}'),
              );
            }
            final convert = page.items[index - 1];
            return ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(convert.fullName),
              subtitle: Text('${_stageName(convert.stage)}${convert.phone == null ? '' : ' · ${convert.phone}'}'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).push<void>(
                MaterialPageRoute<void>(builder: (_) => ConvertDetailScreen(convertId: convert.id)),
              ),
            );
          },
        ),
      ),
    );
  }

  String _stageName(String value) => value.replaceAll('_', ' ');
}

class ConvertDetailScreen extends ConsumerWidget {
  const ConvertDetailScreen({required this.convertId, super.key});

  final String convertId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text(context.l10n.text('convertDetail'))),
      body: FutureBuilder<ConvertRecord>(
        future: ref.watch(convertsRepositoryProvider).get(convertId),
        builder: (BuildContext context, AsyncSnapshot<ConvertRecord> snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return Center(child: Text(context.l10n.text('convertLoadError')));
          }
          final convert = snapshot.data!;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: <Widget>[
              Text(convert.fullName, style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 16),
              _DetailRow(label: context.l10n.text('stage'), value: convert.stage.replaceAll('_', ' ')),
              _DetailRow(label: context.l10n.text('phone'), value: convert.phone ?? '—'),
              _DetailRow(label: context.l10n.text('address'), value: convert.address ?? '—'),
              _DetailRow(label: context.l10n.text('parish'), value: convert.parishId ?? context.l10n.text('notAssigned')),
            ],
          );
        },
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(width: 104, child: Text(label, style: Theme.of(context).textTheme.labelLarge)),
          Expanded(child: SelectableText(value)),
        ],
      ),
    );
  }
}
