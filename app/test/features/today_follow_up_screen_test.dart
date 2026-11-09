import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/app_providers.dart';
import 'package:goye/core/models.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/features/follow_up/today_follow_up_screen.dart';
import 'package:goye/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'shows Today follow-up work and sends one-tap DONE with the default outcome',
    (WidgetTester tester) async {
      Map<String, Object?>? completion;
      final store = MemorySessionStore()
        ..session = const Session(
          accessToken: 'today-access',
          refreshToken: 'today-refresh',
          accessTokenExpiresInSeconds: 900,
          refreshTokenExpiresInSeconds: 3600,
          userId: 'worker-1',
          roles: <String>{'FOLLOW_UP_WORKER'},
          homePath: 'u1.u2',
        );
      final task = <String, Object?>{
        'id': 'task-1',
        'convertId': 'convert-1',
        'parishId': 'parish-1',
        'taskType': 'CALL_24H',
        'occurrenceNumber': 1,
        'dueAt': '2026-11-07T09:00:00.000Z',
        'status': 'PENDING',
        'convertName': 'Ada Example',
        'phone': '+2348030000055',
      };
      final client = ApiClient(
        baseUrl: 'https://goye.test/api/v1/',
        sessionStore: store,
        httpClient: MockClient((http.Request request) async {
          if (request.url.path == '/api/v1/follow-up/today') {
            return http.Response(jsonEncode(<Map<String, Object?>>[task]), 200);
          }
          expect(request.url.path, '/api/v1/follow-up/tasks/task-1/complete');
          completion = jsonDecode(request.body) as Map<String, Object?>;
          return http.Response(
            jsonEncode(<String, Object?>{
              ...task,
              'status': 'COMPLETED',
              'outcome': 'COMPLETED',
              'completedAt': '2026-11-07T09:01:00.000Z',
              'completedBy': 'worker-1',
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
            home: TodayFollowUpScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ada Example'), findsOneWidget);
      expect(find.text('24-hour call'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('follow-up-done-task-1')),
      );
      await tester.pump();

      expect(completion, <String, Object?>{'outcome': 'COMPLETED'});
    },
  );
}
