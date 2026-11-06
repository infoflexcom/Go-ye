import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/app_providers.dart';
import 'package:goye/core/models.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/features/converts/converts_list_screen.dart';
import 'package:goye/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('uses a data table for the wide Windows layout', (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final store = MemorySessionStore()
      ..session = const Session(
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
        accessTokenExpiresInSeconds: 900,
        refreshTokenExpiresInSeconds: 3600,
        userId: 'user-1',
        roles: <String>{'AREA_LEADER'},
        homePath: 'n1.n2',
      );
    final client = ApiClient(
      baseUrl: 'https://goye.test/api/v1/',
      sessionStore: store,
      httpClient: MockClient((http.Request request) async {
        expect(request.url.path, '/api/v1/converts');
        return http.Response(
          jsonEncode(<String, Object?>{
            'total': 1,
            'items': <Map<String, Object?>>[
              <String, Object?>{
                'id': 'convert-1',
                'fullName': 'Ada Example',
                'phone': '+2348030000044',
                'registeredAtUnitId': 'area-1',
                'parishId': 'parish-1',
                'stage': 'NEW_CONVERT',
                'createdAt': '2026-11-06T12:00:00.000Z',
              },
            ],
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
          home: ConvertsListScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(DataTable), findsOneWidget);
    expect(find.text('Ada Example'), findsOneWidget);
    expect(find.text('NEW CONVERT'), findsOneWidget);
  });
}
