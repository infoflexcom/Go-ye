import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/app_providers.dart';
import 'package:goye/core/models.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/features/directory/hierarchy_browser_screen.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('renders only hierarchy units returned by the scoped API', (
    WidgetTester tester,
  ) async {
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
        expect(request.headers['authorization'], 'Bearer test-access');
        expect(request.url.path, '/api/v1/directory/org-units');
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
            <String, Object?>{
              'id': 'parish-1',
              'type': 'PARISH',
              'name': 'Grace Parish',
              'code': 'GRC-P',
              'parentId': 'area-1',
              'path': 'n1.n2.n3',
              'isActive': true,
            },
          ]),
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
        child: const MaterialApp(home: HierarchyBrowserScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Lagos Area'), findsOneWidget);
    expect(find.text('Grace Parish'), findsOneWidget);
    expect(find.textContaining('COUNTRY'), findsNothing);
  });
}
