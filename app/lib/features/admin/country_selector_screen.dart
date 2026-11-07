import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/app_providers.dart';
import '../../core/models.dart';

class CountrySelectorScreen extends ConsumerWidget {
  const CountrySelectorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final countries = ref.watch(countriesProvider);
    final selected = ref.watch(selectedCountryProvider);
    return countries.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (Object error, StackTrace stackTrace) => Center(
        child: OutlinedButton.icon(
          onPressed: () => ref.invalidate(countriesProvider),
          icon: const Icon(Icons.refresh),
          label: const Text('Retry country list'),
        ),
      ),
      data: (List<SummaryTotal> values) => ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text(
            'Select a country',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          const Text('Country totals are scoped to the Global Admin role.'),
          const SizedBox(height: 16),
          for (final country in values)
            Card(
              child: RadioListTile<SummaryTotal>(
                value: country,
                groupValue: selected,
                onChanged: (SummaryTotal? value) {
                  ref.read(selectedCountryProvider.notifier).state = value;
                },
                title: Text(country.name),
                subtitle: Text(country.code),
                secondary: _TotalChip(total: country.total),
              ),
            ),
          if (selected != null) ...<Widget>[
            const SizedBox(height: 16),
            _RegionTotals(country: selected),
          ],
        ],
      ),
    );
  }
}

class _TotalChip extends StatelessWidget {
  const _TotalChip({required this.total});

  final int total;

  @override
  Widget build(BuildContext context) {
    return Chip(label: Text('$total'));
  }
}

class _RegionTotals extends ConsumerWidget {
  const _RegionTotals({required this.country});

  final SummaryTotal country;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final regions = ref.watch(regionTotalsProvider(country.id));
    return regions.when(
      loading: () => const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: CircularProgressIndicator(),
        ),
      ),
      error: (Object error, StackTrace stackTrace) =>
          const Text('Could not load regions.'),
      data: (List<SummaryTotal> values) => Card(
        child: Column(
          children: <Widget>[
            ListTile(
              title: Text('${country.name} regions'),
              trailing: _TotalChip(total: country.total),
            ),
            for (final region in values)
              ListTile(
                title: Text(region.name),
                subtitle: Text(region.code),
                trailing: _TotalChip(total: region.total),
              ),
          ],
        ),
      ),
    );
  }
}
