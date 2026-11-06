import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/app_providers.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/main.dart';
import 'package:http/testing.dart';

void main() {
  testWidgets('shows the OTP login screen before a secure session exists', (WidgetTester tester) async {
    final store = MemorySessionStore();
    final client = ApiClient(
      baseUrl: 'https://goye.test/api/v1/',
      sessionStore: store,
      httpClient: MockClient((_) async => throw UnimplementedError()),
    );

    await tester.pumpWidget(
      ProviderScope(
        overrides: <Override>[
          sessionStoreProvider.overrideWithValue(store),
          apiClientProvider.overrideWithValue(client),
        ],
        child: const GoYeApp(),
      ),
    );
    await tester.pump();

    expect(find.text('Welcome to Go-Ye'), findsOneWidget);
    expect(find.text('Send sign-in code'), findsOneWidget);
  });
}
