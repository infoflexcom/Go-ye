import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';
import '../features/admin/admin_reports_repository.dart';
import '../features/directory/directory_repository.dart';
import '../features/converts/converts_repository.dart';
import '../features/reports/reports_repository.dart';
import 'session_store.dart';

const String configuredApiBaseUrl = String.fromEnvironment(
  'API_BASE_URL',
  defaultValue: 'http://localhost:3000/api/v1/',
);

final sessionStoreProvider = Provider<SessionStore>((Ref ref) => SecureSessionStore());

final apiClientProvider = Provider<ApiClient>((Ref ref) {
  return ApiClient(
    baseUrl: configuredApiBaseUrl,
    sessionStore: ref.watch(sessionStoreProvider),
  );
});

final themeModeProvider = StateProvider<ThemeMode>((Ref ref) => ThemeMode.system);

final localeProvider = StateProvider<Locale>((Ref ref) => const Locale('en'));

final directoryRepositoryProvider = Provider<DirectoryRepository>((Ref ref) {
  return DirectoryRepository(ref.watch(apiClientProvider));
});

final adminReportsRepositoryProvider = Provider<AdminReportsRepository>((Ref ref) {
  return AdminReportsRepository(ref.watch(apiClientProvider));
});

final orgUnitsProvider = FutureProvider.autoDispose<List<OrgUnit>>((Ref ref) {
  return ref.watch(directoryRepositoryProvider).listUnits();
});

final countriesProvider = FutureProvider.autoDispose<List<SummaryTotal>>((Ref ref) {
  return ref.watch(adminReportsRepositoryProvider).listCountries();
});

final selectedCountryProvider = StateProvider<SummaryTotal?>((Ref ref) => null);

final convertsRepositoryProvider = Provider<ConvertsRepository>((Ref ref) {
  return ConvertsRepository(ref.watch(apiClientProvider));
});

final convertsProvider = FutureProvider.autoDispose<ConvertPage>((Ref ref) {
  return ref.watch(convertsRepositoryProvider).list();
});

final unassignedConvertsProvider = FutureProvider.autoDispose<List<UnassignedConvert>>((Ref ref) {
  return ref.watch(convertsRepositoryProvider).listUnassigned();
});

final reportsRepositoryProvider = Provider<ReportsRepository>((Ref ref) {
  return ReportsRepository(ref.watch(apiClientProvider));
});

final scopedCountProvider = FutureProvider.autoDispose.family<ScopedCount?, Session>((Ref ref, Session session) async {
  final reports = ref.watch(reportsRepositoryProvider);
  if (session.isGlobalAdmin) {
    return reports.grandTotal();
  }
  const reportingRoles = <String>{
    'COUNTRY_ADMIN',
    'REGION_LEADER',
    'PROVINCE_LEADER',
    'ZONE_LEADER',
    'AREA_LEADER',
    'PARISH_PASTOR',
    'SOUL_WINNER',
    'FOLLOW_UP_WORKER',
  };
  if (session.homePath == null || !session.roles.any(reportingRoles.contains)) {
    return null;
  }
  final units = await ref.watch(directoryRepositoryProvider).listUnits();
  OrgUnit? home;
  for (final unit in units) {
    if (unit.path == session.homePath) {
      home = unit;
      break;
    }
  }
  return home == null ? null : reports.countForUnit(home);
});

final regionTotalsProvider = FutureProvider.autoDispose.family<List<SummaryTotal>, String>((Ref ref, String countryId) {
  return ref.watch(adminReportsRepositoryProvider).listRegions(countryId);
});

final convertDetailProvider = FutureProvider.autoDispose.family<ConvertRecord, String>((Ref ref, String convertId) {
  return ref.watch(convertsRepositoryProvider).get(convertId);
});
