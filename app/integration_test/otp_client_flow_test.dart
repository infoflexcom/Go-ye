import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/app_providers.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/main.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'signs in through the same app route used on Android and Windows',
    (WidgetTester tester) async {
      final store = MemorySessionStore();
      final client = ApiClient(
        baseUrl: 'https://goye.integration.test/api/v1/',
        sessionStore: store,
        httpClient: MockClient((http.Request request) async {
          if (request.url.path.endsWith('/request')) {
            return http.Response('{"accepted":true}', 202);
          }
          if (request.url.path.endsWith('/verify')) {
            return http.Response(
              jsonEncode(<String, Object?>{
                'accessToken': _jwt(),
                'refreshToken': 'integration-test-refresh-token',
                'accessTokenExpiresInSeconds': 900,
                'refreshTokenExpiresInSeconds': 3600,
              }),
              200,
            );
          }
          if (request.url.path == '/api/v1/directory/org-units') {
            return http.Response('[]', 200);
          }
          if (request.url.path == '/api/v1/reports/org-units/area-1/converts') {
            return http.Response(
              '{"unitId":"area-1","total":0,"byStage":{}}',
              200,
            );
          }
          return http.Response('{}', 404);
        }),
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
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, '+2348030000044');
      await tester.tap(find.text('Send sign-in code'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField).first, '123456');
      await tester.tap(find.text('Sign in securely'));
      await tester.pumpAndSettle();

      expect(find.text('Signed in securely'), findsOneWidget);
      expect(store.session, isNotNull);
    },
  );
}

String _jwt() {
  String encode(Object value) =>
      base64Url.encode(utf8.encode(jsonEncode(value))).replaceAll('=', '');
  return '${encode(<String, Object?>{'alg': 'none'})}.${encode(<String, Object?>{
    'sub': 'integration-user',
    'roles': <String>['AREA_LEADER'],
    'homePath': 'n1.n2',
  })}.signature';
}
