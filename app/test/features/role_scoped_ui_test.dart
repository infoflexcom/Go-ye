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
    'renders the server-scoped count for every hierarchy role in the UI',
    (WidgetTester tester) async {
      final roles = <({String role, String level})>[
        (role: 'COUNTRY_ADMIN', level: 'Country'),
        (role: 'REGION_LEADER', level: 'Region'),
        (role: 'PROVINCE_LEADER', level: 'Province'),
        (role: 'ZONE_LEADER', level: 'Zone'),
        (role: 'AREA_LEADER', level: 'Area'),
        (role: 'PARISH_PASTOR', level: 'Parish'),
      ];

      for (var index = 0; index < roles.length; index += 1) {
        final role = roles[index];
        final session = Session(
          accessToken: 'token-$index',
          refreshToken: 'refresh-$index',
          accessTokenExpiresInSeconds: 900,
          refreshTokenExpiresInSeconds: 3600,
          userId: 'user-$index',
          roles: <String>{role.role},
          homePath: 'n$index',
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
                    'id': 'unit-$index',
                    'type': role.level.toUpperCase(),
                    'name': '${role.level} home',
                    'code': 'CODE-$index',
                    'parentId': null,
                    'path': 'n$index',
                    'isActive': true,
                  },
                ]),
                200,
              );
            }
            expect(
              request.url.path,
              '/api/v1/reports/org-units/unit-$index/converts',
            );
            return http.Response(
              jsonEncode(<String, Object?>{
                'unitId': 'unit-$index',
                'total': index + 1,
                'byStage': <String, Object?>{},
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
            child: MaterialApp(
              localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
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

        expect(find.text('${role.level} home'), findsOneWidget);
        expect(find.text('${index + 1}'), findsOneWidget);
      }
    },
  );

  testWidgets('renders the Global Admin grand total in the UI', (
    WidgetTester tester,
  ) async {
    const session = Session(
      accessToken: 'global-token',
      refreshToken: 'global-refresh',
      accessTokenExpiresInSeconds: 900,
      refreshTokenExpiresInSeconds: 3600,
      userId: 'global-user',
      roles: <String>{'GLOBAL_ADMIN'},
      homePath: null,
    );
    final store = MemorySessionStore()..session = session;
    final client = ApiClient(
      baseUrl: 'https://goye.test/api/v1/',
      sessionStore: store,
      httpClient: MockClient((http.Request request) async {
        expect(request.url.path, '/api/v1/admin/reports/grand-total');
        return http.Response('{"total":7}', 200);
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

    expect(find.text('All countries'), findsOneWidget);
    expect(find.text('7'), findsOneWidget);
  });
}
