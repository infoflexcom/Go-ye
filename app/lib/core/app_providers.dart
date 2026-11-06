import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api_client.dart';
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
