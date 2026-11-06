import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
import 'models.dart';
import '../features/admin/admin_reports_repository.dart';
import '../features/directory/directory_repository.dart';
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
