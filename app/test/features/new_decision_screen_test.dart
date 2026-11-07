import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/app_providers.dart';
import 'package:goye/core/models.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/features/converts/new_decision_screen.dart';
import 'package:goye/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets('does not save a decision until affirmative consent is checked', (
    WidgetTester tester,
  ) async {
    Map<String, Object?>? submitted;
    final store = MemorySessionStore()
      ..session = const Session(
        accessToken: 'test-access',
        refreshToken: 'test-refresh',
        accessTokenExpiresInSeconds: 900,
        refreshTokenExpiresInSeconds: 3600,
        userId: 'user-1',
        roles: <String>{'SOUL_WINNER'},
        homePath: 'n1.n2',
      );
    final client = ApiClient(
      baseUrl: 'https://goye.test/api/v1/',
      sessionStore: store,
      httpClient: MockClient((http.Request request) async {
        submitted = jsonDecode(request.body) as Map<String, Object?>;
        return http.Response(
          jsonEncode(<String, Object?>{
            'id': 'convert-1',
            'fullName': 'Ada Example',
            'registeredAtUnitId': 'unit-1',
            'stage': 'NEW_CONVERT',
            'createdAt': '2026-11-06T12:00:00.000Z',
          }),
          201,
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
          home: Scaffold(
            body: NewDecisionScreen(isGlobalAdmin: false),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).first, 'Ada Example');
    await tester.tap(find.text('Save decision'));
    await tester.pump();
    expect(submitted, isNull);

    await tester.tap(find.byType(Checkbox));
    await tester.tap(find.text('Save decision'));
    await tester.pump();

    expect(submitted?['fullName'], 'Ada Example');
    expect(submitted?['consent'], <String, Object?>{
      'granted': true,
      'version': '2026-11',
      'method': 'DIGITAL',
    });
  });
}
