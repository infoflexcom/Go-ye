import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/app_providers.dart';
import 'package:goye/core/models.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/features/home/home_shell.dart';
import 'package:goye/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'requests the signed-in role home-unit total rather than a global total',
    (WidgetTester tester) async {
      const session = Session(
        accessToken: 'area-access',
        refreshToken: 'area-refresh',
        accessTokenExpiresInSeconds: 900,
        refreshTokenExpiresInSeconds: 3600,
        userId: 'area-user',
        roles: <String>{'AREA_LEADER'},
        homePath: 'n1.n2',
      );
      final store = MemorySessionStore()..session = session;
      final client = ApiClient(
        baseUrl: 'https://goye.test/api/v1/',
        sessionStore: store,
        httpClient: MockClient((http.Request request) async {
          if (request.url.path == '/api/v1/directory/org-units') {
            return http.Response(
              jsonEncode(<Map<String, Object?>>[
                <String, Object?>{
                  'id': 'area-1',
                  'type': 'AREA',
                  'name': 'Lagos Area',
                  'code': 'LAG-A',
                  'parentId': null,
                  'path': 'n1.n2',
                  'isActive': true,
                },
              ]),
              200,
            );
          }
          expect(request.url.path, '/api/v1/reports/org-units/area-1/converts');
          return http.Response(
            jsonEncode(<String, Object?>{
              'unitId': 'area-1',
              'total': 2,
              'byStage': <String, Object?>{'NEW_CONVERT': 2},
            }),
            200,
          );
        }),
      );

      await tester.pumpWidget(
        ProviderScope(
          overrides: <Override>[
            sessionStoreProvider.overrideWithValue(store),
            apiClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(
            localizationsDelegates: <LocalizationsDelegate<dynamic>>[
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: HomeShell(session: session),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Lagos Area'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('NEW CONVERT · 2'), findsOneWidget);
    },
  );
}
