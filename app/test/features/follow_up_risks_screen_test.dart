import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goye/core/api_client.dart';
import 'package:goye/core/app_providers.dart';
import 'package:goye/core/models.dart';
import 'package:goye/core/session_store.dart';
import 'package:goye/features/follow_up/follow_up_risks_screen.dart';
import 'package:goye/l10n/app_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  testWidgets(
    'shows scoped escalation and neglected convert lists and resolves an overdue action',
    (WidgetTester tester) async {
      Map<String, Object?>? completion;
      final store = MemorySessionStore()
        ..session = const Session(
          accessToken: 'risk-access',
          refreshToken: 'risk-refresh',
          accessTokenExpiresInSeconds: 900,
          refreshTokenExpiresInSeconds: 3600,
          userId: 'supervisor-1',
          roles: <String>{'AREA_LEADER'},
          homePath: 'u1.u2',
        );
      final escalation = <String, Object?>{
        'id': 'task-overdue-1',
        'convertId': 'convert-overdue-1',
        'parishId': 'parish-1',
        'parishName': 'Grace Parish',
        'taskType': 'CALL_24H',
        'occurrenceNumber': 1,
        'dueAt': '2026-11-05T09:00:00.000Z',
        'status': 'PENDING',
        'convertName': 'Ada Overdue',
        'phone': '+2348030000055',
        'overdueMinutes': 1560,
      };
      final client = ApiClient(
        baseUrl: 'https://goye.test/api/v1/',
        sessionStore: store,
        httpClient: MockClient((http.Request request) async {
          switch (request.url.path) {
            case '/api/v1/follow-up/escalations':
              return http.Response(
                jsonEncode(<String, Object?>{
                  'total': 1,
                  'items': <Map<String, Object?>>[escalation],
                }),
                200,
              );
            case '/api/v1/follow-up/neglected':
              return http.Response(
                jsonEncode(<String, Object?>{
                  'total': 1,
                  'items': <Map<String, Object?>>[
                    <String, Object?>{
                      'convertId': 'convert-neglected-1',
                      'parishId': 'parish-1',
                      'parishName': 'Grace Parish',
                      'convertName': 'Tunde Neglected',
                      'phone': '+2348030000056',
                      'oldestOverdueTaskType': 'PRAYER_DAY_3',
                      'oldestOverdueOccurrenceNumber': 1,
                      'oldestOverdueDueAt': '2026-11-04T09:00:00.000Z',
                      'overdueTaskCount': 2,
                      'neglectedForMinutes': 3000,
                    },
                  ],
                }),
                200,
              );
            case '/api/v1/follow-up/tasks/task-overdue-1/complete':
              completion = jsonDecode(request.body) as Map<String, Object?>;
              return http.Response(
                jsonEncode(<String, Object?>{
                  ...escalation,
                  'status': 'COMPLETED',
                  'outcome': 'COMPLETED',
                  'completedAt': '2026-11-06T11:00:00.000Z',
                  'completedBy': 'supervisor-1',
                }),
                200,
              );
            default:
              fail('Unexpected API request: ${request.url}');
          }
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
            home: FollowUpRisksScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Ada Overdue'), findsOneWidget);
      expect(find.text('1d 2h overdue'), findsOneWidget);
      expect(find.textContaining('Grace Parish'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('escalation-done-task-overdue-1')),
      );
      await tester.pump();
      expect(completion, <String, Object?>{'outcome': 'COMPLETED'});

      await tester.tap(find.text('Neglected'));
      await tester.pumpAndSettle();
      expect(find.text('Tunde Neglected'), findsOneWidget);
      expect(find.textContaining('2 overdue tasks'), findsOneWidget);
    },
  );
}
